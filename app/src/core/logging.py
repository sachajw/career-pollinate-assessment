"""Structured logging configuration using structlog.

Provides JSON-formatted logs with:
- Correlation IDs for request tracing
- Azure Application Insights integration
- Configurable log levels
- Sensitive data redaction
"""

import logging
import sys
from contextvars import ContextVar
from typing import Any

import structlog
from structlog.types import EventDict, Processor

from src.core.config import get_settings

# Context variable for correlation ID tracking
correlation_id_var: ContextVar[str | None] = ContextVar("correlation_id", default=None)


def add_correlation_id(logger: Any, method_name: str, event_dict: EventDict) -> EventDict:
    """Add correlation ID to log entries if available."""
    correlation_id = correlation_id_var.get()
    if correlation_id:
        event_dict["correlation_id"] = correlation_id
    return event_dict


def redact_sensitive_fields(logger: Any, method_name: str, event_dict: EventDict) -> EventDict:
    """Redact sensitive fields from log entries."""
    sensitive_fields = {
        "password",
        "secret",
        "api_key",
        "apikey",
        "authorization",
        "token",
        "credential",
        "id_number",
        "firstname",
        "lastname",
    }

    def redact_dict(d: dict[str, Any]) -> dict[str, Any]:
        return {
            k: "***REDACTED***" if k.lower() in sensitive_fields else (
                redact_dict(v) if isinstance(v, dict) else v
            )
            for k, v in d.items()
        }

    return redact_dict(event_dict)


def get_log_level() -> str:
    """Get log level from settings."""
    return get_settings().log_level


def setup_logging() -> None:
    """Configure structured logging for the application.

    Sets up JSON-formatted logs with correlation ID tracking
    and sensitive field redaction.
    """
    # Shared processors for all loggers
    shared_processors: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.UnicodeDecoder(),
        add_correlation_id,
        redact_sensitive_fields,
    ]

    # Configure structlog
    structlog.configure(
        processors=shared_processors
        + [
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    # Configure standard library logging
    formatter = structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=shared_processors,
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            structlog.processors.JSONRenderer(),
        ],
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.addHandler(handler)
    root_logger.setLevel(getattr(logging, get_log_level()))

    # Reduce noise from third-party libraries
    logging.getLogger("azure").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


def set_correlation_id(correlation_id: str) -> None:
    """Set the correlation ID for the current request context.

    Args:
        correlation_id: Unique identifier for request tracing.
    """
    correlation_id_var.set(correlation_id)


def get_correlation_id() -> str | None:
    """Get the current correlation ID from context.

    Returns:
        The correlation ID if set, None otherwise.
    """
    return correlation_id_var.get()


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    """Get a configured logger instance.

    Args:
        name: Logger name, typically __name__ of the calling module.

    Returns:
        A configured structlog logger instance.
    """
    return structlog.get_logger(name)
