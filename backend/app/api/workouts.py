from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.core.errors import AppError
from app.core.security import CurrentUser, get_current_user
from app.models import ExerciseLibrary, UserExercise
from app.schemas.common import Page
from app.schemas.workout import (CustomExerciseIn, CustomExerciseOut, ExerciseOut, PreviousPerformance, SessionIn,
                                 SessionOut, SessionSyncResult, SplitIn, SplitOut)
from app.services import workouts as w

router = APIRouter(prefix="/v1", tags=["workouts"])


# ---- Exercise library ---------------------------------------------------------
@router.get("/exercises", response_model=list[ExerciseOut])
def list_exercises(q: str | None = Query(default=None, max_length=60), muscle: str | None = None,
                   equipment: str | None = None, difficulty: str | None = None,
                   _: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    stmt = select(ExerciseLibrary).order_by(ExerciseLibrary.primary_muscle, ExerciseLibrary.name)
    if q:
        stmt = stmt.where(ExerciseLibrary.name.ilike(f"%{q}%"))
    if muscle:
        stmt = stmt.where(ExerciseLibrary.primary_muscle == muscle)
    if equipment:
        stmt = stmt.where(ExerciseLibrary.equipment == equipment)
    if difficulty:
        stmt = stmt.where(ExerciseLibrary.difficulty == difficulty)
    return list(db.scalars(stmt))


@router.get("/user-exercises", response_model=list[CustomExerciseOut])
def list_user_exercises(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(UserExercise).where(UserExercise.user_id == user.id)))


@router.put("/user-exercises/{item_id}", response_model=CustomExerciseOut)
def put_user_exercise(item_id: uuid.UUID, body: CustomExerciseIn, user: CurrentUser = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    row = db.get(UserExercise, item_id)
    if row is not None and row.user_id != user.id:
        raise AppError(404, "not_found", "Exercise not found.")
    if row is None:
        row = UserExercise(id=item_id, user_id=user.id)
        db.add(row)
    for k, v in body.model_dump(exclude={"id"}).items():
        setattr(row, k, v)
    db.commit()
    return row


@router.delete("/user-exercises/{item_id}", status_code=204)
def delete_user_exercise(item_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
                         db: Session = Depends(get_db)):
    row = db.get(UserExercise, item_id)
    if row is not None and row.user_id == user.id:
        db.delete(row)
        db.commit()
    return Response(status_code=204)


# ---- Splits ---------------------------------------------------------------------
@router.get("/splits/active", response_model=SplitOut | None)
def get_active_split(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return w.active_split(db, user.id)


@router.put("/splits/{split_id}", response_model=SplitOut)
def put_split(split_id: uuid.UUID, body: SplitIn, user: CurrentUser = Depends(get_current_user),
              db: Session = Depends(get_db)):
    return w.upsert_split(db, user.id, split_id, body)


# ---- Sessions -------------------------------------------------------------------
@router.put("/sessions/{session_id}", response_model=SessionSyncResult)
def put_session(session_id: uuid.UUID, body: SessionIn, user: CurrentUser = Depends(get_current_user),
                db: Session = Depends(get_db)):
    """Idempotent upsert of a full session snapshot (used by the offline sync queue)."""
    res = w.upsert_session(db, user.id, session_id, body)
    s = res["session"]
    return SessionSyncResult(id=s.id, applied=res["applied"], server_updated_at=s.updated_at,
                             xp_from_session=w.session_xp(db, user.id, s.id),
                             new_achievements=res["new_achievements"], personal_records=res["personal_records"])


@router.get("/sessions/{session_id}", response_model=SessionOut)
def get_session(session_id: uuid.UUID, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    s = w._load_session(db, session_id)
    if s is None or s.user_id != user.id:
        raise AppError(404, "not_found", "Session not found.")
    return s


@router.delete("/sessions/{session_id}", status_code=204)
def delete_session(session_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
                   db: Session = Depends(get_db)):
    w.delete_session(db, user.id, session_id)
    return Response(status_code=204)


@router.get("/sessions", response_model=Page[SessionOut])
def list_sessions(limit: int = Query(default=20, ge=1, le=100), before: datetime | None = None,
                  user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = w.history(db, user.id, limit + 1, before)
    nxt = rows[limit - 1].started_at.isoformat() if len(rows) > limit else None
    return Page[SessionOut](items=rows[:limit], next_cursor=nxt)


@router.get("/exercises/{exercise_ref}/previous", response_model=PreviousPerformance)
def previous(exercise_ref: str, exclude_session: uuid.UUID | None = None,
             user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    if len(exercise_ref) > 64:
        raise AppError(422, "validation_error", "exercise_ref too long")
    return w.previous_performance(db, user.id, exercise_ref, exclude_session)

