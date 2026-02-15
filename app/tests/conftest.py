"""Pytest configuration and fixtures."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

from src.main import create_app
from src.core.config import Settings


@pytest.fixture
def test_settings() -> Settings:
    """Create test settings."""
    return Settings(
        ENVIRONMENT="dev",
        LOG_LEVEL="DEBUG",
        PORT=8080,
        RISKSHIELD_API_URL="https://api.test.riskshield.com/v1",
        RISKSHIELD_API_KEY="test-api-key",
        CORS_ORIGINS=["*"],
    )


@pytest.fixture
def mock_riskshield_response():
    """Mock RiskShield API response."""
    return {
        "riskScore": 72,
        "riskLevel": "MEDIUM",
        "additionalData": {
            "factors": ["high_debt_ratio", "recent_inquiries"],
        },
    }


@pytest.fixture
def client(test_settings):
    """Create test client with mocked settings."""
    with patch("src.main.get_settings", return_value=test_settings):
        app = create_app()
        with TestClient(app) as test_client:
            yield test_client


@pytest.fixture
def mock_riskshield_client(mock_riskshield_response):
    """Mock RiskShield client."""
    from src.models.validation import RiskLevel

    mock = MagicMock()
    mock.validate_applicant = AsyncMock(
        return_value=(
            mock_riskshield_response["riskScore"],
            RiskLevel[mock_riskshield_response["riskLevel"]],
        )
    )
    return mock
