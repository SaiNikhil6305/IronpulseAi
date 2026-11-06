"""Bootstrap snapshot used by the app to hydrate its offline store after sign-in."""
from __future__ import annotations

from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.db import get_db
from app.core.security import CurrentUser, get_current_user
from app.models import (ChecklistCompletion, ChecklistItem, FitnessGoal, GymSchedule, Meal, NotificationPreference,
                        NutritionTarget, UserExercise, WeightMeasurement)
from app.schemas.profile import ProfileOut
from app.schemas.tracking import (ChecklistItemIO, GoalIO, MealIO, NotificationPrefIO, NutritionTargetIO,
                                  ScheduleDayIO, WeightIO)
from app.schemas.workout import CustomExerciseOut, SessionOut, SplitOut
from app.services import workouts as w
from app.services.users import get_or_create_profile

router = APIRouter(prefix="/v1", tags=["sync"])


@router.get("/sync/snapshot")
def snapshot(days: int = Query(default=120, ge=7, le=730), user: CurrentUser = Depends(get_current_user),
             db: Session = Depends(get_db)):
    since = date.today() - timedelta(days=days)
    uid = user.id
    split = w.active_split(db, uid)
    prefs = db.scalar(select(NotificationPreference).where(NotificationPreference.user_id == uid))
    target = db.scalar(select(NutritionTarget).where(NutritionTarget.user_id == uid))
    return {
        "profile": ProfileOut.model_validate(get_or_create_profile(db, uid)).model_dump(mode="json"),
        "active_split": SplitOut.model_validate(split).model_dump(mode="json") if split else None,
        "sessions": [SessionOut.model_validate(s).model_dump(mode="json")
                     for s in w.history(db, uid, limit=300, before=None)],
        "user_exercises": [CustomExerciseOut.model_validate(x).model_dump(mode="json") for x in
                           db.scalars(select(UserExercise).where(UserExercise.user_id == uid))],
        "checklist_items": [ChecklistItemIO.model_validate(x).model_dump(mode="json") for x in
                            db.scalars(select(ChecklistItem).where(ChecklistItem.user_id == uid,
                                                                   ChecklistItem.deleted.is_(False)))],
        "checklist_completions": [{"id": str(c.id), "item_id": str(c.item_id), "day": c.day.isoformat(),
                                   "completed_at": c.completed_at.isoformat()} for c in
                                  db.scalars(select(ChecklistCompletion).where(ChecklistCompletion.user_id == uid,
                                                                               ChecklistCompletion.day >= since))],
        "meals": [MealIO.model_validate(m).model_dump(mode="json") for m in
                  db.scalars(select(Meal).where(Meal.user_id == uid,
                                                (Meal.day >= since) | Meal.is_saved_template.is_(True))
                             .options(selectinload(Meal.entries)))],
        "nutrition_targets": NutritionTargetIO.model_validate(target).model_dump(mode="json") if target else None,
        "goals": [GoalIO.model_validate(x).model_dump(mode="json") for x in
                  db.scalars(select(FitnessGoal).where(FitnessGoal.user_id == uid))],
        "weights": [WeightIO.model_validate(x).model_dump(mode="json") for x in
                    db.scalars(select(WeightMeasurement).where(WeightMeasurement.user_id == uid))],
        "schedule": [ScheduleDayIO.model_validate(x).model_dump(mode="json") for x in
                     db.scalars(select(GymSchedule).where(GymSchedule.user_id == uid))],
        "notification_preferences": NotificationPrefIO.model_validate(prefs).model_dump(mode="json") if prefs else None,
    }
