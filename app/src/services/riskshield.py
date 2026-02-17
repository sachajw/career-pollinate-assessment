"""RiskShield API client for fraud risk validation.

Implements resilience patterns as defined in ADR-002:
- Timeout handling with httpx
- Retry logic with tenacity (exponential backoff)
- Structured logging with structlog
"""

import logging

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


class RiskShieldError(Exception):
    """Base exception for RiskShield errors."""
    pass


class RiskShieldTimeoutError(RiskShieldError):
    """RiskShield API timeout."""
    pass


class RiskShieldUnavailableError(RiskShieldError):
    """RiskShield API unavailable after retries."""
    pass


class RiskShieldClient:
    """Client for RiskShield API integration.

    Implements resilience patterns:
    - Timeout handling with configurable timeouts
    - Retry logic with exponential backoff for transient failures
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
        self.client = httpx.AsyncClient(
            base_url=api_url,
            timeout=HTTP_TIMEOUT,
            headers={"X-API-Key": api_key} if api_key else {},
        )

    async def validate_applicant(
        self, request: ApplicantValidationRequest
    ) -> tuple[int, RiskLevel]:
        """Validate applicant and return risk score.

        Uses retry logic with exponential backoff for transient failures.

        Args:
            request: Applicant validation request

        Returns:
            Tuple of (risk_score, risk_level)

        Raises:
            RiskShieldTimeoutError: If API call times out
            RiskShieldUnavailableError: If API is unavailable after retries
        """
        logger.info(
            "Validating applicant",
            first_name=request.firstName,
            last_name=request.lastName,
            id_number_hash=hash(request.idNumber) % 1000,
        )

        # DEMO: Generate deterministic risk score from ID number
        # In production, this would call _validate_with_retry()
        risk_score = self._calculate_demo_risk_score(request.idNumber)
        risk_level = self._classify_risk_level(risk_score)

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
