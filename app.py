"""IronPulse AI server.

A small, stateless FastAPI service that sits between the phone and an AI model.
- Provider keys never reach the phone; the phone only holds IRONPULSE_AI_TOKEN.
- Requests are authenticated, size-limited, validated and rate-limited.
- Message content is never logged.
"""

from __future__ import annotations

import hmac
import logging
import time
from collections import defaultdict, deque
from functools import lru_cache
from typing import Literal

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

log = logging.getLogger("ironpulse.ai")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

MAX_BODY_BYTES = 64_000


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    ironpulse_ai_token: str = Field(..., min_length=24)
    ai_provider: Literal["ollama", "openai_compatible"] = "ollama"
    ai_model: str = "llama3.2:3b"
    ollama_url: str = "http://127.0.0.1:11434"
    ai_base_url: str | None = None
    ai_api_key: str | None = None
    rate_limit_per_minute: int = 10
    daily_message_limit: int = 200
    ai_timeout_seconds: float = 90


@lru_cache
def get_settings() -> Settings:
    return Settings()  # raises at startup if the token is missing or too short


SYSTEM_PROMPT = """You are IronPulse AI, the fitness assistant inside the IronPulse gym app.
Personality: friendly, direct, motivating, practical, nonjudgmental. Keep answers concise and skimmable
(short paragraphs or bullet points). Use kg unless the user uses other units.

Rules you must always follow:
- You are not a doctor. Never diagnose conditions or injuries. For pain, injury, dizziness, chest pain or
  other serious symptoms, tell the user to stop and see a qualified professional.
- Never recommend steroids, SARMs, prohibited substances, or unsafe supplement doses. Do not prescribe
  individual supplement dosages.
- Never encourage dangerous lifting: no ego lifting, maxing out without a spotter or safety bars, or
  training through sharp pain. Favor good form and gradual progressive overload.
- Never guarantee results or timelines. Be honest when unsure.
- Do not prescribe aggressive calorie deficits or extreme diets.
- If training data is provided, use only those numbers and do not invent workouts, weights or history.
  If no data is provided, say you can't see their history and give general guidance.
"""


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(..., min_length=1, max_length=4000)


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., min_length=1, max_length=20)
    # Optional, user-approved summary built on the phone. Kept small on purpose.
    context: str | None = Field(default=None, max_length=4000)

    @field_validator("messages")
    @classmethod
    def last_is_user(cls, v: list[ChatMessage]) -> list[ChatMessage]:
        if v[-1].role != "user":
            raise ValueError("last message must be from the user")
        return v


class ChatResponse(BaseModel):
    reply: str
    model: str


class RateLimiter:
    """In-memory sliding window per token. Fine for one personal server; use Redis if scaled out."""

    def __init__(self) -> None:
        self.minute: dict[str, deque[float]] = defaultdict(deque)
        self.day: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str, per_minute: int, per_day: int) -> None:
        now = time.monotonic()
        for q, window, limit, label in (
            (self.minute[key], 60, per_minute, "Too many messages - wait a minute and try again."),
            (self.day[key], 86_400, per_day, "Daily message limit reached. Try again tomorrow."),
        ):
            while q and now - q[0] > window:
                q.popleft()
            if len(q) >= limit:
                raise HTTPException(429, {"code": "rate_limited", "message": label})
        self.minute[key].append(now)
        self.day[key].append(now)


limiter = RateLimiter()


def require_token(request: Request, settings: Settings = Depends(get_settings)) -> str:
    auth = request.headers.get("authorization", "")
    token = auth[7:] if auth.lower().startswith("bearer ") else ""
    if not token or not hmac.compare_digest(token.encode(), settings.ironpulse_ai_token.encode()):
        raise HTTPException(401, {"code": "unauthorized", "message": "Invalid or missing access token."})
    return token


class ProviderError(Exception):
    def __init__(self, message: str, status: int = 503) -> None:
        super().__init__(message)
        self.message = message
        self.status = status


async def call_model(settings: Settings, messages: list[dict[str, str]]) -> str:
    timeout = httpx.Timeout(settings.ai_timeout_seconds, connect=5)
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            if settings.ai_provider == "ollama":
                r = await client.post(
                    settings.ollama_url.rstrip("/") + "/api/chat",
                    json={"model": settings.ai_model, "messages": messages, "stream": False,
                          "options": {"temperature": 0.6}},
                )
                if r.status_code == 404:
                    raise ProviderError(f"Model '{settings.ai_model}' is not installed. Run: ollama pull {settings.ai_model}")
                r.raise_for_status()
                return r.json()["message"]["content"].strip()
            if not settings.ai_base_url or not settings.ai_api_key:
                raise ProviderError("AI provider is not configured: set AI_BASE_URL and AI_API_KEY.")
            r = await client.post(
                settings.ai_base_url.rstrip("/") + "/chat/completions",
                headers={"authorization": f"Bearer {settings.ai_api_key}"},
                json={"model": settings.ai_model, "messages": messages, "temperature": 0.6},
            )
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"].strip()
    except ProviderError:
        raise
    except httpx.ConnectError as e:
        hint = "Is Ollama running? Start it with: ollama serve" if settings.ai_provider == "ollama" else "Provider unreachable."
        raise ProviderError(f"Cannot reach the AI model. {hint}") from e
    except httpx.TimeoutException as e:
        raise ProviderError("The AI model took too long to answer. Try a shorter question or a smaller model.", 504) from e
    except (httpx.HTTPStatusError, KeyError, ValueError) as e:
        raise ProviderError("The AI model returned an error.", 502) from e


app = FastAPI(title="IronPulse AI", version="0.1.0", docs_url=None, redoc_url=None)


@app.middleware("http")
async def limit_body(request: Request, call_next):  # type: ignore[no-untyped-def]
    length = request.headers.get("content-length")
    if length and int(length) > MAX_BODY_BYTES:
        return JSONResponse({"error": {"code": "too_large", "message": "Request too large."}}, status_code=413)
    start = time.monotonic()
    response = await call_next(request)
    # Structured access log without bodies, tokens or personal data.
    log.info("path=%s status=%s ms=%d", request.url.path, response.status_code, (time.monotonic() - start) * 1000)
    return response


@app.exception_handler(HTTPException)
async def http_error(_: Request, exc: HTTPException) -> JSONResponse:
    body = exc.detail if isinstance(exc.detail, dict) else {"code": "error", "message": str(exc.detail)}
    return JSONResponse({"error": body}, status_code=exc.status_code)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/status")
async def status(_: str = Depends(require_token), settings: Settings = Depends(get_settings)) -> dict[str, object]:
    """Lets the app show whether the model is actually reachable."""
    ok, detail = True, "ready"
    if settings.ai_provider == "ollama":
        try:
            async with httpx.AsyncClient(timeout=5) as c:
                tags = (await c.get(settings.ollama_url.rstrip("/") + "/api/tags")).json()
            names = {m.get("name", "") for m in tags.get("models", [])}
            if not any(n == settings.ai_model or n.split(":")[0] == settings.ai_model for n in names):
                ok, detail = False, f"Model not installed. Run: ollama pull {settings.ai_model}"
        except Exception:
            ok, detail = False, "Ollama is not running. Start it with: ollama serve"
    elif not settings.ai_base_url or not settings.ai_api_key:
        ok, detail = False, "AI_BASE_URL / AI_API_KEY not set"
    return {"ok": ok, "detail": detail, "provider": settings.ai_provider, "model": settings.ai_model}


@app.post("/v1/chat", response_model=ChatResponse)
async def chat(body: ChatRequest, token: str = Depends(require_token), settings: Settings = Depends(get_settings)) -> ChatResponse:
    limiter.check(token, settings.rate_limit_per_minute, settings.daily_message_limit)
    system = SYSTEM_PROMPT
    if body.context:
        system += "\n\nUser's training data (shared with their permission):\n" + body.context
    msgs = [{"role": "system", "content": system}] + [m.model_dump() for m in body.messages]
    try:
        reply = await call_model(settings, msgs)
    except ProviderError as e:
        raise HTTPException(e.status, {"code": "provider_error", "message": e.message}) from e
    if not reply:
        raise HTTPException(502, {"code": "provider_error", "message": "The AI model returned an empty answer."})
    return ChatResponse(reply=reply, model=settings.ai_model)


if __name__ == "__main__":
    import uvicorn

    get_settings()
    import os; uvicorn.run(app, host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "8000")), proxy_headers=True, forwarded_allow_ips="*")

