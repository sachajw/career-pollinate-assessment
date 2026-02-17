"""Integration tests for API endpoints."""

import pytest
from unittest.mock import AsyncMock, MagicMock
from fastapi.testclient import TestClient

from src.main import create_app
from src.core.config import Settings
from src.models.validation import RiskLevel
from src.services.riskshield import RiskShieldClient


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
def mock_riskshield_client():
    """Create a mock RiskShield client."""
    mock_client = MagicMock(spec=RiskShieldClient)
    mock_client.validate_applicant = AsyncMock(return_value=(72, RiskLevel.HIGH))
    mock_client.health_check = AsyncMock(return_value=True)
    return mock_client


@pytest.fixture
def client(test_settings, mock_riskshield_client):
    """Create test client with dependency overrides."""
    from src.api.v1.routes import get_riskshield_client
    from src.core.config import get_settings

    app = create_app()

    # Override dependencies
    app.dependency_overrides[get_settings] = lambda: test_settings
    app.dependency_overrides[get_riskshield_client] = lambda: mock_riskshield_client

    with TestClient(app) as test_client:
        yield test_client, mock_riskshield_client

    # Clean up overrides
    app.dependency_overrides.clear()


class TestHealthEndpoints:
    """Tests for health check endpoints."""

    def test_health_check(self, client):
        """Test health check endpoint returns healthy status."""
        test_client, _ = client
        response = test_client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data
        assert "environment" in data

    def test_readiness_check(self, client):
        """Test readiness check endpoint returns ready status."""
        test_client, _ = client
        response = test_client.get("/ready")
        assert response.status_code == 200
        data = response.json()
        assert "ready" in data
        assert "checks" in data


class TestRootEndpoint:
    """Tests for root endpoint."""

    def test_root_returns_api_info(self, client):
        """Test root endpoint returns API info."""
        test_client, _ = client
        response = test_client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert "service" in data
        assert "version" in data
        assert "docs" in data


class TestValidationEndpoint:
    """Tests for the /api/v1/validate endpoint."""

    def test_validate_success(self, client):
        """Test successful validation request."""
        test_client, mock_client = client

        # Configure mock for this test
        mock_client.validate_applicant = AsyncMock(
            return_value=(72, RiskLevel.HIGH)
        )

        # Make request
        response = test_client.post(
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

    def test_validate_low_risk(self, client):
        """Test validation with low risk score."""
        test_client, mock_client = client

        # Configure mock for this test
        mock_client.validate_applicant = AsyncMock(
            return_value=(15, RiskLevel.LOW)
        )

        response = test_client.post(
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

    def test_validate_medium_risk(self, client):
        """Test validation with medium risk score."""
        test_client, mock_client = client

        mock_client.validate_applicant = AsyncMock(
            return_value=(50, RiskLevel.MEDIUM)
        )

        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "John",
                "lastName": "Smith",
                "idNumber": "9001011234088",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["riskScore"] == 50
        assert data["riskLevel"] == "MEDIUM"

    def test_validate_critical_risk(self, client):
        """Test validation with critical risk score."""
        test_client, mock_client = client

        mock_client.validate_applicant = AsyncMock(
            return_value=(95, RiskLevel.CRITICAL)
        )

        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "Suspicious",
                "lastName": "Person",
                "idNumber": "7001015009087",
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["riskScore"] == 95
        assert data["riskLevel"] == "CRITICAL"


class TestValidationInput:
    """Tests for input validation."""

    def test_missing_first_name(self, client):
        """Test rejection of missing first name."""
        test_client, _ = client
        response = test_client.post(
            "/api/v1/validate",
            json={
                "lastName": "Doe",
                "idNumber": "8001015009087",
            },
        )
        assert response.status_code == 422

    def test_missing_last_name(self, client):
        """Test rejection of missing last name."""
        test_client, _ = client
        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "idNumber": "8001015009087",
            },
        )
        assert response.status_code == 422

    def test_invalid_id_number_format(self, client):
        """Test rejection of invalid ID number format."""
        test_client, _ = client
        response = test_client.post(
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
        test_client, _ = client
        response = test_client.post(
            "/api/v1/validate",
            json={},
        )
        assert response.status_code == 422

    def test_id_number_too_short(self, client):
        """Test rejection of ID number that's too short."""
        test_client, _ = client
        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "123456789012",  # 12 digits instead of 13
            },
        )
        assert response.status_code == 422

    def test_id_number_too_long(self, client):
        """Test rejection of ID number that's too long."""
        test_client, _ = client
        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "12345678901234",  # 14 digits instead of 13
            },
        )
        assert response.status_code == 422


class TestOpenAPI:
    """Tests for OpenAPI documentation."""

    def test_docs_accessible(self, client):
        """Test that OpenAPI docs are accessible."""
        test_client, _ = client
        response = test_client.get("/docs")
        assert response.status_code == 200

    def test_openapi_json_accessible(self, client):
        """Test that OpenAPI JSON is accessible."""
        test_client, _ = client
        response = test_client.get("/openapi.json")
        assert response.status_code == 200
        data = response.json()
        assert "openapi" in data
        assert "paths" in data


class TestCorrelationID:
    """Tests for correlation ID middleware."""

    def test_correlation_id_in_response(self, client):
        """Test that correlation ID is returned in response header."""
        test_client, mock_client = client

        mock_client.validate_applicant = AsyncMock(
            return_value=(50, RiskLevel.MEDIUM)
        )

        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "8001015009087",
            },
        )

        assert "X-Correlation-ID" in response.headers
        assert response.headers["X-Correlation-ID"]  # Not empty

    def test_correlation_id_propagated_from_request(self, client):
        """Test that provided correlation ID is used."""
        test_client, mock_client = client

        mock_client.validate_applicant = AsyncMock(
            return_value=(50, RiskLevel.MEDIUM)
        )

        custom_correlation_id = "test-correlation-123"

        response = test_client.post(
            "/api/v1/validate",
            json={
                "firstName": "Jane",
                "lastName": "Doe",
                "idNumber": "8001015009087",
            },
            headers={"X-Correlation-ID": custom_correlation_id},
        )

        assert response.headers["X-Correlation-ID"] == custom_correlation_id

    def test_health_endpoint_has_correlation_id(self, client):
        """Test that health endpoint returns correlation ID."""
        test_client, _ = client
        response = test_client.get("/health")

        assert "X-Correlation-ID" in response.headers
