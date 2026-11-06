"""Application configuration loaded from environment variables.

Secrets live only in the backend environment. Nothing in this module is ever
sent to the mobile client.
"""
from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    environment: Literal["development", "test", "production"] = "development"
    database_url: str = "sqlite:///./ironpulse_dev.db"

    # --- Supabase -----------------------------------------------------------
    supabase_url: str = ""  # e.g. https://<project-ref>.supabase.co
    # Legacy projects sign access tokens with a shared HS256 secret. Newer
    # projects use asymmetric keys published at /auth/v1/.well-known/jwks.json.
    supabase_jwt_secret: str = ""
    supabase_service_role_key: str = ""  # used only for account deletion + storage cleanup
    supabase_jwt_audience: str = "authenticated"
    progress_photo_bucket: str = "progress-photos"

    # --- AI provider (server-side only) ------------------------------------
    ai_provider: Literal["", "anthropic", "openai_compatible"] = ""
    ai_api_key: str = ""
    ai_model: str = ""
    ai_base_url: str = ""  # required for openai_compatible
    ai_timeout_seconds: float = 40.0
    # Sent to OpenAI-compatible providers; "low" keeps Gemini 3 "thinking" short so replies arrive fast.
    ai_reasoning_effort: str = "low"
    ai_max_output_tokens: int = 900
    ai_rate_limit_per_minute: int = 6
    ai_daily_message_limit: int = 50
    ai_max_input_chars: int = 2000

    # --- Operational --------------------------------------------------------
    cors_origins: list[str] = Field(default_factory=list)
    max_request_bytes: int = 1_000_000
    api_rate_limit_per_minute: int = 240
    log_level: str = "INFO"

    @field_validator("supabase_url")
    @classmethod
    def _strip_slash(cls, v: str) -> str:
        return v.rstrip("/")

    @property
    def ai_configured(self) -> bool:
        if not (self.ai_provider and self.ai_api_key and self.ai_model):
            return False
        if self.ai_provider == "openai_compatible" and not self.ai_base_url:
            return False
        return True

    @property
    def auth_configured(self) -> bool:
        return bool(self.supabase_jwt_secret or self.supabase_url)

    def validate_for_startup(self) -> list[str]:
        """Return a list of human-readable configuration problems."""
        problems: list[str] = []
        if not self.auth_configured:
            problems.append("SUPABASE_URL or SUPABASE_JWT_SECRET must be set to verify user tokens.")
        if self.environment == "production":
            if self.database_url.startswith("sqlite"):
                problems.append("DATABASE_URL must point to PostgreSQL in production.")
            if not self.supabase_service_role_key:
                problems.append("SUPABASE_SERVICE_ROLE_KEY is required in production for account deletion.")
        return problems


@lru_cache
def get_settings() -> Settings:
    return Settings()
