"""Correlation ID middleware for distributed tracing.

Implements correlation ID propagation as defined in ADR-002.
"""

import uuid
from collections.abc import Awaitable, Callable

import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = structlog.get_logger()


class CorrelationIDMiddleware(BaseHTTPMiddleware):
    """Middleware to add correlation ID to all requests for distributed tracing.

    The correlation ID is:
    - Extracted from X-Correlation-ID header if present
    - Generated as a new UUID if not present
    - Added to structlog context for all log messages
    - Returned in response headers for client tracking

    This enables tracing a single request across multiple services and log entries.
    """

    CORRELATION_ID_HEADER = "X-Correlation-ID"

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        """Process request with correlation ID tracking.

        Args:
            request: The incoming HTTP request
            call_next: The next middleware or route handler

        Returns:
            The HTTP response with correlation ID header
        """
        # Use existing correlation ID from header or generate new one
        correlation_id = request.headers.get(
            self.CORRELATION_ID_HEADER,
            str(uuid.uuid4()),
        )

        # Bind to structlog context for all subsequent log messages
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)

        # Log incoming request
        logger.info(
            "request_started",
            method=request.method,
            path=request.url.path,
            query=str(request.query_params) if request.query_params else None,
            client_ip=request.client.host if request.client else None,
        )

        response: Response | None = None

        try:
            response = await call_next(request)

            # Log response
            logger.info(
                "request_completed",
                method=request.method,
                path=request.url.path,
                status_code=response.status_code,
            )

            return response

        except Exception as e:
            # Log exception with correlation ID
            logger.error(
                "request_failed",
                method=request.method,
                path=request.url.path,
                error=str(e),
                error_type=type(e).__name__,
            )
            raise

        finally:
            # Add correlation ID to response header if response exists
            if response is not None:
                response.headers[self.CORRELATION_ID_HEADER] = correlation_id

            # Clear context to prevent leakage between requests
            structlog.contextvars.unbind_contextvars("correlation_id")
