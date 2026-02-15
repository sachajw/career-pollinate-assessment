"""Application configuration using Pydantic Settings.

This module provides centralized configuration management with:
- Environment variable loading
- Azure Key Vault integration for secrets
- Type-safe configuration access
"""

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables.

    Attributes:
        environment: Deployment environment (dev, staging, prod)
        log_level: Logging level
        port: Application port
        key_vault_url: Azure Key Vault URL for secrets
        app_insights_connection_string: Application Insights connection
        riskshield_api_url: RiskShield API endpoint
        riskshield_api_timeout: API request timeout in seconds
        riskshield_max_retries: Maximum retry attempts
        cors_origins: Allowed CORS origins
        rate_limit_requests: Max requests per minute per client
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Application
    environment: Literal["dev", "staging", "prod"] = Field(
        default="dev",
        description="Deployment environment",
    )
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = Field(
        default="INFO",
        description="Logging level",
    )
    port: int = Field(
        default=8080,
        ge=1,
        le=65535,
        description="Application port",
    )
    app_name: str = Field(
        default="Risk Scoring API",
        description="Application name for logging and docs",
    )
    app_version: str = Field(
        default="1.0.0",
        description="Application version",
    )

    # Azure Services
    key_vault_url: str | None = Field(
        default=None,
        description="Azure Key Vault URL (e.g., https://kv-name.vault.azure.net/)",
    )
    app_insights_connection_string: str | None = Field(
        default=None,
        description="Application Insights connection string",
    )

    # RiskShield API Configuration
    riskshield_api_url: str = Field(
        default="https://api.riskshield.example.com/v1",
        description="RiskShield API base URL",
    )
    riskshield_api_key: str | None = Field(
        default=None,
        description="RiskShield API key (loaded from Key Vault in production)",
    )
    riskshield_api_timeout: int = Field(
        default=30,
        ge=5,
        le=120,
        description="API request timeout in seconds",
    )
    riskshield_max_retries: int = Field(
        default=3,
        ge=0,
        le=5,
        description="Maximum retry attempts for failed requests",
    )
    riskshield_retry_delay: float = Field(
        default=1.0,
        ge=0.1,
        le=10.0,
        description="Initial retry delay in seconds (exponential backoff)",
    )

    # CORS Configuration
    cors_origins: list[str] = Field(
        default=[],
        description="Allowed CORS origins (required in production)",
    )
    cors_allow_credentials: bool = Field(
        default=False,
        description="Allow credentials in CORS requests",
    )

    # Rate Limiting
    rate_limit_enabled: bool = Field(
        default=True,
        description="Enable rate limiting",
    )
    rate_limit_requests: int = Field(
        default=100,
        ge=1,
        le=10000,
        description="Max requests per minute per client",
    )

    # Feature Flags
    enable_openapi_docs: bool = Field(
        default=True,
        description="Enable OpenAPI documentation endpoints",
    )
    enable_health_endpoints: bool = Field(
        default=True,
        description="Enable health and readiness endpoints",
    )

    @field_validator("key_vault_url")
    @classmethod
    def validate_key_vault_url(cls, v: str | None) -> str | None:
        """Validate Key Vault URL format."""
        if v is not None and not v.startswith("https://"):
            raise ValueError("Key Vault URL must start with https://")
        return v

    @field_validator("riskshield_api_url")
    @classmethod
    def validate_riskshield_url(cls, v: str) -> str:
        """Validate RiskShield API URL format."""
        if not v.startswith(("http://", "https://")):
            raise ValueError("RiskShield API URL must start with http:// or https://")
        return v.rstrip("/")

    @property
    def is_production(self) -> bool:
        """Check if running in production environment."""
        return self.environment == "prod"

    @property
    def is_development(self) -> bool:
        """Check if running in development environment."""
        return self.environment == "dev"


@lru_cache()
def get_settings() -> Settings:
    """Get cached application settings.

    Uses lru_cache to ensure settings are only loaded once.

    Returns:
        Settings: Application settings instance.
    """
    return Settings()


def reset_settings() -> None:
    """Clear settings cache (for testing).

    This function is useful in tests when you need to reload
    settings with different environment variables.
    """
    get_settings.cache_clear()
