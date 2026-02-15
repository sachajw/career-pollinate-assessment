"""RiskShield API client for fraud risk validation."""

import httpx
import structlog

from ..models.validation import ApplicantValidationRequest, RiskLevel

logger = structlog.get_logger()


class RiskShieldClient:
    """Client for RiskShield API integration."""

    def __init__(self, api_url: str, api_key: str | None = None) -> None:
        """Initialize RiskShield client.

        Args:
            api_url: Base URL for RiskShield API
            api_key: API key for authentication (optional for demo)
        """
        self.api_url = api_url
        self.api_key = api_key
        self.client = httpx.AsyncClient(timeout=30.0)

    async def validate_applicant(
        self, request: ApplicantValidationRequest
    ) -> tuple[int, RiskLevel]:
        """Validate applicant and return risk score.

        Args:
            request: Applicant validation request

        Returns:
            Tuple of (risk_score, risk_level)

        Note:
            This is a DEMO implementation that generates deterministic risk scores
            based on ID number for testing. In production, this would call the
            actual RiskShield API.
        """
        logger.info(
            "Validating applicant",
            first_name=request.firstName,
            last_name=request.lastName,
            id_number_hash=hash(request.idNumber) % 1000,
        )

        # DEMO: Generate deterministic risk score from ID number
        # In production, this would be replaced with actual RiskShield API call
        risk_score = self._calculate_demo_risk_score(request.idNumber)
        risk_level = self._classify_risk_level(risk_score)

        logger.info(
            "Applicant validation complete",
            risk_score=risk_score,
            risk_level=risk_level.value,
        )

        return risk_score, risk_level

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
