"""Data export and account deletion.

Deletion order (see docs/PRIVACY_AND_COMPLIANCE.md):
1. Record an AccountDeletionRequest keyed by a one-way hash of the user id.
2. Delete progress-photo objects from private storage (service role, backend only).
3. Delete all database rows (FK ON DELETE CASCADE from ``users``).
4. Delete the Supabase Auth user (revokes all sessions and Google linkage).
5. Mark the request completed (or ``partial`` with a note for manual follow-up).
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, datetime

import httpx
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from app.core.config import Settings
from app.models import (AccountDeletionRequest, AIConversation, ChecklistCompletion, ChecklistItem, ConsentRecord,
                        FitnessGoal, Meal, NotificationPreference, NutritionTarget, ProgressPhoto, SyncedHealthRecord,
                        User, UserAchievement, UserExercise, UserProfile, WearableConnection, WeightMeasurement,
                        WorkoutSplit, XPTransaction, GymSchedule)
from app.models.base import utcnow
from app.services import workouts as w
from app.services.users import audit, user_hash

log = logging.getLogger("ironpulse.account")


def _row(obj, exclude: tuple[str, ...] = ("user_id",)) -> dict:
    out = {}
    for col in obj.__table__.columns:
        if col.name in exclude:
            continue
        v = getattr(obj, col.name)
        if isinstance(v, (uuid.UUID,)):
            v = str(v)
        elif isinstance(v, (datetime, date)):
            v = v.isoformat()
        out[col.name] = v
    return out


def export_user_data(db: Session, user_id: uuid.UUID) -> dict:
    """Everything IronPulse stores about the user, and nothing about anyone else."""
    def owned(model):
        return [_row(r) for r in db.scalars(select(model).where(model.user_id == user_id))]

    sessions = []
    for s in w.history(db, user_id, limit=100_000, before=None):
        d = _row(s)
        d["exercises"] = [{**_row(e, ("session_id",)), "sets": [_row(st, ("workout_exercise_id",)) for st in e.sets]}
                          for e in s.exercises]
        sessions.append(d)
    meals = []
    for m in db.scalars(select(Meal).where(Meal.user_id == user_id).options(selectinload(Meal.entries))):
        d = _row(m)
        d["entries"] = [_row(e, ("meal_id",)) for e in m.entries]
        meals.append(d)
    splits = []
    for sp in db.scalars(select(WorkoutSplit).where(WorkoutSplit.user_id == user_id)):
        d = _row(sp)
        d["days"] = [{**_row(day, ("split_id",)),
                      "exercises": [_row(t, ("day_id",)) for t in day.template_exercises]} for day in sp.days]
        splits.append(d)
    convs = []
    for c in db.scalars(select(AIConversation).where(AIConversation.user_id == user_id)):
        d = _row(c)
        d["messages"] = [_row(m, ("conversation_id",)) for m in c.messages]
        convs.append(d)
    user = db.get(User, user_id)
    return {
        "format": "ironpulse-export-v1",
        "exported_at": utcnow().isoformat(),
        "account": {"id": str(user_id), "email": user.email if user else None},
        "profile": owned(UserProfile),
        "consents": owned(ConsentRecord),
        "workout_splits": splits,
        "workout_sessions": sessions,
        "custom_exercises_and_favorites": owned(UserExercise),
        "xp_transactions": owned(XPTransaction),
        "achievements": owned(UserAchievement),
        "gym_schedule": owned(GymSchedule),
        "notification_preferences": owned(NotificationPreference),
        "checklist_items": owned(ChecklistItem),
        "checklist_completions": owned(ChecklistCompletion),
        "meals": meals,
        "nutrition_targets": owned(NutritionTarget),
        "fitness_goals": owned(FitnessGoal),
        "weight_measurements": owned(WeightMeasurement),
        "progress_photos_metadata": owned(ProgressPhoto),
        "ai_conversations": convs,
        "wearable_connections": owned(WearableConnection),
        "synced_health_records": owned(SyncedHealthRecord),
    }


def _supabase_admin(settings: Settings) -> httpx.Client | None:
    if not (settings.supabase_url and settings.supabase_service_role_key):
        return None
    key = settings.supabase_service_role_key
    return httpx.Client(base_url=settings.supabase_url, timeout=15,
                        headers={"apikey": key, "authorization": f"Bearer {key}"})


def delete_account(db: Session, settings: Settings, user_id: uuid.UUID) -> AccountDeletionRequest:
    req = AccountDeletionRequest(user_hash=user_hash(user_id), status="pending")
    db.add(req)
    db.commit()
    notes: list[str] = []

    photo_paths = list(db.scalars(select(ProgressPhoto.storage_path).where(ProgressPhoto.user_id == user_id)))
    admin = _supabase_admin(settings)

    if photo_paths:
        if admin is None:
            notes.append(f"storage: {len(photo_paths)} photo object(s) not removed (service role not configured)")
        else:
            try:
                r = admin.request("DELETE", f"/storage/v1/object/{settings.progress_photo_bucket}",
                                  json={"prefixes": photo_paths})
                r.raise_for_status()
            except httpx.HTTPError as exc:
                notes.append(f"storage: deletion failed ({type(exc).__name__})")

    # All user-owned rows cascade from users.id. Delete explicitly too for SQLite without FK enforcement.
    db.execute(delete(User).where(User.id == user_id))
    db.commit()

    if admin is None:
        notes.append("auth: Supabase auth user not removed (service role not configured)")
    else:
        try:
            r = admin.delete(f"/auth/v1/admin/users/{user_id}")
            if r.status_code not in (200, 204, 404):
                r.raise_for_status()
        except httpx.HTTPError as exc:
            notes.append(f"auth: deletion failed ({type(exc).__name__})")
        finally:
            admin.close()

    req.status = "completed" if not notes else "partial"
    req.completed_at = utcnow()
    req.notes = "; ".join(notes) or None
    db.commit()
    audit(db, "account_deleted", None, request_id=str(req.id), status=req.status)
    if notes:
        log.warning("account_deletion_partial", extra={"request_id": str(req.id), "notes": req.notes})
    return req
