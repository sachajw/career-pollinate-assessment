"""API v1 routes for applicant validation."""

from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, status

from ...core.config import Settings, get_settings
from ...models.validation import (
    ApplicantValidationRequest,
    ApplicantValidationResponse,
    HealthResponse,
    ReadyResponse,
)
from ...services.riskshield import RiskShieldClient

logger = structlog.get_logger()

router = APIRouter()


def get_riskshield_client(
    settings: Annotated[Settings, Depends(get_settings)],
) -> RiskShieldClient:
    """Get RiskShield client dependency.

    Args:
        settings: Application settings

    Returns:
        Configured RiskShield client
    """
    return RiskShieldClient(
        api_url=settings.RISKSHIELD_API_URL,
        api_key=settings.RISKSHIELD_API_KEY,
    )


@router.post(
    "/validate",
    response_model=ApplicantValidationResponse,
    status_code=status.HTTP_200_OK,
    summary="Validate loan applicant",
    description="Validates a loan applicant against RiskShield API for fraud risk assessment",
    responses={
        200: {
            "description": "Applicant validated successfully",
            "content": {
                "application/json": {
                    "example": {
                        "riskScore": 72,
                        "riskLevel": "MEDIUM",
                        "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                    }
                }
            },
        },
        422: {"description": "Validation error (invalid input)"},
        500: {"description": "Internal server error"},
        503: {"description": "RiskShield API unavailable"},
    },
)
async def validate_applicant(
    request: ApplicantValidationRequest,
    riskshield: Annotated[RiskShieldClient, Depends(get_riskshield_client)],
) -> ApplicantValidationResponse:
    """Validate loan applicant for fraud risk.

    Args:
        request: Applicant validation request
        riskshield: RiskShield API client

    Returns:
        Validation response with risk score and level

    Raises:
        HTTPException: If validation fails
    """
    try:
        logger.info(
            "Processing validation request",
            first_name=request.firstName,
            last_name=request.lastName,
        )

        # Validate applicant via RiskShield API
        risk_score, risk_level = await riskshield.validate_applicant(request)

        response = ApplicantValidationResponse(
            riskScore=risk_score,
            riskLevel=risk_level,
        )

        logger.info(
            "Validation successful",
            risk_score=risk_score,
            risk_level=risk_level.value,
            correlation_id=str(response.correlationId),
        )

        return response

    except Exception as e:
        logger.error(
            "Validation failed",
            error=str(e),
            error_type=type(e).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Applicant validation failed",
        ) from e


@router.get(
    "/health",
    response_model=HealthResponse,
    status_code=status.HTTP_200_OK,
    summary="Health check",
    description="Check if the service is running",
    tags=["Health"],
)
async def health_check(
    settings: Annotated[Settings, Depends(get_settings)],
) -> HealthResponse:
    """Health check endpoint.

    Args:
        settings: Application settings

    Returns:
        Health status
    """
    return HealthResponse(
        status="healthy",
        version="0.1.0",
        environment=settings.ENVIRONMENT,
    )


@router.get(
    "/ready",
    response_model=ReadyResponse,
    status_code=status.HTTP_200_OK,
    summary="Readiness check",
    description="Check if the service is ready to handle requests",
    tags=["Health"],
)
async def readiness_check(
    settings: Annotated[Settings, Depends(get_settings)],
    riskshield: Annotated[RiskShieldClient, Depends(get_riskshield_client)],
) -> ReadyResponse:
    """Readiness check endpoint.

    Checks:
    - RiskShield API connectivity

    Args:
        settings: Application settings
        riskshield: RiskShield API client

    Returns:
        Readiness status
    """
    # Check RiskShield API health
    riskshield_healthy = await riskshield.health_check()

    checks = {
        "riskshield_api": riskshield_healthy,
    }

    # Service is ready if all checks pass
    ready = all(checks.values())

    if not ready:
        logger.warning("Readiness check failed", checks=checks)

    return ReadyResponse(ready=ready, checks=checks)
