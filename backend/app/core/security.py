"""Supabase access-token verification and the current-user dependency.

Tokens are verified locally:
* HS256 with SUPABASE_JWT_SECRET (legacy projects), or
* asymmetric keys (RS256/ES256) fetched from the project's JWKS endpoint.
The backend never trusts a user id supplied in a request body.
"""
from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass

import jwt
from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.db import get_db
from app.core.errors import AppError
from app.core.rate_limit import limiter

log = logging.getLogger("ironpulse.auth")

_jwks_client: jwt.PyJWKClient | None = None


def _jwks(settings: Settings) -> jwt.PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = jwt.PyJWKClient(f"{settings.supabase_url}/auth/v1/.well-known/jwks.json", cache_keys=True)
    return _jwks_client


@dataclass(frozen=True)
class CurrentUser:
    id: uuid.UUID
    email: str | None


def decode_token(token: str, settings: Settings) -> dict:
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise AppError(401, "invalid_token", "Malformed access token.") from exc

    alg = header.get("alg")
    try:
        if alg == "HS256":
            if not settings.supabase_jwt_secret:
                raise AppError(401, "invalid_token", "HS256 tokens are not accepted by this server.")
            key = settings.supabase_jwt_secret
        elif alg in ("RS256", "ES256"):
            if not settings.supabase_url:
                raise AppError(401, "invalid_token", "Asymmetric tokens require SUPABASE_URL.")
            key = _jwks(settings).get_signing_key_from_jwt(token).key
        else:
            raise AppError(401, "invalid_token", "Unsupported token algorithm.")
        return jwt.decode(
            token, key, algorithms=[alg], audience=settings.supabase_jwt_audience,
            options={"require": ["exp", "sub"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise AppError(401, "token_expired", "Session expired. Please sign in again.") from exc
    except jwt.PyJWTError as exc:
        raise AppError(401, "invalid_token", "Access token could not be verified.") from exc


def get_current_user(request: Request, db: Session = Depends(get_db),
                     settings: Settings = Depends(get_settings)) -> CurrentUser:
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        raise AppError(401, "unauthorized", "Missing bearer token.")
    claims = decode_token(auth[7:].strip(), settings)
    try:
        user_id = uuid.UUID(claims["sub"])
    except (ValueError, KeyError) as exc:
        raise AppError(401, "invalid_token", "Token subject is not a valid user id.") from exc

    allowed, retry = limiter.check(f"api:{user_id}", settings.api_rate_limit_per_minute)
    if not allowed:
        raise AppError(429, "rate_limited", "Too many requests.", {"retry_after_seconds": round(retry, 1)})

    from app.services.users import ensure_user  # local import avoids a cycle

    ensure_user(db, user_id, claims.get("email"))
    return CurrentUser(id=user_id, email=claims.get("email"))
