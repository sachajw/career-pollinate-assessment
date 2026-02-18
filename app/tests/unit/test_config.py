"""Unit tests for configuration module."""

from src.core.config import Settings


class TestSettings:
    """Tests for Settings configuration."""

    def test_default_values(self):
        """Test default configuration values."""
        settings = Settings()
        assert settings.ENVIRONMENT == "dev"
        assert settings.LOG_LEVEL == "INFO"
        assert settings.PORT == 8080

    def test_custom_values(self):
        """Test custom configuration values."""
        settings = Settings(
            ENVIRONMENT="prod",
            LOG_LEVEL="DEBUG",
            PORT=9000,
        )
        assert settings.ENVIRONMENT == "prod"
        assert settings.LOG_LEVEL == "DEBUG"
        assert settings.PORT == 9000

    def test_riskshield_defaults(self):
        """Test RiskShield default values."""
        settings = Settings()
        assert settings.RISKSHIELD_API_URL == "https://api.riskshield.com/v1"
        assert settings.RISKSHIELD_API_KEY is None

    def test_cors_origins_default(self):
        """Test CORS origins default value."""
        settings = Settings()
        assert settings.CORS_ORIGINS == ["*"]

    def test_health_check_timeout_default(self):
        """Test health check timeout default value."""
        settings = Settings()
        assert settings.HEALTH_CHECK_TIMEOUT == 5

    def test_key_vault_url_optional(self):
        """Test Key Vault URL is optional."""
        settings = Settings()
        assert settings.KEY_VAULT_URL is None

    def test_application_insights_optional(self):
        """Test Application Insights connection string is optional."""
        settings = Settings()
        assert settings.APPLICATIONINSIGHTS_CONNECTION_STRING is None
