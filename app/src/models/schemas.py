"""Pydantic models for API request and response schemas.

Provides data validation and serialization for:
- Validation requests
- Risk score responses
- Error responses
"""

from enum import Enum
from typing import Any
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator, model_validator


class RiskLevel(str, Enum):
    """Risk level classification for loan applicants."""

    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"

    @classmethod
    def from_score(cls, score: int) -> "RiskLevel":
        """Determine risk level from numerical score.

        Args:
            score: Risk score from 0-100.

        Returns:
            RiskLevel enum value.
        """
        if score < 30:
            return cls.LOW
        elif score < 60:
            return cls.MEDIUM
        elif score < 80:
            return cls.HIGH
        return cls.CRITICAL


class ValidationRequest(BaseModel):
    """Request model for loan applicant validation.

    Attributes:
        first_name: Applicant's first name.
        last_name: Applicant's last name.
        id_number: South African ID number (13 digits).
    """

    first_name: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Applicant's first name",
        examples=["Jane"],
    )
    last_name: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Applicant's last name",
        examples=["Doe"],
    )
    id_number: str = Field(
        ...,
        min_length=13,
        max_length=13,
        pattern=r"^\d{13}$",
        description="South African ID number (13 digits)",
        examples=["9001011234088"],
    )

    @field_validator("first_name", "last_name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        """Validate and sanitize name fields."""
        # Remove extra whitespace
        v = " ".join(v.split())
        # Check for valid characters (letters, spaces, hyphens, apostrophes)
        if not all(c.isalpha() or c in " -'" for c in v):
            raise ValueError("Name must contain only letters, spaces, hyphens, and apostrophes")
        return v

    @field_validator("id_number")
    @classmethod
    def validate_id_number(cls, v: str) -> str:
        """Validate South African ID number format.

        Performs basic validation:
        - Must be exactly 13 digits
        - Date portion must be valid (YYMMDD)
        - Must pass Luhn checksum validation
        """
        if not v.isdigit():
            raise ValueError("ID number must contain only digits")

        if len(v) != 13:
            raise ValueError("ID number must be exactly 13 digits")

        # Validate date portion (YYMMDD)
        try:
            year = int(v[0:2])
            month = int(v[2:4])
            day = int(v[4:6])

            # Basic month validation
            if not 1 <= month <= 12:
                raise ValueError("Invalid month in ID number")

            # Basic day validation
            if not 1 <= day <= 31:
                raise ValueError("Invalid day in ID number")

        except ValueError as e:
            raise ValueError(f"Invalid date in ID number: {e}") from e

        # Luhn algorithm validation
        if not cls._luhn_check(v):
            raise ValueError("Invalid ID number (checksum failed)")

        return v

    @staticmethod
    def _luhn_check(id_number: str) -> bool:
        """Perform Luhn algorithm checksum validation.

        Args:
            id_number: 13-digit ID number string.

        Returns:
            True if checksum passes, False otherwise.
        """
        digits = [int(d) for d in id_number]
        odd_digits = digits[-1::-2]
        even_digits = digits[-2::-2]

        checksum = sum(odd_digits)

        for d in even_digits:
            doubled = d * 2
            checksum += doubled - 9 if doubled > 9 else doubled

        return checksum % 10 == 0


class ValidationResponse(BaseModel):
    """Response model for successful validation.

    Attributes:
        risk_score: Numerical risk score (0-100).
        risk_level: Categorical risk classification.
        correlation_id: Unique identifier for request tracing.
        additional_data: Optional additional metadata from RiskShield.
    """

    risk_score: int = Field(
        ...,
        ge=0,
        le=100,
        description="Risk score from 0 (low risk) to 100 (high risk)",
        examples=[72],
    )
    risk_level: RiskLevel = Field(
        ...,
        description="Categorical risk classification",
        examples=[RiskLevel.MEDIUM],
    )
    correlation_id: UUID = Field(
        default_factory=uuid4,
        description="Unique identifier for request tracing",
    )
    additional_data: dict[str, Any] | None = Field(
        default=None,
        description="Optional additional metadata from RiskShield",
    )

    @model_validator(mode="after")
    def validate_risk_level_matches_score(self) -> "ValidationResponse":
        """Ensure risk level is consistent with score."""
        expected_level = RiskLevel.from_score(self.risk_score)
        if self.risk_level != expected_level:
            self.risk_level = expected_level
        return self


class ErrorCode(str, Enum):
    """Standardized error codes for API responses."""

    VALIDATION_ERROR = "VALIDATION_ERROR"
    AUTHENTICATION_ERROR = "AUTHENTICATION_ERROR"
    RATE_LIMIT_ERROR = "RATE_LIMIT_ERROR"
    UPSTREAM_ERROR = "UPSTREAM_ERROR"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    TIMEOUT_ERROR = "TIMEOUT_ERROR"


class ErrorDetail(BaseModel):
    """Detailed error information."""

    field: str | None = Field(
        default=None,
        description="Field that caused the error (if applicable)",
    )
    message: str = Field(
        ...,
        description="Human-readable error message",
    )
    code: str | None = Field(
        default=None,
        description="Additional error code for programmatic handling",
    )


class ErrorResponse(BaseModel):
    """Standard error response model.

    Attributes:
        error: Error code and message.
        correlation_id: Request correlation ID for debugging.
        details: Optional list of detailed error information.
    """

    error: ErrorCode = Field(
        ...,
        description="Error code",
    )
    message: str = Field(
        ...,
        description="Human-readable error message",
    )
    correlation_id: UUID = Field(
        default_factory=uuid4,
        description="Unique identifier for request tracing",
    )
    details: list[ErrorDetail] | None = Field(
        default=None,
        description="Optional list of detailed error information",
    )


class HealthResponse(BaseModel):
    """Health check response model."""

    status: Literal["healthy", "unhealthy"] = Field(
        default="healthy",
        description="Health status",
    )
    version: str = Field(
        ...,
        description="Application version",
    )
    environment: str = Field(
        ...,
        description="Deployment environment",
    )
    checks: dict[str, bool] | None = Field(
        default=None,
        description="Optional health check details",
    )


class ReadyResponse(BaseModel):
    """Readiness check response model."""

    status: Literal["ready", "not_ready"] = Field(
        default="ready",
        description="Readiness status",
    )
    checks: dict[str, bool] = Field(
        default_factory=dict,
        description="Readiness check details",
    )


# Import Literal for type hints
from typing import Literal

# Re-export for convenience
__all__ = [
    "RiskLevel",
    "ValidationRequest",
    "ValidationResponse",
    "ErrorCode",
    "ErrorDetail",
    "ErrorResponse",
    "HealthResponse",
    "ReadyResponse",
]
