"""Pydantic models for applicant validation."""

from enum import Enum
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, field_validator


class RiskLevel(str, Enum):
    """Risk level classification."""

    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class ApplicantValidationRequest(BaseModel):
    """Request model for applicant validation."""

    firstName: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Applicant's first name",
        examples=["Jane"],
    )
    lastName: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Applicant's last name",
        examples=["Doe"],
    )
    idNumber: str = Field(
        ...,
        min_length=13,
        max_length=13,
        description="South African ID number (13 digits)",
        examples=["9001011234088"],
    )

    @field_validator("idNumber")
    @classmethod
    def validate_id_number(cls, v: str) -> str:
        """Validate South African ID number format."""
        if not v.isdigit():
            raise ValueError("ID number must contain only digits")
        if len(v) != 13:
            raise ValueError("ID number must be exactly 13 digits")
        return v


class ApplicantValidationResponse(BaseModel):
    """Response model for applicant validation."""

    riskScore: int = Field(
        ...,
        ge=0,
        le=100,
        description="Risk score (0-100, where 100 is highest risk)",
        examples=[72],
    )
    riskLevel: RiskLevel = Field(
        ...,
        description="Risk level classification",
        examples=[RiskLevel.MEDIUM],
    )
    correlationId: UUID = Field(
        default_factory=uuid4,
        description="Unique correlation ID for request tracking",
    )


class HealthResponse(BaseModel):
    """Health check response."""

    status: str = Field(default="healthy", description="Service health status")
    version: str = Field(default="0.1.0", description="Service version")
    environment: str = Field(..., description="Deployment environment")


class ReadyResponse(BaseModel):
    """Readiness check response."""

    ready: bool = Field(..., description="Service readiness status")
    checks: dict[str, bool] = Field(
        default_factory=dict,
        description="Individual dependency checks",
    )
