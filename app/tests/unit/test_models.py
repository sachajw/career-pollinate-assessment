"""Unit tests for Pydantic models."""

import pytest
from pydantic import ValidationError

from src.models import (
    RiskLevel,
    ValidationRequest,
    ValidationResponse,
    ErrorCode,
    ErrorDetail,
    ErrorResponse,
)


class TestRiskLevel:
    """Tests for RiskLevel enum."""

    def test_from_score_low(self):
        """Test LOW risk level for scores 0-29."""
        assert RiskLevel.from_score(0) == RiskLevel.LOW
        assert RiskLevel.from_score(15) == RiskLevel.LOW
        assert RiskLevel.from_score(29) == RiskLevel.LOW

    def test_from_score_medium(self):
        """Test MEDIUM risk level for scores 30-59."""
        assert RiskLevel.from_score(30) == RiskLevel.MEDIUM
        assert RiskLevel.from_score(45) == RiskLevel.MEDIUM
        assert RiskLevel.from_score(59) == RiskLevel.MEDIUM

    def test_from_score_high(self):
        """Test HIGH risk level for scores 60-79."""
        assert RiskLevel.from_score(60) == RiskLevel.HIGH
        assert RiskLevel.from_score(70) == RiskLevel.HIGH
        assert RiskLevel.from_score(79) == RiskLevel.HIGH

    def test_from_score_critical(self):
        """Test CRITICAL risk level for scores 80-100."""
        assert RiskLevel.from_score(80) == RiskLevel.CRITICAL
        assert RiskLevel.from_score(90) == RiskLevel.CRITICAL
        assert RiskLevel.from_score(100) == RiskLevel.CRITICAL


class TestValidationRequest:
    """Tests for ValidationRequest model."""

    def test_valid_request(self):
        """Test valid request creation."""
        request = ValidationRequest(
            first_name="John",
            last_name="Doe",
            id_number="8001015009087",
        )
        assert request.first_name == "John"
        assert request.last_name == "Doe"
        assert request.id_number == "8001015009087"

    def test_name_normalization(self):
        """Test name whitespace normalization."""
        request = ValidationRequest(
            first_name="  John  Paul  ",
            last_name="  Doe  ",
            id_number="8001015009087",
        )
        assert request.first_name == "John Paul"
        assert request.last_name == "Doe"

    def test_invalid_name_characters(self):
        """Test rejection of invalid name characters."""
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="John123",
                last_name="Doe",
                id_number="8001015009087",
            )

    def test_empty_name(self):
        """Test rejection of empty name."""
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="",
                last_name="Doe",
                id_number="8001015009087",
            )

    def test_invalid_id_number_length(self):
        """Test rejection of wrong ID number length."""
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="John",
                last_name="Doe",
                id_number="12345",
            )

    def test_invalid_id_number_non_digits(self):
        """Test rejection of non-digit characters in ID."""
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="John",
                last_name="Doe",
                id_number="900101123408A",
            )

    def test_invalid_id_number_month(self):
        """Test rejection of invalid month in ID number."""
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="John",
                last_name="Doe",
                id_number="9013012340881",  # Month 13
            )

    def test_invalid_id_number_day(self):
        """Test rejection of invalid day in ID number."""
        with pytest.raises(ValidationError):
            ValidationRequest(
                first_name="John",
                last_name="Doe",
                id_number="9001321234088",  # Day 32
            )


class TestValidationResponse:
    """Tests for ValidationResponse model."""

    def test_valid_response(self):
        """Test valid response creation."""
        response = ValidationResponse(
            risk_score=72,
            risk_level=RiskLevel.HIGH,  # Score 72 is in HIGH range (60-79)
        )
        assert response.risk_score == 72
        assert response.risk_level == RiskLevel.HIGH

    def test_risk_level_auto_correction(self):
        """Test automatic risk level correction based on score."""
        response = ValidationResponse(
            risk_score=85,
            risk_level=RiskLevel.LOW,  # Wrong level for score
        )
        # Should be auto-corrected to CRITICAL
        assert response.risk_level == RiskLevel.CRITICAL

    def test_score_out_of_range(self):
        """Test rejection of score out of range."""
        with pytest.raises(ValidationError):
            ValidationResponse(
                risk_score=150,
                risk_level=RiskLevel.HIGH,
            )

        with pytest.raises(ValidationError):
            ValidationResponse(
                risk_score=-10,
                risk_level=RiskLevel.LOW,
            )


class TestErrorResponse:
    """Tests for ErrorResponse model."""

    def test_valid_error_response(self):
        """Test valid error response creation."""
        response = ErrorResponse(
            error=ErrorCode.VALIDATION_ERROR,
            message="Invalid input",
        )
        assert response.error == ErrorCode.VALIDATION_ERROR
        assert response.message == "Invalid input"
        assert response.correlation_id is not None

    def test_error_response_with_details(self):
        """Test error response with detailed errors."""
        response = ErrorResponse(
            error=ErrorCode.VALIDATION_ERROR,
            message="Validation failed",
            details=[
                ErrorDetail(field="first_name", message="Required", code="required"),
            ],
        )
        assert len(response.details) == 1
        assert response.details[0].field == "first_name"
        assert response.details[0].message == "Required"
        assert response.details[0].code == "required"
