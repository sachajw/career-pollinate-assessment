"""Integration tests for API endpoints."""

import pytest
from unittest.mock import patch, AsyncMock, MagicMock
from fastapi.testclient import TestClient

from src.main import create_app
from src.core.config import Settings
from src.models.validation import RiskLevel


@pytest.fixture
def test_settings():
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
def client(test_settings):
    """Create test client."""
    with patch("src.main.get_settings", return_value=test_settings):
        app = create_app()
        with TestClient(app) as test_client:
            yield test_client


class TestHealthEndpoints:
    """Tests for health check endpoints."""

    def test_health_check(self, client):
        """Test health check endpoint returns healthy status."""
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data
        assert "environment" in data

    def test_readiness_check(self, client):
        """Test readiness check endpoint returns ready status."""
        response = client.get("/ready")
        assert response.status_code == 200
        data = response.json()
        assert "ready" in data
        assert "checks" in data


class TestRootEndpoint:
    """Tests for root endpoint."""

    def test_root_returns_api_info(self, client):
        """Test root endpoint returns API info."""
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert "service" in data
        assert "version" in data
        assert "docs" in data


class TestValidationEndpoint:
    """Tests for the /api/v1/validate endpoint."""

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_success(self, mock_get_client, client):
        """Test successful validation request."""
        # Setup mock
        mock_client = MagicMock()
        mock_client.validate_applicant = AsyncMock(
            return_value=(72, RiskLevel.HIGH)
        )
        mock_get_client.return_value = mock_client

        # Make request
        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "8001015009087",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["riskScore"] == 72
        assert data["riskLevel"] == "HIGH"
        assert "correlationId" in data

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_low_risk(self, mock_get_client, client):
        """Test validation with low risk score."""
        mock_client = MagicMock()
        mock_client.validate_applicant = AsyncMock(
            return_value=(15, RiskLevel.LOW)
        )
        mock_get_client.return_value = mock_client

        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "8001015009087",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["riskScore"] == 15
        assert data["riskLevel"] == "LOW"


class TestValidationInput:
    """Tests for input validation."""

    def test_missing_first_name(self, client):
        """Test rejection of missing first name."""
        response = client.post(
            "/api/v1/validate",
            json={
                "lastName": "Doe",
                "idNumber": "8001015009087",
            },
        )
        assert response.status_code == 422

    def test_missing_last_name(self, client):
        """Test rejection of missing last name."""
        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "idNumber": "8001015009087",
            },
        )
        assert response.status_code == 422

    def test_invalid_id_number_format(self, client):
        """Test rejection of invalid ID number format."""
        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "invalid",
            },
        )
        assert response.status_code == 422

    def test_empty_request_body(self, client):
        """Test rejection of empty request body."""
        response = client.post(
            "/api/v1/validate",
            json={},
        )
        assert response.status_code == 422


class TestOpenAPI:
    """Tests for OpenAPI documentation."""

    def test_docs_accessible(self, client):
        """Test that OpenAPI docs are accessible."""
        response = client.get("/docs")
        assert response.status_code == 200

    def test_openapi_json_accessible(self, client):
        """Test that OpenAPI JSON is accessible."""
        response = client.get("/openapi.json")
        assert response.status_code == 200
        data = response.json()
        assert "openapi" in data
        assert "paths" in data
