"""
Structured JSON logging configuration for the PII Redaction Service.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime


class _JsonFormatter(logging.Formatter):
    """Emit log records as single-line JSON objects."""

    RESERVED = {"message", "levelname", "name", "asctime", "exc_info", "exc_text", "stack_info"}

    def format(self, record: logging.LogRecord) -> str:
        payload: dict = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Attach any extra keys passed via extra={} on the log call
        for key, val in record.__dict__.items():
            if key not in logging.LogRecord.__dict__ and key not in self.RESERVED and not key.startswith("_"):
                payload[key] = val

        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO") -> None:
    """
    Replace the root handler with a single JSON-to-stdout handler.
    Should be called once at application startup (lifespan).
    """
    root = logging.getLogger()
    root.setLevel(level.upper())

    for handler in root.handlers[:]:
        root.removeHandler(handler)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JsonFormatter())
    root.addHandler(handler)

    # Suppress noisy uvicorn access logs (we log requests ourselves)
    logging.getLogger("uvicorn.access").propagate = False
