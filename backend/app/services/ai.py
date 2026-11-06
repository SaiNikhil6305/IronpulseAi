"""IronPulse AI: provider-agnostic chat with privacy-scoped personal context.

* Credentials stay in the backend environment.
* Only context scopes that the user has authorised in their profile AND
  selected for this request are sent to the provider (data minimisation).
* Per-minute rate limits and per-day usage limits are enforced before the
  provider is called. Provider errors never produce fabricated replies.
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import AppError
from app.core.rate_limit import limiter
from app.models import (AIConversation, AIConversationMessage, AIUsageDay, FitnessGoal, Meal, UserProfile,
                        WeightMeasurement)
from app.models.base import utcnow
from app.services import gamification as g
from app.services import workouts as w

log = logging.getLogger("ironpulse.ai")

SYSTEM_PROMPT = """You are IronPulse AI, the fitness assistant inside the IronPulse gym app.
Personality: friendly, direct, motivating, practical, knowledgeable, nonjudgmental, honest about uncertainty.
Rules you must always follow:
- You are not a doctor. Never diagnose medical conditions or replace qualified medical advice.
- If the user mentions pain, injury, chest pain, dizziness, fainting, or other serious symptoms, tell them to stop
  training and consult a qualified health professional (or emergency services if severe).
- Never recommend anabolic steroids, SARMs, prohormones or other performance-enhancing drugs.
- Never guarantee results or timelines. Never encourage max-effort or ego lifting without proper progression,
  technique and safety (spotters, safety bars).
- Nutrition numbers are estimates; say so. Do not prescribe aggressive calorie deficits or individual supplement
  dosages; suggest a registered dietitian for individual plans.
- Use the user's recorded data only as provided below; if data is missing, say so instead of guessing.
- Keep answers concise and skimmable, use metric units unless the user prefers imperial."""

SCOPES = ("profile", "goals", "split", "workouts", "nutrition", "progress")


class AIUnavailable(AppError):
    def __init__(self, message: str = "IronPulse AI is not configured on this server yet."):
        super().__init__(503, "ai_not_configured", message)


# ---- Context ----------------------------------------------------------------------
def build_context(db: Session, user_id: uuid.UUID, scopes: set[str]) -> str:
    parts: list[str] = []
    profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
    if "profile" in scopes and profile:
        parts.append(
            f"Profile: experience={profile.experience or 'unknown'}, units={profile.units}, "
            f"equipment={', '.join(profile.equipment) or 'unknown'}, diet={', '.join(profile.dietary_preferences) or 'none stated'}, "
            f"allergies={'stated (avoid listed allergens): ' + profile.allergies if profile.allergies else 'none stated'}, "
            f"weekly target={profile.weekly_target} workouts.")
    if "goals" in scopes:
        goals = list(db.scalars(select(FitnessGoal).where(FitnessGoal.user_id == user_id,
                                                          FitnessGoal.status == "active")))
        fg = ", ".join(profile.goals) if profile and profile.goals else "none"
        parts.append(f"Fitness goals: {fg}. Active goals: " +
                     ("; ".join(f"{x.title} (until {x.target_date})" for x in goals) or "none") + ".")
    if "split" in scopes:
        split = w.active_split(db, user_id)
        if split:
            days = "; ".join(f"{d.name}: {', '.join(d.muscle_groups)}" for d in split.days)
            parts.append(f"Workout split '{split.name}': {days}.")
    if "workouts" in scopes:
        sessions = w.history(db, user_id, limit=5, before=None)
        lines = []
        for s in sessions:
            ex = []
            for e in s.exercises:
                done = [st for st in e.sets if st.completed]
                if done:
                    best = max(done, key=lambda st: (st.weight_kg or 0, st.reps or 0))
                    ex.append(f"{e.exercise_name} {len(done)} sets, top {best.weight_kg or 0:g} kg x {best.reps or 0}")
            lines.append(f"{s.started_at.date()} {s.name} [{s.status}]: " + ("; ".join(ex) or "no completed sets"))
        parts.append("Recent workouts:\n" + ("\n".join(lines) or "none recorded"))
    if "nutrition" in scopes:
        since = date.today() - timedelta(days=7)
        meals = list(db.scalars(select(Meal).where(Meal.user_id == user_id, Meal.day >= since,
                                                   Meal.is_saved_template.is_(False))))
        per_day: dict[date, list[float]] = {}
        for m in meals:
            acc = per_day.setdefault(m.day, [0.0, 0.0])
            for e in m.entries:
                acc[0] += (e.calories or 0) * e.quantity
                acc[1] += (e.protein_g or 0) * e.quantity
        txt = "; ".join(f"{d}: ~{v[0]:.0f} kcal, ~{v[1]:.0f} g protein" for d, v in sorted(per_day.items()))
        parts.append("Logged nutrition, last 7 days (user-entered, may be estimates): " + (txt or "none logged"))
    if "progress" in scopes:
        tz = g.tz_for(profile)
        streak = g.compute_streaks(g.qualifying_workout_dates(db, user_id, tz),
                                   profile.weekly_target if profile else 3, date.today())
        weights = list(db.scalars(select(WeightMeasurement).where(WeightMeasurement.user_id == user_id)
                                  .order_by(WeightMeasurement.day.desc()).limit(6)))
        prs = g.personal_records(db, user_id)[-5:]
        parts.append(
            f"Progress: {streak['total_workouts']} workouts total, consistency streak {streak['current_streak_weeks']} "
            f"week(s). Recent weigh-ins: " + (", ".join(f"{m.day} {m.weight_kg:g} kg" for m in weights) or "none") +
            ". Recent PRs: " + (", ".join(f"{p['exercise_name']} {p['weight_kg']:g}x{p['reps']}" for p in prs) or "none") + ".")
    return "\n".join(parts)


# ---- Providers --------------------------------------------------------------------
def call_provider(settings: Settings, system: str, messages: list[dict]) -> str:
    if not settings.ai_configured:
        raise AIUnavailable()
    try:
        with httpx.Client(timeout=settings.ai_timeout_seconds) as client:
            if settings.ai_provider == "anthropic":
                resp = client.post(
                    (settings.ai_base_url or "https://api.anthropic.com").rstrip("/") + "/v1/messages",
                    headers={"x-api-key": settings.ai_api_key, "anthropic-version": "2023-06-01",
                             "content-type": "application/json"},
                    json={"model": settings.ai_model, "max_tokens": settings.ai_max_output_tokens,
                          "system": system, "messages": messages})
                resp.raise_for_status()
                data = resp.json()
                text = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")
            else:  # openai_compatible
                resp = client.post(
                    settings.ai_base_url.rstrip("/") + "/chat/completions",
                    headers={"authorization": f"Bearer {settings.ai_api_key}", "content-type": "application/json"},
                    json={"model": settings.ai_model, "max_tokens": settings.ai_max_output_tokens,
                          "messages": [{"role": "system", "content": system}, *messages]})
                resp.raise_for_status()
                text = resp.json()["choices"][0]["message"]["content"] or ""
    except httpx.TimeoutException as exc:
        raise AppError(504, "ai_timeout", "IronPulse AI took too long to respond. Please try again.") from exc
    except httpx.HTTPStatusError as exc:
        log.warning("ai_provider_error", extra={"status": exc.response.status_code})
        raise AppError(502, "ai_provider_error", "IronPulse AI is temporarily unavailable.") from exc
    except (httpx.HTTPError, KeyError, ValueError) as exc:
        log.warning("ai_provider_failure", extra={"error": type(exc).__name__})
        raise AppError(502, "ai_provider_error", "IronPulse AI is temporarily unavailable.") from exc
    text = text.strip()
    if not text:
        raise AppError(502, "ai_provider_error", "IronPulse AI returned an empty response.")
    return text


# ---- Chat -------------------------------------------------------------------------
def _usage_row(db: Session, user_id: uuid.UUID, day: date) -> AIUsageDay:
    row = db.scalar(select(AIUsageDay).where(AIUsageDay.user_id == user_id, AIUsageDay.day == day))
    if row is None:
        row = AIUsageDay(user_id=user_id, day=day, message_count=0)
        db.add(row)
        try:
            db.flush()
        except IntegrityError:
            db.rollback()
            row = db.scalar(select(AIUsageDay).where(AIUsageDay.user_id == user_id, AIUsageDay.day == day))
    return row


def chat(db: Session, settings: Settings, user_id: uuid.UUID, conversation_id: uuid.UUID | None, message: str,
         requested_scopes: list[str]) -> dict:
    if not settings.ai_configured:
        raise AIUnavailable()
    message = message.strip()
    if not message:
        raise AppError(422, "validation_error", "Message is empty.")
    if len(message) > settings.ai_max_input_chars:
        raise AppError(422, "message_too_long", f"Messages are limited to {settings.ai_max_input_chars} characters.")

    allowed, retry = limiter.check(f"ai:{user_id}", settings.ai_rate_limit_per_minute)
    if not allowed:
        raise AppError(429, "rate_limited", "You're sending messages too quickly.",
                       {"retry_after_seconds": round(retry, 1)})
    today = utcnow().date()
    usage = _usage_row(db, user_id, today)
    if usage.message_count >= settings.ai_daily_message_limit:
        raise AppError(429, "daily_limit_reached",
                       f"You've reached today's limit of {settings.ai_daily_message_limit} IronPulse AI messages.")

    if conversation_id is not None:
        conv = db.get(AIConversation, conversation_id)
        if conv is None or conv.user_id != user_id:
            raise AppError(404, "not_found", "Conversation not found.")
    else:
        conv = AIConversation(user_id=user_id, title=message[:60])
        db.add(conv)
        db.flush()

    profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
    authorised = set(profile.ai_context_scopes or []) if profile else set()
    scopes = authorised & set(requested_scopes) & set(SCOPES)
    context = build_context(db, user_id, scopes) if scopes else ""
    system = SYSTEM_PROMPT + ("\n\nUser data the user has chosen to share:\n" + context if context else
                              "\n\nThe user has not shared personal training data for this message.")

    history = [{"role": m.role, "content": m.content} for m in conv.messages[-12:]]
    history.append({"role": "user", "content": message})
    reply = call_provider(settings, system, history)

    now = utcnow()
    db.add(AIConversationMessage(conversation_id=conv.id, role="user", content=message, created_at=now))
    db.add(AIConversationMessage(conversation_id=conv.id, role="assistant", content=reply, created_at=now))
    conv.updated_at = now
    usage.message_count += 1
    db.commit()
    return {"conversation_id": conv.id, "reply": reply,
            "remaining_today": max(0, settings.ai_daily_message_limit - usage.message_count),
            "context_scopes_used": sorted(scopes)}
