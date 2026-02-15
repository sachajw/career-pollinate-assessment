"""FastAPI application entry point."""

import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.v1 import router as v1_router
from .core.config import get_settings
from .core.logging import configure_logging

# Configure structured logging
settings = get_settings()
configure_logging(settings.LOG_LEVEL)

logger = structlog.get_logger()

# Create FastAPI application
app = FastAPI(
    title="Applicant Validator API",
    description="FinRisk Platform - Loan Applicant Fraud Risk Validation Service",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(v1_router, prefix="/api/v1", tags=["Validation"])

# Root health endpoints (no /api/v1 prefix for Container Apps health probes)
app.include_router(v1_router, tags=["Health"])


@app.on_event("startup")
async def startup_event() -> None:
    """Application startup event."""
    logger.info(
        "Starting Applicant Validator API",
        version="0.1.0",
        environment=settings.ENVIRONMENT,
        port=settings.PORT,
    )


@app.on_event("shutdown")
async def shutdown_event() -> None:
    """Application shutdown event."""
    logger.info("Shutting down Applicant Validator API")


@app.get("/", include_in_schema=False)
async def root() -> dict[str, str]:
    """Root endpoint."""
    return {
        "service": "Applicant Validator API",
        "version": "0.1.0",
        "docs": "/docs",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=settings.PORT,
        reload=True,
    )
