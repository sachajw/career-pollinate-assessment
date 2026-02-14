"""Integration tests for API endpoints."""

import pytest
from unittest.mock import patch, AsyncMock
from fastapi.testclient import TestClient

from src.main import create_app
from src.core.config import Settings
from src.services import (
    RiskShieldResult,
    RiskShieldAuthError,
    RiskShieldRateLimitError,
    RiskShieldTimeoutError,
    RiskShieldServerError,
)


@pytest.fixture
def test_settings():
    """Create test settings with rate limiting disabled."""
    return Settings(
        environment="dev",
        log_level="DEBUG",
        port=8080,
        riskshield_api_url="https://api.test.riskshield.com/v1",
        riskshield_api_key="test-api-key",
        cors_origins=["*"],
        rate_limit_enabled=False,
        enable_openapi_docs=True,
        enable_health_endpoints=True,
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
        assert data["status"] == "ready"
        assert "checks" in data


class TestRootEndpoint:
    """Tests for root endpoint."""

    def test_root_redirect(self, client):
        """Test root endpoint returns API info."""
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert "name" in data
        assert "version" in data


class TestValidationEndpoint:
    """Tests for the /api/v1/validate endpoint."""

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_success(self, mock_get_client, client):
        """Test successful validation request."""
        # Setup mock
        mock_client = mock_get_client.return_value
        mock_client.validate = AsyncMock(
            return_value=RiskShieldResult(
                risk_score=72,
                risk_level="MEDIUM",
                additional_data={"factors": ["test_factor"]},
            )
        )

        # Make request
        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "9001011234088",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["riskScore"] == 72
        assert data["riskLevel"] == "MEDIUM"
        assert "correlationId" in data

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_auth_error(self, mock_get_client, client):
        """Test validation with authentication error."""
        mock_client = mock_get_client.return_value
        mock_client.validate = AsyncMock(
            side_effect=RiskShieldAuthError("Auth failed")
        )

        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "9001011234088",
            },
        )

        assert response.status_code == 401

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_rate_limit_error(self, mock_get_client, client):
        """Test validation with rate limit error."""
        mock_client = mock_get_client.return_value
        mock_client.validate = AsyncMock(
            side_effect=RiskShieldRateLimitError(retry_after=60)
        )

        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "9001011234088",
            },
        )

        assert response.status_code == 429

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_timeout_error(self, mock_get_client, client):
        """Test validation with timeout error."""
        mock_client = mock_get_client.return_value
        mock_client.validate = AsyncMock(
            side_effect=RiskShieldTimeoutError()
        )

        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "9001011234088",
            },
        )

        assert response.status_code == 504

    @patch("src.api.v1.routes.get_riskshield_client")
    def test_validate_server_error(self, mock_get_client, client):
        """Test validation with upstream server error."""
        mock_client = mock_get_client.return_value
        mock_client.validate = AsyncMock(
            side_effect=RiskShieldServerError(status_code=503)
        )

        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "9001011234088",
            },
        )

        assert response.status_code == 503


class TestValidationInput:
    """Tests for input validation."""

    def test_missing_first_name(self, client):
        """Test rejection of missing first name."""
        response = client.post(
            "/api/v1/validate",
            json={
                "lastName": "Doe",
                "idNumber": "9001011234088",
            },
        )
        assert response.status_code == 400

    def test_missing_last_name(self, client):
        """Test rejection of missing last name."""
        response = client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "idNumber": "9001011234088",
            },
        )
        assert response.status_code == 400

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
        assert response.status_code == 400

    def test_empty_request_body(self, client):
        """Test rejection of empty request body."""
        response = client.post(
            "/api/v1/validate",
            json={},
        )
        assert response.status_code == 400


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
