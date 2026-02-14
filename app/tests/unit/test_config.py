"""Unit tests for configuration module."""

import pytest

from src.core.config import Settings


class TestSettings:
    """Tests for Settings configuration."""

    def test_default_values(self):
        """Test default configuration values."""
        settings = Settings()
        assert settings.environment == "dev"
        assert settings.log_level == "INFO"
        assert settings.port == 8080
        assert settings.riskshield_api_timeout == 30
        assert settings.riskshield_max_retries == 3

    def test_environment_properties(self):
        """Test environment check properties."""
        dev_settings = Settings(environment="dev")
        assert dev_settings.is_development is True
        assert dev_settings.is_production is False

        prod_settings = Settings(environment="prod")
        assert prod_settings.is_development is False
        assert prod_settings.is_production is True

    def test_invalid_environment(self):
        """Test rejection of invalid environment."""
        with pytest.raises(Exception):
            Settings(environment="invalid")

    def test_invalid_port(self):
        """Test rejection of invalid port."""
        with pytest.raises(Exception):
            Settings(port=0)

        with pytest.raises(Exception):
            Settings(port=70000)

    def test_invalid_key_vault_url(self):
        """Test rejection of non-HTTPS Key Vault URL."""
        with pytest.raises(Exception):
            Settings(key_vault_url="http://kv-test.vault.azure.net/")

    def test_invalid_riskshield_url(self):
        """Test rejection of invalid RiskShield URL."""
        with pytest.raises(Exception):
            Settings(riskshield_api_url="invalid-url")

    def test_trailing_slash_removed(self):
        """Test trailing slash removal from API URL."""
        settings = Settings(riskshield_api_url="https://api.example.com/v1/")
        assert settings.riskshield_api_url == "https://api.example.com/v1"
