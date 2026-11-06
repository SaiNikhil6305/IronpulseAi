"""Workout sessions, splits, exercise catalogue and previous-performance queries.

Sessions are synchronised as full snapshots with ids generated on the device.
``upsert_session`` is idempotent: replaying the same snapshot any number of
times yields exactly one session and no duplicate XP. Conflicts between two
devices editing the same session are resolved last-write-wins on
``client_updated_at`` (documented in docs/ARCHITECTURE.md).
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.core.errors import AppError
from app.models import (ExerciseLibrary, WorkoutDay, WorkoutExercise, WorkoutSession, WorkoutSet, WorkoutSplit,
                        WorkoutTemplate)
from app.models.base import utcnow
from app.schemas.workout import SessionIn, SplitIn
from app.services import gamification as g

EXERCISES_FILE = Path(__file__).resolve().parent.parent / "data" / "exercises.json"


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


# ---- Exercise catalogue ------------------------------------------------------------
def seed_exercises(db: Session) -> int:
    """Upsert the catalogue from exercises.json (the single maintained source)."""
    data = json.loads(EXERCISES_FILE.read_text(encoding="utf-8"))
    count = 0
    for e in data["exercises"]:
        row = db.get(ExerciseLibrary, e["id"])
        fields = {k: e.get(k) for k in ("name", "primary_muscle", "secondary_muscles", "equipment", "difficulty",
                                        "instructions", "safety", "alternatives", "unilateral", "tracking",
                                        "media_url", "media_license")}
        fields["secondary_muscles"] = fields["secondary_muscles"] or []
        fields["alternatives"] = fields["alternatives"] or []
        fields["unilateral"] = bool(fields["unilateral"])
        fields["tracking"] = fields["tracking"] or "weight_reps"
        if row is None:
            db.add(ExerciseLibrary(id=e["id"], **fields))
        else:
            for k, v in fields.items():
                setattr(row, k, v)
        count += 1
    db.commit()
    return count


# ---- Splits ---------------------------------------------------------------------------
def upsert_split(db: Session, user_id: uuid.UUID, split_id: uuid.UUID, body: SplitIn, activate: bool = True
                 ) -> WorkoutSplit:
    split = db.get(WorkoutSplit, split_id)
    if split is not None and split.user_id != user_id:
        raise AppError(404, "not_found", "Split not found.")
    if split is None:
        split = WorkoutSplit(id=split_id, user_id=user_id, name=body.name, split_type=body.split_type)
        db.add(split)
    split.name = body.name
    split.split_type = body.split_type
    split.days.clear()
    db.flush()
    for i, d in enumerate(body.days):
        day = WorkoutDay(name=d.name, position=i, muscle_groups=d.muscle_groups,
                         weekdays=sorted({w for w in d.weekdays if 1 <= w <= 7}))
        for j, t in enumerate(d.template_exercises):
            day.template_exercises.append(WorkoutTemplate(exercise_ref=t.exercise_ref, position=j,
                                                          target_sets=t.target_sets, target_reps=t.target_reps))
        split.days.append(day)
    if activate:
        # Older splits are archived, never deleted: history references names, not split rows.
        db.execute(update(WorkoutSplit).where(WorkoutSplit.user_id == user_id, WorkoutSplit.id != split_id,
                                              WorkoutSplit.is_active.is_(True))
                   .values(is_active=False, archived_at=utcnow()))
        split.is_active = True
        split.archived_at = None
    db.commit()
    db.refresh(split)
    return split


def active_split(db: Session, user_id: uuid.UUID) -> WorkoutSplit | None:
    return db.scalar(select(WorkoutSplit).where(WorkoutSplit.user_id == user_id, WorkoutSplit.is_active.is_(True))
                     .options(selectinload(WorkoutSplit.days).selectinload(WorkoutDay.template_exercises)))


# ---- Sessions -------------------------------------------------------------------------
def _load_session(db: Session, session_id: uuid.UUID) -> WorkoutSession | None:
    return db.scalar(select(WorkoutSession).where(WorkoutSession.id == session_id)
                     .options(selectinload(WorkoutSession.exercises).selectinload(WorkoutExercise.sets)))


def upsert_session(db: Session, user_id: uuid.UUID, session_id: uuid.UUID, body: SessionIn) -> dict:
    existing = _load_session(db, session_id)
    if existing is not None and existing.user_id != user_id:
        # Do not reveal that another user's session exists.
        raise AppError(404, "not_found", "Session not found.")

    incoming_ts = _aware(body.client_updated_at)
    if existing is not None and _aware(existing.client_updated_at) >= incoming_ts:
        # Stale or duplicate replay: nothing changes, no XP side effects.
        return {"session": existing, "applied": False, "new_achievements": [], "personal_records": []}

    prs_before = {(p["session_id"], p["exercise_ref"]) for p in g.personal_records(db, user_id)}

    if existing is None:
        existing = WorkoutSession(id=session_id, user_id=user_id)
        db.add(existing)
    s = existing
    s.name = body.name
    s.workout_day_name = body.workout_day_name
    s.status = body.status
    s.started_at = body.started_at
    s.ended_at = body.ended_at
    s.extra_muscle_groups = body.extra_muscle_groups
    s.notes = body.notes
    s.client_updated_at = incoming_ts
    s.exercises.clear()
    db.flush()
    for ex in body.exercises:
        we = WorkoutExercise(id=ex.id, exercise_ref=ex.exercise_ref, exercise_name=ex.exercise_name,
                             position=ex.position, notes=ex.notes)
        for st in ex.sets:
            we.sets.append(WorkoutSet(**st.model_dump()))
        s.exercises.append(we)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise AppError(409, "id_conflict", "An exercise or set id in this session is already in use.") from exc

    g.award_for_session(db, user_id, s)
    new_achievements = g.evaluate_achievements(db, user_id)
    prs = [p for p in g.personal_records(db, user_id)
           if p["session_id"] == str(session_id) and (p["session_id"], p["exercise_ref"]) not in prs_before]
    db.commit()
    s = _load_session(db, session_id)
    return {"session": s, "applied": True, "new_achievements": new_achievements, "personal_records": prs}


def session_xp(db: Session, user_id: uuid.UUID, session_id: uuid.UUID) -> int:
    from app.models import XPTransaction

    return sum(t.amount for t in db.scalars(select(XPTransaction).where(
        XPTransaction.user_id == user_id, XPTransaction.source_id == str(session_id))))


def delete_session(db: Session, user_id: uuid.UUID, session_id: uuid.UUID) -> None:
    s = db.get(WorkoutSession, session_id)
    if s is None or s.user_id != user_id:
        return  # idempotent
    g.delete_session_xp(db, user_id, session_id)
    db.delete(s)
    db.flush()
    g.refresh_weekly_targets(db, user_id)
    db.commit()


def history(db: Session, user_id: uuid.UUID, limit: int, before: datetime | None) -> list[WorkoutSession]:
    q = (select(WorkoutSession).where(WorkoutSession.user_id == user_id, WorkoutSession.status != "discarded")
         .options(selectinload(WorkoutSession.exercises).selectinload(WorkoutExercise.sets))
         .order_by(WorkoutSession.started_at.desc()).limit(limit))
    if before is not None:
        q = q.where(WorkoutSession.started_at < before)
    return list(db.scalars(q))


def previous_performance(db: Session, user_id: uuid.UUID, exercise_ref: str,
                         exclude_session: uuid.UUID | None = None) -> dict:
    q = (select(WorkoutSession)
         .join(WorkoutExercise, WorkoutExercise.session_id == WorkoutSession.id)
         .where(WorkoutSession.user_id == user_id, WorkoutSession.status == "completed",
                WorkoutExercise.exercise_ref == exercise_ref)
         .options(selectinload(WorkoutSession.exercises).selectinload(WorkoutExercise.sets))
         .order_by(WorkoutSession.started_at.desc()).limit(3))
    for s in db.scalars(q).unique():
        if exclude_session and s.id == exclude_session:
            continue
        sets = [st for ex in s.exercises if ex.exercise_ref == exercise_ref for st in ex.sets if st.completed]
        if sets:
            return {"exercise_ref": exercise_ref, "session_id": s.id, "date": s.started_at, "sets": sets}
    return {"exercise_ref": exercise_ref, "session_id": None, "date": None, "sets": []}
