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
        environment="dev",
        log_level="DEBUG",
        port=8080,
        riskshield_api_url="https://api.test.riskshield.com/v1",
        riskshield_api_key="test-api-key",
        cors_origins=["*"],
        rate_limit_enabled=False,  # Disable rate limiting for tests
        enable_openapi_docs=True,
        enable_health_endpoints=True,
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
    from src.services import RiskShieldResult

    mock = MagicMock()
    mock.validate = AsyncMock(
        return_value=RiskShieldResult(
            risk_score=mock_riskshield_response["riskScore"],
            risk_level=mock_riskshield_response["riskLevel"],
            additional_data=mock_riskshield_response.get("additionalData"),
        )
    )
    return mock
