"""IronPulse API entrypoint. Run: uvicorn app.main:app --reload"""
from __future__ import annotations

import logging
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api import ai, profile, sync, tracking, workouts
from app.core.config import get_settings
from app.core.db import Base, SessionLocal, engine
from app.core.errors import install_error_handlers
from app.core.logging import configure_logging

log = logging.getLogger("ironpulse.api")


def _bootstrap() -> None:
    import app.models  # noqa: F401  (register tables)
    from app.services.gamification import seed_achievements
    from app.services.workouts import seed_exercises

    settings = get_settings()
    if settings.database_url.startswith("sqlite"):
        # Local development / tests only. PostgreSQL schemas are managed by Alembic.
        Base.metadata.create_all(engine)
    with SessionLocal() as db:
        seed_exercises(db)
        seed_achievements(db)


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    configure_logging(settings.log_level)
    problems = settings.validate_for_startup()
    for p in problems:
        log.error("configuration_problem", extra={"problem": p})
    if problems and settings.environment == "production":
        raise RuntimeError("Invalid production configuration: " + " | ".join(problems))
    if not settings.ai_configured:
        log.warning("ai_not_configured")
    _bootstrap()
    yield


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="IronPulse API", version="1.0.0", lifespan=lifespan,
                  description="Backend for the IronPulse fitness app. All /v1 endpoints require a Supabase access "
                              "token in the Authorization header.",
                  docs_url="/docs" if settings.environment != "production" else None)
    install_error_handlers(app)
    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_methods=["*"],
                           allow_headers=["authorization", "content-type"])

    @app.middleware("http")
    async def guard(request: Request, call_next):
        length = request.headers.get("content-length")
        if length and length.isdigit() and int(length) > settings.max_request_bytes:
            return JSONResponse(status_code=413, content={"error": {"code": "payload_too_large",
                                                                    "message": "Request body too large."}})
        rid = request.headers.get("x-request-id") or str(uuid.uuid4())
        start = time.perf_counter()
        response = await call_next(request)
        response.headers["x-request-id"] = rid
        response.headers["x-content-type-options"] = "nosniff"
        response.headers["cache-control"] = "no-store"
        log.info("request", extra={"rid": rid, "method": request.method, "path": request.url.path,
                                   "status": response.status_code,
                                   "ms": round((time.perf_counter() - start) * 1000, 1)})
        return response

    @app.get("/health", tags=["ops"])
    def health():
        return {"status": "ok"}

    @app.get("/ready", tags=["ops"])
    def ready():
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
        except Exception:  # pragma: no cover
            return JSONResponse(status_code=503, content={"status": "database_unavailable"})
        return {"status": "ready", "ai_available": settings.ai_configured}

    for r in (profile.router, workouts.router, tracking.router, ai.router, sync.router):
        app.include_router(r)
    return app


app = create_app()
