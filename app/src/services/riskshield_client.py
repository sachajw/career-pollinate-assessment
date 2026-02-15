"""RiskShield API client for fraud validation.

Provides a robust HTTP client with:
- Exponential backoff retry logic
- Circuit breaker pattern
- Comprehensive error handling
- Structured logging
- Azure Key Vault integration for API keys
"""

import asyncio
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Any

import httpx
from tenacity import (
    RetryError,
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
)

from src.core.config import get_settings
from src.core.logging import get_logger

logger = get_logger(__name__)


class CircuitState(str, Enum):
    """Circuit breaker states."""

    CLOSED = "CLOSED"  # Normal operation
    OPEN = "OPEN"  # Failing, reject all requests
    HALF_OPEN = "HALF_OPEN"  # Testing if recovered


class RiskShieldError(Exception):
    """Base exception for RiskShield API errors."""

    def __init__(self, message: str, *, status_code: int | None = None, details: Any = None):
        super().__init__(message)
        self.status_code = status_code
        self.details = details


class RiskShieldTimeoutError(RiskShieldError):
    """Raised when API request times out."""

    def __init__(self, message: str = "Request timed out"):
        super().__init__(message, status_code=408)


class RiskShieldRateLimitError(RiskShieldError):
    """Raised when API rate limit is exceeded."""

    def __init__(self, message: str = "Rate limit exceeded", retry_after: int | None = None):
        super().__init__(message, status_code=429)
        self.retry_after = retry_after


class RiskShieldAuthError(RiskShieldError):
    """Raised when API authentication fails."""

    def __init__(self, message: str = "Authentication failed"):
        super().__init__(message, status_code=401)


class RiskShieldServerError(RiskShieldError):
    """Raised when API returns a server error."""

    def __init__(self, message: str = "Server error", status_code: int = 500):
        super().__init__(message, status_code=status_code)


@dataclass
class RiskShieldResult:
    """Result from RiskShield validation."""

    risk_score: int
    risk_level: str
    additional_data: dict[str, Any] | None = None


class CircuitBreaker:
    """Simple circuit breaker for API fault tolerance.

    Prevents cascading failures by temporarily blocking requests
    when the upstream service is unhealthy.
    """

    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        half_open_max_calls: int = 3,
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls

        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._last_failure_time: float | None = None
        self._half_open_calls = 0

    @property
    def state(self) -> CircuitState:
        """Get current circuit state."""
        return self._state

    def can_execute(self) -> bool:
        """Check if request should be allowed."""
        if self._state == CircuitState.CLOSED:
            return True

        if self._state == CircuitState.OPEN:
            # Check if recovery timeout has passed
            if self._last_failure_time is None:
                self._state = CircuitState.HALF_OPEN
                return True

            elapsed = time.monotonic() - self._last_failure_time
            if elapsed >= self.recovery_timeout:
                self._state = CircuitState.HALF_OPEN
                self._half_open_calls = 0
                return True
            return False

        # HALF_OPEN state
        if self._half_open_calls < self.half_open_max_calls:
            self._half_open_calls += 1
            return True
        return False

    def record_success(self) -> None:
        """Record successful request."""
        if self._state == CircuitState.HALF_OPEN:
            self._state = CircuitState.CLOSED
            self._failure_count = 0
            logger.info("circuit_breaker_recovered")

    def record_failure(self) -> None:
        """Record failed request."""
        self._failure_count += 1
        self._last_failure_time = time.monotonic()

        if self._state == CircuitState.HALF_OPEN:
            self._state = CircuitState.OPEN
            logger.warning("circuit_breaker_opened_half_open_failed")
        elif self._failure_count >= self.failure_threshold:
            self._state = CircuitState.OPEN
            logger.warning(
                "circuit_breaker_opened",
                failure_count=self._failure_count,
                threshold=self.failure_threshold,
            )


class RiskShieldClient:
    """HTTP client for RiskShield fraud validation API.

    Features:
    - Exponential backoff retry with configurable attempts
    - Circuit breaker for fault tolerance
    - Comprehensive error handling
    - Structured logging with correlation IDs
    """

    def __init__(self) -> None:
        self._settings = get_settings()
        self._circuit_breaker = CircuitBreaker()
        self._api_key: str | None = None
        self._client: httpx.AsyncClient | None = None

    async def _get_api_key(self) -> str:
        """Get API key from settings or Key Vault."""
        if self._api_key:
            return self._api_key

        # First, check if API key is in settings (for local dev)
        if self._settings.riskshield_api_key:
            self._api_key = self._settings.riskshield_api_key
            return self._api_key

        # Try to load from Key Vault
        if self._settings.key_vault_url:
            try:
                from azure.identity.aio import DefaultAzureCredential as AsyncDefaultAzureCredential
                from azure.keyvault.secrets.aio import SecretClient as AsyncSecretClient

                async with AsyncDefaultAzureCredential() as credential:
                    async with AsyncSecretClient(
                        vault_url=self._settings.key_vault_url,
                        credential=credential,
                    ) as client:
                        secret = await client.get_secret("RISKSHIELD-API-KEY")
                        self._api_key = secret.value
                        logger.info("api_key_loaded_from_key_vault")
                        return self._api_key
            except Exception as e:
                logger.error("failed_to_load_api_key_from_key_vault", error=str(e))
                raise RiskShieldAuthError(
                    "Failed to load API key from Key Vault"
                ) from e

        raise RiskShieldAuthError("No API key configured")

    async def _get_client(self) -> httpx.AsyncClient:
        """Get or create HTTP client."""
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=httpx.Timeout(self._settings.riskshield_api_timeout),
                follow_redirects=True,
            )
        return self._client

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type(RiskShieldServerError),
        reraise=True,
    )
    async def validate(
        self,
        first_name: str,
        last_name: str,
        id_number: str,
    ) -> RiskShieldResult:
        """Validate a loan applicant through RiskShield API.

        Args:
            first_name: Applicant's first name.
            last_name: Applicant's last name.
            id_number: Applicant's ID number.

        Returns:
            RiskShieldResult with risk score and level.

        Raises:
            RiskShieldAuthError: Authentication failed.
            RiskShieldRateLimitError: Rate limit exceeded.
            RiskShieldTimeoutError: Request timed out.
            RiskShieldServerError: Server error.
            RiskShieldError: Other API errors.
        """
        # Check circuit breaker
        if not self._circuit_breaker.can_execute():
            logger.warning("circuit_breaker_blocking_request")
            raise RiskShieldServerError(
                "RiskShield service temporarily unavailable",
                status_code=503,
            )

        api_key = await self._get_api_key()
        client = await self._get_client()

        payload = {
            "firstName": first_name,
            "lastName": last_name,
            "idNumber": id_number,
        }

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        url = f"{self._settings.riskshield_api_url}/validate"

        try:
            logger.info(
                "riskshield_request_started",
                url=url,
                method="POST",
            )

            response = await client.post(url, json=payload, headers=headers)

            # Handle response status
            if response.status_code == 200:
                self._circuit_breaker.record_success()
                data = response.json()
                result = RiskShieldResult(
                    risk_score=data.get("riskScore", 0),
                    risk_level=data.get("riskLevel", "UNKNOWN"),
                    additional_data=data.get("additionalData"),
                )
                logger.info(
                    "riskshield_request_succeeded",
                    risk_score=result.risk_score,
                    risk_level=result.risk_level,
                )
                return result

            if response.status_code == 401:
                # Clear cached API key on auth failure
                self._api_key = None
                self._circuit_breaker.record_failure()
                raise RiskShieldAuthError()

            if response.status_code == 429:
                self._circuit_breaker.record_failure()
                retry_after = response.headers.get("Retry-After")
                raise RiskShieldRateLimitError(
                    retry_after=int(retry_after) if retry_after else None
                )

            if response.status_code >= 500:
                self._circuit_breaker.record_failure()
                raise RiskShieldServerError(
                    f"Server error: {response.status_code}",
                    status_code=response.status_code,
                )

            # Other client errors
            self._circuit_breaker.record_failure()
            raise RiskShieldError(
                f"API error: {response.status_code}",
                status_code=response.status_code,
                details=response.json() if response.content else None,
            )

        except httpx.TimeoutException as e:
            self._circuit_breaker.record_failure()
            logger.error("riskshield_request_timeout", error=str(e))
            raise RiskShieldTimeoutError() from e

        except httpx.RequestError as e:
            self._circuit_breaker.record_failure()
            logger.error("riskshield_request_error", error=str(e))
            raise RiskShieldError(
                f"Request failed: {str(e)}",
                status_code=503,
            ) from e

        except RetryError as e:
            self._circuit_breaker.record_failure()
            logger.error("riskshield_retry_exhausted", error=str(e))
            raise RiskShieldServerError(
                "Max retries exceeded",
                status_code=503,
            ) from e

    async def close(self) -> None:
        """Close the HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None


# Global client instance
_client: RiskShieldClient | None = None


def get_riskshield_client() -> RiskShieldClient:
    """Get or create global RiskShield client instance."""
    global _client
    if _client is None:
        _client = RiskShieldClient()
    return _client


async def close_riskshield_client() -> None:
    """Close global RiskShield client."""
    global _client
    if _client:
        await _client.close()
        _client = None
