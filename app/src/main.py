"""FastAPI application entry point.

This module creates and configures the FastAPI application with:
- API routes for validation
- Health and readiness endpoints
- CORS middleware
- Exception handlers
- OpenAPI documentation
"""

import uuid
from contextlib import asynccontextmanager
from typing import Any

import uvicorn
from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from src.api.v1 import router as v1_router
from src.core import get_settings, setup_logging
from src.core.logging import get_logger, set_correlation_id
from src.models import (
    ErrorCode,
    ErrorResponse,
    HealthResponse,
    ReadyResponse,
)
from src.services import close_riskshield_client

settings = get_settings()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup and shutdown."""
    # Startup
    setup_logging()
    logger.info(
        "application_starting",
        environment=settings.environment,
        version=settings.app_version,
    )

    yield

    # Shutdown
    logger.info("application_shutting_down")
    await close_riskshield_client()
    logger.info("application_shutdown_complete")


def create_app() -> FastAPI:
    """Create and configure the FastAPI application.

    Returns:
        Configured FastAPI application instance.
    """
    app = FastAPI(
        title=settings.app_name,
        description="""
# Applicant Validator

A domain service for loan applicant fraud risk validation using RiskShield.

**Part of FinSure Capital's FinRisk Platform**

## Features

- **Risk Validation**: Submit applicant details and receive a risk score (0-100)
- **Risk Classification**: Automatic categorization (LOW, MEDIUM, HIGH, CRITICAL)
- **Correlation IDs**: Every request gets a unique ID for distributed tracing
- **Rate Limiting**: 100 requests/minute per client to prevent abuse

## Authentication

API uses Bearer token authentication. Contact the Platform team for credentials.

## Rate Limiting

- **Limit**: 100 requests per minute per IP address
- **Headers**: Rate limit info returned in response headers

## Error Handling

All errors follow a consistent JSON format with error codes and correlation IDs.
        """,
        version=settings.app_version,
        docs_url="/docs" if settings.enable_openapi_docs else None,
        redoc_url="/redoc" if settings.enable_openapi_docs else None,
        openapi_url="/openapi.json" if settings.enable_openapi_docs else None,
        lifespan=lifespan,
    )

    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=settings.cors_allow_credentials,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["*"],
    )

    # Include API routers
    app.include_router(v1_router, prefix="/api")

    # Exception handlers
    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        """Handle validation errors with consistent format."""
        correlation_id = uuid.uuid4()
        set_correlation_id(str(correlation_id))

        errors = []
        for error in exc.errors():
            errors.append(
                {
                    "field": ".".join(str(loc) for loc in error.get("loc", [])),
                    "message": error.get("msg", "Validation error"),
                    "code": error.get("type"),
                }
            )

        logger.warning(
            "request_validation_error",
            errors=errors,
            path=request.url.path,
        )

        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=jsonable_encoder(
                ErrorResponse(
                    error=ErrorCode.VALIDATION_ERROR,
                    message="Request validation failed",
                    correlation_id=correlation_id,
                    details=errors,
                )
            ),
        )

    @app.exception_handler(Exception)
    async def generic_exception_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        """Handle unexpected exceptions."""
        correlation_id = uuid.uuid4()

        logger.exception(
            "unhandled_exception",
            error=str(exc),
            error_type=type(exc).__name__,
            path=request.url.path,
        )

        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=jsonable_encoder(
                ErrorResponse(
                    error=ErrorCode.INTERNAL_ERROR,
                    message="An unexpected error occurred",
                    correlation_id=correlation_id,
                )
            ),
        )

    # Health endpoints
    if settings.enable_health_endpoints:

        @app.get(
            "/health",
            response_model=HealthResponse,
            tags=["Health"],
            summary="Health check",
            description="Returns the health status of the API",
        )
        async def health_check() -> HealthResponse:
            """Health check endpoint for load balancers and monitoring."""
            return HealthResponse(
                status="healthy",
                version=settings.app_version,
                environment=settings.environment,
                checks={
                    "api": True,
                },
            )

        @app.get(
            "/ready",
            response_model=ReadyResponse,
            tags=["Health"],
            summary="Readiness check",
            description="Returns whether the API is ready to accept requests",
        )
        async def readiness_check() -> ReadyResponse:
            """Readiness check for Kubernetes deployments."""
            checks = {
                "api": True,
                # Could add checks for:
                # - Key Vault connectivity
                # - RiskShield API health
            }

            all_healthy = all(checks.values())

            return ReadyResponse(
                status="ready" if all_healthy else "not_ready",
                checks=checks,
            )

    # Root endpoint
    @app.get("/", include_in_schema=False)
    async def root() -> dict[str, str]:
        """Root endpoint redirecting to docs."""
        return {
            "name": settings.app_name,
            "version": settings.app_version,
            "docs": "/docs" if settings.enable_openapi_docs else "disabled",
        }

    return app


# Create the application instance
app = create_app()


def main() -> None:
    """Run the application with uvicorn."""
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=settings.port,
        reload=settings.is_development,
        log_level=settings.log_level.lower(),
    )


if __name__ == "__main__":
    main()
