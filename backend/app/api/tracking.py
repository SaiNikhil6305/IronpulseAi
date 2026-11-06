"""Gamification, checklist, nutrition, goals, weight, photos, schedules and wearables.

Every write is an idempotent PUT/DELETE keyed by a client-generated id, so the
mobile offline queue can replay operations safely.
"""
from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, timedelta, timezone

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from app.core.db import get_db
from app.core.errors import AppError
from app.core.security import CurrentUser, get_current_user
from app.models import (Achievement, ChecklistCompletion, ChecklistItem, FitnessGoal, FoodEntry, GymSchedule, Meal,
                        NotificationEvent, NotificationPreference, NutritionTarget, ProgressPhoto, SyncedHealthRecord,
                        UserAchievement, WearableConnection, WeightMeasurement, XPTransaction)
from app.models.base import utcnow
from app.schemas.tracking import (ChecklistDayOut, ChecklistItemIO, ChecklistToggleIn, DailyNutritionOut,
                                  FoodEntryIO, GoalIO, GoalProgressOut, HealthSyncIn, MealIO, NotificationPrefIO,
                                  NutritionTargetIO, PhotoIO, PushTokenIn, ScheduleDayIO, ScheduleIn, Totals,
                                  WeightIO)
from app.services import gamification as g
from app.services.users import get_or_create_profile

router = APIRouter(prefix="/v1", tags=["tracking"])


def _utc(dt):
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


def _owned_or_404(obj, user_id: uuid.UUID, what: str):
    if obj is not None and obj.user_id != user_id:
        raise AppError(404, "not_found", f"{what} not found.")
    return obj


# ---- Gamification ------------------------------------------------------------
@router.get("/gamification/summary")
def gamification_summary(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    profile = get_or_create_profile(db, user.id)
    tz = g.tz_for(profile)
    today = g.local_date(utcnow(), tz)
    xp = g.total_xp(db, user.id)
    streaks = g.compute_streaks(g.qualifying_workout_dates(db, user.id, tz), profile.weekly_target, today)
    unlocked = {ua.achievement_id: ua.unlocked_at for ua in
                db.scalars(select(UserAchievement).where(UserAchievement.user_id == user.id))}
    achievements = [{"id": a.id, "title": a.title, "description": a.description,
                     "unlocked_at": unlocked.get(a.id).isoformat() if a.id in unlocked else None}
                    for a in db.scalars(select(Achievement).order_by(Achievement.id))]
    return {"level": g.level_for(xp), "streaks": streaks, "achievements": achievements,
            "personal_records": g.personal_records(db, user.id)[-20:],
            "rules": {"set": g.XP_SET, "workout": g.XP_WORKOUT, "checklist": g.XP_CHECKLIST,
                      "weigh_in": g.XP_WEIGH_IN, "weekly_target": g.XP_WEEKLY_TARGET}}


@router.get("/gamification/xp-history")
def xp_history(limit: int = Query(default=50, ge=1, le=200), user: CurrentUser = Depends(get_current_user),
               db: Session = Depends(get_db)):
    rows = db.scalars(select(XPTransaction).where(XPTransaction.user_id == user.id)
                      .order_by(XPTransaction.created_at.desc()).limit(limit))
    return [{"id": str(t.id), "source": t.source, "amount": t.amount, "description": t.description,
             "created_at": t.created_at.isoformat()} for t in rows]


# ---- Checklist --------------------------------------------------------------
@router.put("/checklist/items/{item_id}", response_model=ChecklistItemIO)
def put_checklist_item(item_id: uuid.UUID, body: ChecklistItemIO, user: CurrentUser = Depends(get_current_user),
                       db: Session = Depends(get_db)):
    if body.id != item_id:
        raise AppError(422, "id_mismatch", "Body id must match the URL.")
    row = _owned_or_404(db.get(ChecklistItem, item_id), user.id, "Item")
    if row is None:
        row = ChecklistItem(id=item_id, user_id=user.id)
        db.add(row)
    for k, v in body.model_dump(exclude={"id"}).items():
        setattr(row, k, v)
    row.deleted = False
    db.commit()
    return row


@router.delete("/checklist/items/{item_id}", status_code=204)
def delete_checklist_item(item_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
                          db: Session = Depends(get_db)):
    row = db.get(ChecklistItem, item_id)
    if row is not None and row.user_id == user.id:
        row.deleted = True  # soft delete keeps completion history and earned XP intact
        db.commit()
    return Response(status_code=204)


@router.put("/checklist/items/{item_id}/completion", response_model=ChecklistDayOut)
def toggle_completion(item_id: uuid.UUID, body: ChecklistToggleIn, user: CurrentUser = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    item = db.get(ChecklistItem, item_id)
    if item is None or item.user_id != user.id:
        raise AppError(404, "not_found", "Item not found.")
    if body.day > date.today() + timedelta(days=1):
        raise AppError(422, "future_day", "Cannot complete items for future days.")
    existing = db.scalar(select(ChecklistCompletion).where(ChecklistCompletion.item_id == item_id,
                                                           ChecklistCompletion.day == body.day))
    if body.completed and existing is None:
        db.add(ChecklistCompletion(id=body.completion_id, user_id=user.id, item_id=item_id, day=body.day,
                                   completed_at=body.completed_at or utcnow()))
    elif not body.completed and existing is not None:
        db.delete(existing)
    db.flush()
    g.set_checklist_xp(db, user.id, item_id, body.day, body.completed, item.name)
    db.commit()
    return checklist_day(body.day, user, db)


@router.get("/checklist", response_model=ChecklistDayOut)
def checklist_day(day: date, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    items = list(db.scalars(select(ChecklistItem).where(ChecklistItem.user_id == user.id,
                                                        ChecklistItem.deleted.is_(False))
                            .order_by(ChecklistItem.position)))
    done = list(db.scalars(select(ChecklistCompletion.item_id).where(ChecklistCompletion.user_id == user.id,
                                                                     ChecklistCompletion.day == day)))
    return ChecklistDayOut(day=day, items=items, completed_item_ids=done)


@router.get("/checklist/history")
def checklist_history(days: int = Query(default=30, ge=1, le=365), user: CurrentUser = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    since = date.today() - timedelta(days=days)
    rows = db.scalars(select(ChecklistCompletion).where(ChecklistCompletion.user_id == user.id,
                                                        ChecklistCompletion.day >= since))
    out: dict[str, list[str]] = defaultdict(list)
    for r in rows:
        out[r.day.isoformat()].append(str(r.item_id))
    return out


# ---- Nutrition ---------------------------------------------------------------
def _totals(meals: list[Meal]) -> Totals:
    t = Totals()
    for m in meals:
        if m.entries:
            t.meals_logged += 1
        for e in m.entries:
            if e.calories is None or e.protein_g is None:
                t.entries_with_missing_values += 1
            t.calories += (e.calories or 0) * e.quantity
            t.protein_g += (e.protein_g or 0) * e.quantity
            t.carbs_g += (e.carbs_g or 0) * e.quantity
            t.fat_g += (e.fat_g or 0) * e.quantity
            t.includes_estimates |= e.is_estimate
    for f in ("calories", "protein_g", "carbs_g", "fat_g"):
        setattr(t, f, round(getattr(t, f), 1))
    return t


@router.put("/meals/{meal_id}", response_model=MealIO)
def put_meal(meal_id: uuid.UUID, body: MealIO, user: CurrentUser = Depends(get_current_user),
             db: Session = Depends(get_db)):
    if body.id != meal_id:
        raise AppError(422, "id_mismatch", "Body id must match the URL.")
    meal = _owned_or_404(db.get(Meal, meal_id), user.id, "Meal")
    if meal is None:
        meal = Meal(id=meal_id, user_id=user.id)
        db.add(meal)
    meal.day, meal.category, meal.name, meal.is_saved_template = body.day, body.category, body.name, body.is_saved_template
    meal.entries.clear()
    db.flush()
    for e in body.entries:
        other = db.get(FoodEntry, e.id)
        if other is not None:
            raise AppError(409, "id_conflict", "Food entry id already in use.")
        meal.entries.append(FoodEntry(**e.model_dump()))
    db.commit()
    db.refresh(meal)
    return meal


@router.delete("/meals/{meal_id}", status_code=204)
def delete_meal(meal_id: uuid.UUID, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    meal = db.get(Meal, meal_id)
    if meal is not None and meal.user_id == user.id:
        db.delete(meal)
        db.commit()
    return Response(status_code=204)


@router.put("/meals/{meal_id}/entries/{entry_id}", response_model=MealIO)
def put_entry(meal_id: uuid.UUID, entry_id: uuid.UUID, body: FoodEntryIO,
              user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    meal = db.get(Meal, meal_id)
    if meal is None or meal.user_id != user.id or body.id != entry_id:
        raise AppError(404, "not_found", "Meal not found.")
    entry = db.get(FoodEntry, entry_id)
    if entry is not None and entry.meal_id != meal_id:
        raise AppError(409, "id_conflict", "Food entry id already in use.")
    if entry is None:
        entry = FoodEntry(id=entry_id, meal_id=meal_id)
        db.add(entry)
    for k, v in body.model_dump(exclude={"id"}).items():
        setattr(entry, k, v)
    db.commit()
    db.refresh(meal)
    return meal


@router.delete("/meals/{meal_id}/entries/{entry_id}", status_code=204)
def delete_entry(meal_id: uuid.UUID, entry_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
                 db: Session = Depends(get_db)):
    meal = db.get(Meal, meal_id)
    entry = db.get(FoodEntry, entry_id)
    if meal is not None and meal.user_id == user.id and entry is not None and entry.meal_id == meal_id:
        db.delete(entry)
        db.commit()
    return Response(status_code=204)


@router.get("/nutrition/day", response_model=DailyNutritionOut)
def nutrition_day(day: date, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    meals = list(db.scalars(select(Meal).where(Meal.user_id == user.id, Meal.day == day,
                                               Meal.is_saved_template.is_(False))
                            .options(selectinload(Meal.entries)).order_by(Meal.created_at)))
    target = db.scalar(select(NutritionTarget).where(NutritionTarget.user_id == user.id))
    return DailyNutritionOut(day=day, totals=_totals(meals), meals=meals, targets=target)


@router.get("/nutrition/history")
def nutrition_history(days: int = Query(default=30, ge=1, le=365), user: CurrentUser = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    since = date.today() - timedelta(days=days)
    meals = list(db.scalars(select(Meal).where(Meal.user_id == user.id, Meal.day >= since,
                                               Meal.is_saved_template.is_(False)).options(selectinload(Meal.entries))))
    by_day: dict[date, list[Meal]] = defaultdict(list)
    for m in meals:
        by_day[m.day].append(m)
    out = [{"day": d.isoformat(), **_totals(ms).model_dump()} for d, ms in sorted(by_day.items())]
    logged = [o for o in out if o["meals_logged"]]
    avg = {k: round(sum(o[k] for o in logged) / len(logged), 1) if logged else None
           for k in ("calories", "protein_g", "carbs_g", "fat_g")}
    return {"days": out, "average_over_logged_days": avg, "logged_days": len(logged)}


@router.get("/meals/saved", response_model=list[MealIO])
def saved_meals(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(Meal).where(Meal.user_id == user.id, Meal.is_saved_template.is_(True))
                           .options(selectinload(Meal.entries))))


@router.put("/nutrition/targets", response_model=NutritionTargetIO)
def put_targets(body: NutritionTargetIO, user: CurrentUser = Depends(get_current_user),
                db: Session = Depends(get_db)):
    row = db.scalar(select(NutritionTarget).where(NutritionTarget.user_id == user.id))
    if row is None:
        row = NutritionTarget(user_id=user.id)
        db.add(row)
    for k, v in body.model_dump().items():
        setattr(row, k, v)
    db.commit()
    return row


# ---- Goals & weight --------------------------------------------------------------
@router.put("/goals/{goal_id}", response_model=GoalIO)
def put_goal(goal_id: uuid.UUID, body: GoalIO, user: CurrentUser = Depends(get_current_user),
             db: Session = Depends(get_db)):
    if body.id != goal_id:
        raise AppError(422, "id_mismatch", "Body id must match the URL.")
    row = _owned_or_404(db.get(FitnessGoal, goal_id), user.id, "Goal")
    if row is None:
        row = FitnessGoal(id=goal_id, user_id=user.id)
        db.add(row)
    for k, v in body.model_dump(exclude={"id"}).items():
        setattr(row, k, v)
    db.commit()
    return row


@router.delete("/goals/{goal_id}", status_code=204)
def delete_goal(goal_id: uuid.UUID, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.get(FitnessGoal, goal_id)
    if row is not None and row.user_id == user.id:
        db.delete(row)
        db.commit()
    return Response(status_code=204)


@router.get("/goals", response_model=list[GoalProgressOut])
def list_goals(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    profile = get_or_create_profile(db, user.id)
    tz = g.tz_for(profile)
    today = g.local_date(utcnow(), tz)
    latest_weight = db.scalar(select(WeightMeasurement.weight_kg).where(WeightMeasurement.user_id == user.id)
                              .order_by(WeightMeasurement.day.desc()).limit(1))
    workout_dates = g.qualifying_workout_dates(db, user.id, tz)
    out = []
    for goal in db.scalars(select(FitnessGoal).where(FitnessGoal.user_id == user.id)
                           .order_by(FitnessGoal.target_date)):
        current, progress = None, None
        if goal.goal_type == "target_weight" and latest_weight is not None and goal.target_value:
            current = latest_weight
            if goal.start_value is not None and goal.start_value != goal.target_value:
                progress = (goal.start_value - current) / (goal.start_value - goal.target_value)
        elif goal.goal_type == "workout_count" and goal.target_value:
            current = float(sum(1 for d in workout_dates if goal.start_date <= d <= goal.target_date))
            progress = current / goal.target_value
        if progress is not None:
            progress = max(0.0, min(1.0, progress))
        out.append(GoalProgressOut.model_validate({**GoalIO.model_validate(goal).model_dump(),
                                                   "current_value": current, "progress": progress,
                                                   "days_remaining": max(0, (goal.target_date - today).days)}))
    return out


@router.put("/weights/{weight_id}", response_model=WeightIO)
def put_weight(weight_id: uuid.UUID, body: WeightIO, user: CurrentUser = Depends(get_current_user),
               db: Session = Depends(get_db)):
    if body.id != weight_id:
        raise AppError(422, "id_mismatch", "Body id must match the URL.")
    row = _owned_or_404(db.get(WeightMeasurement, weight_id), user.id, "Measurement")
    if row is None:
        row = WeightMeasurement(id=weight_id, user_id=user.id)
        db.add(row)
    row.day, row.weight_kg, row.notes = body.day, body.weight_kg, body.notes
    db.flush()
    g.award_for_weigh_ins(db, user.id)
    db.commit()
    return row


@router.delete("/weights/{weight_id}", status_code=204)
def delete_weight(weight_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
                  db: Session = Depends(get_db)):
    row = db.get(WeightMeasurement, weight_id)
    if row is not None and row.user_id == user.id:
        db.delete(row)
        db.flush()
        g.award_for_weigh_ins(db, user.id)
        db.commit()
    return Response(status_code=204)


@router.get("/weights", response_model=list[WeightIO])
def list_weights(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(WeightMeasurement).where(WeightMeasurement.user_id == user.id)
                           .order_by(WeightMeasurement.day)))


# ---- Progress photos (metadata; binaries live in the private Supabase bucket) --------
@router.put("/photos/{photo_id}", response_model=PhotoIO)
def put_photo(photo_id: uuid.UUID, body: PhotoIO, user: CurrentUser = Depends(get_current_user),
              db: Session = Depends(get_db)):
    if body.id != photo_id:
        raise AppError(422, "id_mismatch", "Body id must match the URL.")
    if not body.storage_path.startswith(f"{user.id}/") or ".." in body.storage_path:
        raise AppError(403, "forbidden", "Photos must be stored in your own private folder.")
    row = _owned_or_404(db.get(ProgressPhoto, photo_id), user.id, "Photo")
    if row is None:
        row = ProgressPhoto(id=photo_id, user_id=user.id)
        db.add(row)
    for k, v in body.model_dump(exclude={"id"}).items():
        setattr(row, k, v)
    db.commit()
    return row


@router.get("/photos", response_model=list[PhotoIO])
def list_photos(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(ProgressPhoto).where(ProgressPhoto.user_id == user.id)
                           .order_by(ProgressPhoto.taken_on.desc())))


@router.delete("/photos/{photo_id}", status_code=204)
def delete_photo(photo_id: uuid.UUID, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.get(ProgressPhoto, photo_id)
    if row is not None and row.user_id == user.id:
        db.delete(row)
        db.commit()
    return Response(status_code=204)


# ---- Schedule & notifications --------------------------------------------------
@router.put("/schedule", response_model=list[ScheduleDayIO])
def put_schedule(payload: ScheduleIn, user: CurrentUser = Depends(get_current_user),
                 db: Session = Depends(get_db)):
    body = payload.items
    if len({d.weekday for d in body}) != len(body):
        raise AppError(422, "duplicate_weekday", "Each weekday may appear once.")
    db.execute(delete(GymSchedule).where(GymSchedule.user_id == user.id))
    for d in body:
        db.add(GymSchedule(user_id=user.id, **d.model_dump()))
    db.commit()
    return get_schedule(user, db)


@router.get("/schedule", response_model=list[ScheduleDayIO])
def get_schedule(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(GymSchedule).where(GymSchedule.user_id == user.id).order_by(GymSchedule.weekday)))


@router.put("/notification-preferences", response_model=NotificationPrefIO)
def put_prefs(body: NotificationPrefIO, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.scalar(select(NotificationPreference).where(NotificationPreference.user_id == user.id))
    if row is None:
        row = NotificationPreference(user_id=user.id)
        db.add(row)
    data = body.model_dump()
    data["reminder_offsets_min"] = sorted(set(data["reminder_offsets_min"]), reverse=True)
    for k, v in data.items():
        setattr(row, k, v)
    db.commit()
    return row


@router.get("/notification-preferences", response_model=NotificationPrefIO)
def get_prefs(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.scalar(select(NotificationPreference).where(NotificationPreference.user_id == user.id))
    return row or NotificationPrefIO()


@router.post("/push-tokens", status_code=201)
def register_push_token(body: PushTokenIn, user: CurrentUser = Depends(get_current_user),
                        db: Session = Depends(get_db)):
    """Reserved for server push. The current release uses on-device local notifications only."""
    exists = db.scalar(select(NotificationEvent.id).where(NotificationEvent.user_id == user.id,
                                                          NotificationEvent.kind == "push_token",
                                                          NotificationEvent.value == body.token))
    if not exists:
        db.add(NotificationEvent(user_id=user.id, kind="push_token", platform=body.platform, value=body.token,
                                 created_at=utcnow()))
        db.commit()
    return {"registered": True}


# ---- Wearables -------------------------------------------------------------------
@router.post("/wearables/sync")
def wearable_sync(body: HealthSyncIn, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    conn = db.scalar(select(WearableConnection).where(WearableConnection.user_id == user.id,
                                                      WearableConnection.provider == body.provider))
    if conn is None:
        conn = WearableConnection(user_id=user.id, provider=body.provider, status="connected")
        db.add(conn)
    conn.status = "connected"
    conn.granted_types = body.granted_types
    conn.last_error = None
    inserted = updated = 0
    for r in body.records:
        if r.end_at < r.start_at:
            continue
        existing = db.scalar(select(SyncedHealthRecord).where(
            SyncedHealthRecord.user_id == user.id, SyncedHealthRecord.provider == body.provider,
            SyncedHealthRecord.record_uid == r.record_uid))
        if existing is not None:
            # Daily aggregates (e.g. today's steps) grow during the day: update in place, never duplicate.
            if existing.value != r.value or _utc(existing.end_at) != _utc(r.end_at):
                existing.value, existing.end_at, existing.unit = r.value, r.end_at, r.unit
                updated += 1
            continue
        db.add(SyncedHealthRecord(user_id=user.id, provider=body.provider, **r.model_dump()))
        inserted += 1
    conn.last_synced_at = utcnow()
    db.commit()
    return {"inserted": inserted, "updated": updated, "unchanged": len(body.records) - inserted - updated,
            "last_synced_at": conn.last_synced_at.isoformat()}


@router.get("/wearables")
def list_wearables(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return [{"provider": c.provider, "status": c.status, "granted_types": c.granted_types,
             "last_synced_at": c.last_synced_at.isoformat() if c.last_synced_at else None, "last_error": c.last_error}
            for c in db.scalars(select(WearableConnection).where(WearableConnection.user_id == user.id))]


@router.delete("/wearables/{provider}", status_code=204)
def disconnect_wearable(provider: str, delete_data: bool = False, user: CurrentUser = Depends(get_current_user),
                        db: Session = Depends(get_db)):
    conn = db.scalar(select(WearableConnection).where(WearableConnection.user_id == user.id,
                                                      WearableConnection.provider == provider))
    if conn is not None:
        conn.status = "revoked"
    if delete_data:
        db.execute(delete(SyncedHealthRecord).where(SyncedHealthRecord.user_id == user.id,
                                                    SyncedHealthRecord.provider == provider))
    db.commit()
    return Response(status_code=204)
