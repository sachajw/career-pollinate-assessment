"""Application configuration using Pydantic settings."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
    )

    # Application
    ENVIRONMENT: str = Field(default="dev", description="Environment name")
    LOG_LEVEL: str = Field(default="INFO", description="Logging level")
    PORT: int = Field(default=8080, description="Server port")

    # Azure Key Vault
    KEY_VAULT_URL: str | None = Field(
        default=None, description="Azure Key Vault URL for secrets"
    )

    # Application Insights
    APPLICATIONINSIGHTS_CONNECTION_STRING: str | None = Field(
        default=None, description="Application Insights connection string"
    )

    # RiskShield API (loaded from Key Vault at runtime)
    RISKSHIELD_API_URL: str = Field(
        default="https://api.riskshield.com/v1",
        description="RiskShield API base URL",
    )
    RISKSHIELD_API_KEY: str | None = Field(
        default=None,
        description="RiskShield API key (loaded from Key Vault)",
    )

    # CORS
    CORS_ORIGINS: list[str] = Field(
        default=["*"],
        description="Allowed CORS origins",
    )

    # Health checks
    HEALTH_CHECK_TIMEOUT: int = Field(
        default=5,
        description="Health check timeout in seconds",
    )


@lru_cache
def get_settings() -> Settings:
    """Get cached application settings."""
    return Settings()
