"""Unit tests for Pydantic models."""

import pytest
from pydantic import ValidationError

from src.models import (
    ApplicantValidationRequest,
    ApplicantValidationResponse,
    HealthResponse,
    ReadyResponse,
    RiskLevel,
)


class TestRiskLevel:
    """Tests for RiskLevel enum."""

    def test_risk_level_values(self):
        """Test RiskLevel enum values."""
        assert RiskLevel.LOW.value == "LOW"
        assert RiskLevel.MEDIUM.value == "MEDIUM"
        assert RiskLevel.HIGH.value == "HIGH"
        assert RiskLevel.CRITICAL.value == "CRITICAL"

    def test_risk_level_is_str(self):
        """Test RiskLevel is a string enum."""
        assert RiskLevel.LOW == "LOW"
        assert RiskLevel.MEDIUM == "MEDIUM"


class TestApplicantValidationRequest:
    """Tests for ApplicantValidationRequest model."""

    def test_valid_request(self):
        """Test valid request creation."""
        request = ApplicantValidationRequest(
            firstName="Jane",
            lastName="Doe",
            idNumber="9001011234088",
        )
        assert request.firstName == "Jane"
        assert request.lastName == "Doe"
        assert request.idNumber == "9001011234088"

    def test_invalid_id_number_too_short(self):
        """Test rejection of ID number that's too short."""
        with pytest.raises(ValidationError):
            ApplicantValidationRequest(
                firstName="Jane",
                lastName="Doe",
                idNumber="12345",
            )

    def test_invalid_id_number_too_long(self):
        """Test rejection of ID number that's too long."""
        with pytest.raises(ValidationError):
            ApplicantValidationRequest(
                firstName="Jane",
                lastName="Doe",
                idNumber="12345678901234",
            )

    def test_invalid_id_number_non_digits(self):
        """Test rejection of non-digit characters in ID."""
        with pytest.raises(ValidationError):
            ApplicantValidationRequest(
                firstName="Jane",
                lastName="Doe",
                idNumber="900101123408A",
            )

    def test_empty_first_name(self):
        """Test rejection of empty first name."""
        with pytest.raises(ValidationError):
            ApplicantValidationRequest(
                firstName="",
                lastName="Doe",
                idNumber="9001011234088",
            )

    def test_empty_last_name(self):
        """Test rejection of empty last name."""
        with pytest.raises(ValidationError):
            ApplicantValidationRequest(
                firstName="Jane",
                lastName="",
                idNumber="9001011234088",
            )


class TestApplicantValidationResponse:
    """Tests for ApplicantValidationResponse model."""

    def test_valid_response(self):
        """Test valid response creation."""
        response = ApplicantValidationResponse(
            riskScore=72,
            riskLevel=RiskLevel.HIGH,
        )
        assert response.riskScore == 72
        assert response.riskLevel == RiskLevel.HIGH

    def test_score_out_of_range_high(self):
        """Test rejection of score above 100."""
        with pytest.raises(ValidationError):
            ApplicantValidationResponse(
                riskScore=150,
                riskLevel=RiskLevel.HIGH,
            )

    def test_score_out_of_range_low(self):
        """Test rejection of score below 0."""
        with pytest.raises(ValidationError):
            ApplicantValidationResponse(
                riskScore=-10,
                riskLevel=RiskLevel.LOW,
            )

    def test_correlation_id_auto_generated(self):
        """Test correlation ID is auto-generated."""
        response = ApplicantValidationResponse(
            riskScore=50,
            riskLevel=RiskLevel.MEDIUM,
        )
        assert response.correlationId is not None


class TestHealthResponse:
    """Tests for HealthResponse model."""

    def test_default_status(self):
        """Test default health status."""
        response = HealthResponse(environment="dev")
        assert response.status == "healthy"
        assert response.version == "0.1.0"
        assert response.environment == "dev"


class TestReadyResponse:
    """Tests for ReadyResponse model."""

    def test_ready_response(self):
        """Test ready response creation."""
        response = ReadyResponse(ready=True)
        assert response.ready is True

    def test_ready_response_with_checks(self):
        """Test ready response with dependency checks."""
        response = ReadyResponse(
            ready=True,
            checks={"database": True, "api": True},
        )
        assert response.checks["database"] is True
        assert response.checks["api"] is True
