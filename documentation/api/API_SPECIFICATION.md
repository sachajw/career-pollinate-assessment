# Applicant Validator API Specification

**Version:** 1.0.0
**Base URL:** `https://{environment}.finrisk.example.com/api/v1`

## Overview

The Applicant Validator provides fraud risk validation for loan applicants. It integrates with RiskShield's fraud detection service to return risk scores and recommendations.

## Authentication

> **Note:** API authentication is planned for a future release. The current implementation does not require authentication.

```http
# Future: Bearer token authentication (not yet implemented)
Authorization: Bearer <your-api-key>
```

Contact the Platform Engineering team to obtain API credentials when available.

## Rate Limiting

| Tier | Requests/Minute | Requests/Day |
|------|-----------------|--------------|
| Default | 100 | 10,000 |
| Enterprise | 1,000 | 100,000 |

> **Note:** Rate limiting headers are planned for a future release. The current implementation does not include rate limiting.

When rate limited (future implementation), the API returns HTTP 429:

```json
{
  "error": "RATE_LIMIT_ERROR",
  "message": "Rate limit exceeded. Please try again later.",
  "correlationId": "uuid"
}
```

---

## Endpoints

### POST /validate

Validates a loan applicant and returns their fraud risk score.

#### Request

**Content-Type:** `application/json`

```json
{
  "firstName": "string",    // Required, 1-100 characters
  "lastName": "string",     // Required, 1-100 characters
  "idNumber": "string"      // Required, 13-digit South African ID
}
```

**Field Validation:**

| Field | Type | Constraints |
|-------|------|-------------|
| `firstName` | string | 1-100 chars, letters/spaces/hyphens only |
| `lastName` | string | 1-100 chars, letters/spaces/hyphens only |
| `idNumber` | string | Exactly 13 digits, valid SA ID format |

**ID Number Validation:**
- Must be exactly 13 digits
- Digits 1-6: Birth date (YYMMDD)
- Digits 7-10: Sequence number
- Digit 11: Citizenship indicator (0=SA citizen, 1=permanent resident)
- Digit 12: Previously used for race classification (now 8 or 9)
- Digit 13: Luhn checksum digit

> **Note:** Luhn checksum validation is planned for a future release. Current implementation validates length and numeric content only.

#### Response

**Success (200 OK)**

```json
{
  "riskScore": 72,
  "riskLevel": "MEDIUM",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `riskScore` | integer | Risk score from 0 (lowest) to 100 (highest) |
| `riskLevel` | string | Categorical risk: LOW, MEDIUM, HIGH, CRITICAL |
| `correlationId` | string (UUID) | Unique identifier for request tracing |

#### Risk Level Interpretation

| Level | Score Range | Action |
|-------|-------------|--------|
| `LOW` | 0-29 | Proceed with standard processing |
| `MEDIUM` | 30-59 | Request additional documentation |
| `HIGH` | 60-79 | Escalate to manual review |
| `CRITICAL` | 80-100 | Decline or escalate to fraud team |

#### Error Responses

**400 Bad Request - Validation Error**

```json
{
  "error": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "details": [
    {
      "field": "idNumber",
      "message": "Invalid ID number (checksum failed)",
      "code": "invalid_checksum"
    }
  ]
}
```

**401 Unauthorized**

> **Note:** Authentication is planned for a future release.

```json
{
  "error": "AUTHENTICATION_ERROR",
  "message": "Invalid or expired API key",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**429 Too Many Requests**

```json
{
  "error": "RATE_LIMIT_ERROR",
  "message": "Rate limit exceeded. Retry after 60 seconds.",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**503 Service Unavailable**

```json
{
  "error": "UPSTREAM_ERROR",
  "message": "Risk validation service is temporarily unavailable",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**504 Gateway Timeout**

```json
{
  "error": "TIMEOUT_ERROR",
  "message": "Risk validation service timed out",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

---

## Health Endpoints

### GET /health

Returns the health status of the API.

**Response:**

```json
{
  "status": "healthy",
  "version": "0.1.0",
  "environment": "dev"
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Service health status ("healthy") |
| `version` | string | Service version |
| `environment` | string | Deployment environment (dev/staging/prod) |

### GET /ready

Returns whether the API is ready to accept requests.

**Response:**

```json
{
  "ready": true,
  "checks": {
    "riskshield_api": true
  }
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `ready` | boolean | Overall readiness status |
| `checks` | object | Individual dependency check results |
| `checks.riskshield_api` | boolean | RiskShield API connectivity |

---

## Error Codes Reference

| Code | HTTP Status | Description | Retryable |
|------|-------------|-------------|-----------|
| `VALIDATION_ERROR` | 400 | Invalid request data | No |
| `AUTHENTICATION_ERROR` | 401 | Invalid or missing credentials | No |
| `RATE_LIMIT_ERROR` | 429 | Rate limit exceeded | Yes (after cooldown) |
| `UPSTREAM_ERROR` | 502, 503 | Upstream service error | Yes |
| `TIMEOUT_ERROR` | 504 | Request timeout | Yes |
| `INTERNAL_ERROR` | 500 | Unexpected server error | Yes |

---

## SDK Examples

### Python

```python
import httpx

async def validate_applicant(first_name: str, last_name: str, id_number: str) -> dict:
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "https://api.finrisk.example.com/api/v1/validate",
            # Note: Authentication header will be required in future release
            # headers={"Authorization": "Bearer YOUR_API_KEY"},
            json={
                "firstName": first_name,
                "lastName": last_name,
                "idNumber": id_number,
            },
            timeout=30.0,
        )
        response.raise_for_status()
        return response.json()
```

### cURL

```bash
curl -X POST https://api.finrisk.example.com/api/v1/validate \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "idNumber": "9001011234088"
  }'
```

### JavaScript/TypeScript

```typescript
async function validateApplicant(
  firstName: string,
  lastName: string,
  idNumber: string
): Promise<ValidationResponse> {
  const response = await fetch('https://api.finrisk.example.com/api/v1/validate', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      // Note: Authorization header will be required in future release
      // 'Authorization': 'Bearer YOUR_API_KEY',
    },
    body: JSON.stringify({
      firstName,
      lastName,
      idNumber,
    }),
  });

  if (!response.ok) {
    throw new Error(`API error: ${response.status}`);
  }

  return response.json();
}

interface ValidationResponse {
  riskScore: number;
  riskLevel: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  correlationId: string;
}
```

---

## Changelog

### v0.1.0 (2026-02-16)
- Initial release
- POST /validate endpoint
- Health and readiness endpoints
- Correlation ID tracking

### Planned
- Rate limiting
- Bearer token authentication
- Luhn checksum validation for SA ID numbers
