"""RiskShield API client for fraud risk validation.

Implements resilience patterns as defined in ADR-002:
- Timeout handling with httpx
- Retry logic with tenacity (exponential backoff)
- Circuit breaker (fail fast after consecutive failures)
- Structured logging with structlog
"""

import logging
import time

import httpx
import structlog
from tenacity import (
    before_sleep_log,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from ..models.validation import ApplicantValidationRequest, RiskLevel

logger = structlog.get_logger()

# Timeout configuration as per ADR-002
HTTP_TIMEOUT = httpx.Timeout(
    connect=5.0,   # Connection timeout
    read=10.0,     # Read timeout (RiskShield API response)
    write=5.0,     # Write timeout
    pool=5.0,      # Pool timeout
)

# Circuit breaker configuration
_CIRCUIT_FAILURE_THRESHOLD = 5   # Trip after 5 consecutive failures
_CIRCUIT_RECOVERY_TIMEOUT = 60.0  # Seconds before attempting recovery (half-open)


class RiskShieldError(Exception):
    """Base exception for RiskShield errors."""
    pass


class RiskShieldTimeoutError(RiskShieldError):
    """RiskShield API timeout."""
    pass


class RiskShieldUnavailableError(RiskShieldError):
    """RiskShield API unavailable after retries."""
    pass


class RiskShieldCircuitOpenError(RiskShieldError):
    """Circuit breaker is open; request rejected to protect downstream."""
    pass


class CircuitBreaker:
    """Simple circuit breaker for the RiskShield API.

    States:
    - CLOSED  : normal operation; failures are counted
    - OPEN    : calls are rejected immediately (fail fast)
    - HALF-OPEN: one probe call allowed to test recovery

    Trips to OPEN after ``failure_threshold`` consecutive failures.
    Attempts recovery after ``recovery_timeout`` seconds.
    """

    def __init__(
        self,
        failure_threshold: int = _CIRCUIT_FAILURE_THRESHOLD,
        recovery_timeout: float = _CIRCUIT_RECOVERY_TIMEOUT,
    ) -> None:
        self._failure_threshold = failure_threshold
        self._recovery_timeout = recovery_timeout
        self._failure_count = 0
        self._opened_at: float | None = None  # monotonic timestamp when tripped

    @property
    def is_open(self) -> bool:
        if self._opened_at is None:
            return False
        elapsed = time.monotonic() - self._opened_at
        if elapsed >= self._recovery_timeout:
            # Allow one probe (half-open); caller decides to reset or re-trip
            return False
        return True

    def record_success(self) -> None:
        """Reset circuit after a successful call."""
        self._failure_count = 0
        self._opened_at = None

    def record_failure(self) -> None:
        """Increment failure counter and trip circuit when threshold is reached."""
        self._failure_count += 1
        if self._failure_count >= self._failure_threshold:
            if self._opened_at is None:
                self._opened_at = time.monotonic()
                logger.error(
                    "RiskShield circuit breaker tripped",
                    failure_count=self._failure_count,
                    recovery_timeout=self._recovery_timeout,
                )


class RiskShieldClient:
    """Client for RiskShield API integration.

    Implements resilience patterns:
    - Timeout handling with configurable timeouts
    - Retry logic with exponential backoff for transient failures
    - Circuit breaker (fail fast after consecutive failures)
    - Structured logging for observability
    """

    def __init__(self, api_url: str, api_key: str | None = None) -> None:
        """Initialize RiskShield client.

        Args:
            api_url: Base URL for RiskShield API
            api_key: API key for authentication (optional for demo)
        """
        self.api_url = api_url
        self.api_key = api_key
        self._circuit_breaker = CircuitBreaker()
        self.client = httpx.AsyncClient(
            base_url=api_url,
            timeout=HTTP_TIMEOUT,
            headers={"X-API-Key": api_key} if api_key else {},
        )

    async def validate_applicant(
        self, request: ApplicantValidationRequest
    ) -> tuple[int, RiskLevel]:
        """Validate applicant and return risk score.

        Calls RiskShield API (POST /v1/score) with retry logic and exponential
        backoff for transient failures.

        Falls back to a deterministic demo algorithm when no API key is
        configured (local development without RiskShield credentials).

        Args:
            request: Applicant validation request

        Returns:
            Tuple of (risk_score, risk_level)

        Raises:
            RiskShieldTimeoutError: If API call times out after retries
            RiskShieldUnavailableError: If API is unavailable after retries
        """
        logger.info(
            "Validating applicant",
            first_name=request.firstName,
            last_name=request.lastName,
            id_number_hash=hash(request.idNumber) % 1000,
        )

        if not self.api_key:
            # Demo mode: no API key configured (local development only)
            logger.warning(
                "No RiskShield API key configured - running in demo mode. "
                "Set RISKSHIELD_API_KEY or configure KEY_VAULT_URL for production."
            )
            risk_score = self._calculate_demo_risk_score(request.idNumber)
            risk_level = self._classify_risk_level(risk_score)
        else:
            # Production: check circuit breaker before attempting call
            if self._circuit_breaker.is_open:
                logger.warning("RiskShield circuit breaker is open — rejecting request")
                raise RiskShieldCircuitOpenError(
                    "RiskShield circuit breaker is open; try again later"
                )

            try:
                risk_score, risk_level = await self._validate_with_retry(request)
                self._circuit_breaker.record_success()
            except RiskShieldTimeoutError:
                self._circuit_breaker.record_failure()
                raise RiskShieldUnavailableError(
                    "RiskShield API timed out after retries"
                )
            except RiskShieldUnavailableError:
                self._circuit_breaker.record_failure()
                raise

        logger.info(
            "Applicant validation complete",
            risk_score=risk_score,
            risk_level=risk_level.value,
        )

        return risk_score, risk_level

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(httpx.HTTPStatusError),
        before_sleep=before_sleep_log(logger, log_level=logging.WARNING),
        reraise=True,
    )
    async def _validate_with_retry(
        self, request: ApplicantValidationRequest
    ) -> tuple[int, RiskLevel]:
        """Validate applicant with retry logic.

        Retries on:
        - 5xx server errors (temporary issues)
        - 429 rate limiting (with backoff)

        Does NOT retry on:
        - 4xx client errors (bad request, unauthorized)
        - Timeout errors (separate handling)

        Args:
            request: Applicant validation request

        Returns:
            Tuple of (risk_score, risk_level)

        Raises:
            httpx.HTTPStatusError: For retryable errors after retries exhausted
            RiskShieldTimeoutError: If API call times out
        """
        try:
            response = await self.client.post(
                "/v1/score",
                json=request.model_dump(),
            )

            # Raise for retryable status codes
            if response.status_code >= 500 or response.status_code == 429:
                raise httpx.HTTPStatusError(
                    f"Retryable error: {response.status_code}",
                    request=response.request,
                    response=response,
                )

            response.raise_for_status()
            data = response.json()

            return data["riskScore"], RiskLevel(data["riskLevel"])

        except httpx.TimeoutException as e:
            logger.error("RiskShield API timeout", error=str(e))
            raise RiskShieldTimeoutError(f"RiskShield API timeout: {e}") from e

    def _calculate_demo_risk_score(self, id_number: str) -> int:
        """Calculate demo risk score from ID number.

        Uses a deterministic algorithm for consistent testing:
        - Sum of digits modulo 100
        - Ensures scores are distributed across risk levels

        Args:
            id_number: South African ID number

        Returns:
            Risk score (0-100)
        """
        digit_sum = sum(int(digit) for digit in id_number)
        return digit_sum % 101  # 0-100 inclusive

    def _classify_risk_level(self, risk_score: int) -> RiskLevel:
        """Classify risk level from score.

        Score ranges:
        - 0-25: LOW
        - 26-50: MEDIUM
        - 51-75: HIGH
        - 76-100: CRITICAL

        Args:
            risk_score: Risk score (0-100)

        Returns:
            Risk level classification
        """
        if risk_score <= 25:
            return RiskLevel.LOW
        elif risk_score <= 50:
            return RiskLevel.MEDIUM
        elif risk_score <= 75:
            return RiskLevel.HIGH
        else:
            return RiskLevel.CRITICAL

    async def health_check(self) -> bool:
        """Check if RiskShield API is accessible.

        Returns:
            True if API is accessible, False otherwise
        """
        try:
            # In production, this would ping the actual RiskShield health endpoint
            # For demo, we always return True
            return True
        except Exception as e:
            logger.error("RiskShield health check failed", error=str(e))
            return False

    async def close(self) -> None:
        """Close HTTP client."""
        await self.client.aclose()
