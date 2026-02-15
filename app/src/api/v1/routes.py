"""API v1 routes for the Risk Scoring API."""

import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address

from src.core.config import get_settings
from src.core.logging import get_logger, set_correlation_id
from src.models import (
    ErrorCode,
    ErrorDetail,
    ErrorResponse,
    ValidationRequest,
    ValidationResponse,
    RiskLevel,
)
from src.services import (
    RiskShieldAuthError,
    RiskShieldError,
    RiskShieldRateLimitError,
    RiskShieldServerError,
    RiskShieldTimeoutError,
    get_riskshield_client,
)

logger = get_logger(__name__)
router = APIRouter(prefix="/v1")
settings = get_settings()

# Rate limiter
limiter = Limiter(key_func=get_remote_address)


@router.post(
    "/validate",
    response_model=ValidationResponse,
    responses={
        400: {"model": ErrorResponse, "description": "Validation error"},
        401: {"model": ErrorResponse, "description": "Authentication error"},
        429: {"model": ErrorResponse, "description": "Rate limit exceeded"},
        500: {"model": ErrorResponse, "description": "Internal server error"},
        502: {"model": ErrorResponse, "description": "Upstream error"},
        503: {"model": ErrorResponse, "description": "Service unavailable"},
    },
    summary="Validate loan applicant",
    description="Validates a loan applicant and returns their fraud risk score.",
)
@limiter.limit(f"{settings.rate_limit_requests}/minute")
async def validate_applicant(
    request: Request,
    validation_request: ValidationRequest,
) -> ValidationResponse:
    """Validate a loan applicant for fraud risk.

    This endpoint accepts applicant details and returns a risk score
    along with a categorical risk level (LOW, MEDIUM, HIGH, CRITICAL).

    The risk score ranges from 0 (lowest risk) to 100 (highest risk).

    **Rate Limiting:** 100 requests per minute per IP address.

    **Correlation ID:** Each request is assigned a unique correlation ID
    for tracing across distributed systems.
    """
    # Generate correlation ID for this request
    correlation_id = uuid.uuid4()
    set_correlation_id(str(correlation_id))  # Convert to str for logging context

    logger.info(
        "validation_request_received",
        first_name=validation_request.first_name,
        id_number_prefix=validation_request.id_number[:4] + "***",
    )

    try:
        client = get_riskshield_client()
        result = await client.validate(
            first_name=validation_request.first_name,
            last_name=validation_request.last_name,
            id_number=validation_request.id_number,
        )

        response = ValidationResponse(
            risk_score=result.risk_score,
            risk_level=RiskLevel.from_score(result.risk_score),  # Always derive from score
            correlation_id=correlation_id,
            additional_data=result.additional_data,
        )

        logger.info(
            "validation_request_completed",
            risk_score=response.risk_score,
            risk_level=response.risk_level.value,
        )

        return response

    except RiskShieldAuthError as e:
        logger.error("validation_auth_error", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=ErrorResponse(
                error=ErrorCode.AUTHENTICATION_ERROR,
                message="Failed to authenticate with risk validation service",
                correlation_id=correlation_id,
            ).model_dump(mode='json'),
        )

    except RiskShieldRateLimitError as e:
        logger.warning("validation_rate_limited", retry_after=e.retry_after)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=ErrorResponse(
                error=ErrorCode.RATE_LIMIT_ERROR,
                message="Rate limit exceeded. Please try again later.",
                correlation_id=correlation_id,
            ).model_dump(mode='json'),
        )

    except RiskShieldTimeoutError as e:
        logger.error("validation_timeout", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=ErrorResponse(
                error=ErrorCode.TIMEOUT_ERROR,
                message="Risk validation service timed out",
                correlation_id=correlation_id,
            ).model_dump(mode='json'),
        )

    except RiskShieldServerError as e:
        logger.error("validation_server_error", error=str(e), status_code=e.status_code)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=ErrorResponse(
                error=ErrorCode.UPSTREAM_ERROR,
                message="Risk validation service is temporarily unavailable",
                correlation_id=correlation_id,
            ).model_dump(mode='json'),
        )

    except RiskShieldError as e:
        logger.error("validation_api_error", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=ErrorResponse(
                error=ErrorCode.UPSTREAM_ERROR,
                message=str(e),
                correlation_id=correlation_id,
            ).model_dump(mode='json'),
        )

    except Exception as e:
        logger.exception("validation_unexpected_error", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=ErrorResponse(
                error=ErrorCode.INTERNAL_ERROR,
                message="An unexpected error occurred",
                correlation_id=correlation_id,
            ).model_dump(mode='json'),
        )
