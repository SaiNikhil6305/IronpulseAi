"""Structured JSON logging that never emits tokens or passwords."""
from __future__ import annotations

import json
import logging
import re
import sys
from datetime import datetime, timezone

_REDACT_KEYS = {"authorization", "password", "token", "access_token", "refresh_token", "api_key", "secret"}
_BEARER = re.compile(r"(Bearer\s+)[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE)


def redact(value):
    if isinstance(value, dict):
        return {k: ("[REDACTED]" if k.lower() in _REDACT_KEYS else redact(v)) for k, v in value.items()}
    if isinstance(value, str):
        return _BEARER.sub(r"\1[REDACTED]", value)
    return value


class JsonFormatter(logging.Formatter):
    _std = set(vars(logging.makeLogRecord({})).keys()) | {"message", "asctime"}

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": redact(record.getMessage()),
        }
        for k, v in record.__dict__.items():
            if k not in self._std:
                payload[k] = redact(v)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
