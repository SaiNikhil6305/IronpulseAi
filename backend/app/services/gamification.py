"""Trusted XP, level, streak, personal-record and achievement logic.

Design: XP is *derived* from the user's current qualifying records. Every
reward has a deterministic ``event_key`` and (user_id, event_key) is unique,
so retries, repeated syncs, edits and toggles can never duplicate rewards.
When a qualifying record disappears (set deleted, workout discarded, checklist
item un-ticked) the matching transaction is removed, so XP cannot be farmed by
toggling.

The Flutter client mirrors these rules for offline display; the server ledger
is authoritative once data is synced.
"""
from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import delete, select
from sqlalchemy.orm import Session, selectinload

from app.models import (Achievement, UserAchievement, UserProfile, WeightMeasurement, WorkoutExercise,
                        WorkoutSession, WorkoutSet, XPTransaction)
from app.models.base import utcnow

# ---- Configurable rules -------------------------------------------------------
XP_SET = 10
XP_WORKOUT = 25
XP_CHECKLIST = 5
XP_WEIGH_IN = 15
XP_WEEKLY_TARGET = 30
MAX_XP_SETS_PER_SESSION = 50
MAX_WORKOUT_BONUSES_PER_DAY = 2

LEVELS: list[tuple[int, str]] = [
    (0, "Rookie"),
    (250, "Gym Beginner"),
    (750, "Consistent Lifter"),
    (1750, "Iron Mind"),
    (3500, "Gym Beast"),
    (6500, "Elite Grinder"),
]

ACHIEVEMENTS: dict[str, tuple[str, str]] = {
    "first_workout": ("First Workout", "Complete your first workout."),
    "sets_100": ("First 100 Sets", "Complete 100 valid sets."),
    "three_sessions": ("Three-Session Streak", "Complete three workouts within seven days."),
    "weekly_consistency": ("Seven-Day Consistency Challenge", "Hit your weekly training target in a calendar week."),
    "first_pr": ("First Personal Record", "Beat your previous best on any exercise."),
    "first_month": ("First Month of Training", "Train for 30 days with at least 8 completed workouts."),
}


def tz_for(profile: UserProfile | None) -> ZoneInfo:
    try:
        return ZoneInfo(profile.timezone if profile and profile.timezone else "UTC")
    except ZoneInfoNotFoundError:
        return ZoneInfo("UTC")


def local_date(dt: datetime, tz: ZoneInfo) -> date:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(tz).date()


def week_key(d: date) -> str:
    y, w, _ = d.isocalendar()
    return f"{y}-W{w:02d}"


def is_valid_set(s: WorkoutSet) -> bool:
    """A set earns XP only if it is completed and physically plausible."""
    if not s.completed:
        return False
    if s.weight_kg is not None and not (0 <= s.weight_kg <= 500):
        return False
    reps_ok = s.reps is not None and 1 <= s.reps <= 100
    dur_ok = s.duration_s is not None and 1 <= s.duration_s <= 7200
    dist_ok = s.distance_m is not None and 1 <= s.distance_m <= 10000
    if s.reps is not None and not reps_ok:
        return False
    return reps_ok or dur_ok or dist_ok


def level_for(total_xp: int) -> dict:
    idx = 0
    for i, (threshold, _) in enumerate(LEVELS):
        if total_xp >= threshold:
            idx = i
    current_threshold, name = LEVELS[idx]
    nxt = LEVELS[idx + 1] if idx + 1 < len(LEVELS) else None
    return {
        "level": idx + 1,
        "name": name,
        "total_xp": total_xp,
        "level_floor_xp": current_threshold,
        "next_level_xp": nxt[0] if nxt else None,
        "next_level_name": nxt[1] if nxt else None,
        "progress": 1.0 if not nxt else (total_xp - current_threshold) / (nxt[0] - current_threshold),
    }


def epley_1rm(weight: float, reps: int) -> float:
    return weight * (1 + reps / 30.0)


# ---- Ledger primitives -----------------------------------------------------------
@dataclass
class DesiredXP:
    event_key: str
    source: str
    amount: int
    description: str
    created_at: datetime


def reconcile(db: Session, user_id: uuid.UUID, source_id: str, desired: list[DesiredXP]) -> None:
    """Make the ledger rows tagged with ``source_id`` exactly match ``desired``."""
    existing = {t.event_key: t for t in db.scalars(
        select(XPTransaction).where(XPTransaction.user_id == user_id, XPTransaction.source_id == source_id))}
    want = {d.event_key: d for d in desired}
    for key, tx in existing.items():
        if key not in want:
            db.delete(tx)
    for key, d in want.items():
        if key in existing:
            continue
        # The key may exist under a different source id (defensive); never duplicate.
        clash = db.scalar(select(XPTransaction.id).where(
            XPTransaction.user_id == user_id, XPTransaction.event_key == key))
        if clash:
            continue
        db.add(XPTransaction(user_id=user_id, event_key=key, source=d.source, source_id=source_id,
                             amount=d.amount, description=d.description, created_at=d.created_at))
    db.flush()


def _completed_sessions(db: Session, user_id: uuid.UUID) -> list[WorkoutSession]:
    return list(db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id, WorkoutSession.status == "completed")
        .options(selectinload(WorkoutSession.exercises).selectinload(WorkoutExercise.sets))
        .order_by(WorkoutSession.started_at)))


def session_valid_sets(session: WorkoutSession) -> list[WorkoutSet]:
    return [s for ex in session.exercises for s in ex.sets if is_valid_set(s)]


def award_for_session(db: Session, user_id: uuid.UUID, session: WorkoutSession) -> None:
    profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
    tz = tz_for(profile)
    desired: list[DesiredXP] = []
    if session.status == "completed":
        when = session.ended_at or session.started_at
        valid = session_valid_sets(session)
        for s in valid[:MAX_XP_SETS_PER_SESSION]:
            desired.append(DesiredXP(f"set:{s.id}", "set", XP_SET, f"Completed set – {s.exercise.exercise_name}", when))
        if valid:
            day = local_date(session.started_at, tz)
            other_bonuses = 0
            for other in _completed_sessions(db, user_id):
                if other.id == session.id or local_date(other.started_at, tz) != day:
                    continue
                if db.scalar(select(XPTransaction.id).where(
                        XPTransaction.user_id == user_id, XPTransaction.event_key == f"workout:{other.id}")):
                    other_bonuses += 1
            if other_bonuses < MAX_WORKOUT_BONUSES_PER_DAY:
                desired.append(DesiredXP(f"workout:{session.id}", "workout", XP_WORKOUT,
                                         f"Completed workout – {session.name}", when))
    reconcile(db, user_id, str(session.id), desired)
    refresh_weekly_targets(db, user_id)


def qualifying_workout_dates(db: Session, user_id: uuid.UUID, tz: ZoneInfo) -> list[date]:
    return [local_date(s.started_at, tz) for s in _completed_sessions(db, user_id) if session_valid_sets(s)]


def refresh_weekly_targets(db: Session, user_id: uuid.UUID) -> None:
    profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
    tz = tz_for(profile)
    target = max(1, profile.weekly_target if profile else 3)
    per_week: dict[str, int] = defaultdict(int)
    for d in qualifying_workout_dates(db, user_id, tz):
        per_week[week_key(d)] += 1
    desired = [
        DesiredXP(f"weekly_target:{wk}", "weekly_target", XP_WEEKLY_TARGET, f"Weekly training target reached ({wk})",
                  utcnow())
        for wk, n in per_week.items() if n >= target
    ]
    reconcile(db, user_id, "weekly_target", desired)


def award_for_weigh_ins(db: Session, user_id: uuid.UUID) -> None:
    """15 XP for the first weigh-in of each ISO week."""
    rows = db.scalars(select(WeightMeasurement).where(WeightMeasurement.user_id == user_id)
                      .order_by(WeightMeasurement.day, WeightMeasurement.created_at))
    seen: dict[str, WeightMeasurement] = {}
    for m in rows:
        seen.setdefault(week_key(m.day), m)
    desired = [DesiredXP(f"weigh_in:{wk}", "weigh_in", XP_WEIGH_IN, f"Weekly weigh-in ({wk})",
                         datetime.combine(m.day, datetime.min.time(), tzinfo=timezone.utc))
               for wk, m in seen.items()]
    reconcile(db, user_id, "weigh_in", desired)


def set_checklist_xp(db: Session, user_id: uuid.UUID, item_id: uuid.UUID, day: date, completed: bool,
                     item_name: str) -> None:
    key = f"checklist:{item_id}:{day.isoformat()}"
    source_id = f"checklist:{item_id}:{day.isoformat()}"
    desired = [DesiredXP(key, "checklist", XP_CHECKLIST, f"Checklist – {item_name}", utcnow())] if completed else []
    reconcile(db, user_id, source_id, desired)


# ---- Read models ---------------------------------------------------------------------
def total_xp(db: Session, user_id: uuid.UUID) -> int:
    return sum(t.amount for t in db.scalars(select(XPTransaction).where(XPTransaction.user_id == user_id)))


def compute_streaks(workout_dates: list[date], weekly_target: int, today: date) -> dict:
    """Consistency streak measured in weeks that met the weekly target.

    Training every day is never required; rest days never break a streak. The
    current week counts once its target is met, and an unfinished current week
    never breaks the streak.
    """
    target = max(1, weekly_target)
    per_week: dict[str, int] = defaultdict(int)
    for d in workout_dates:
        per_week[week_key(d)] += 1
    met = {wk for wk, n in per_week.items() if n >= target}

    def prev_week(d: date) -> date:
        return d - timedelta(days=7)

    cursor = today
    current = 0
    if week_key(cursor) in met:
        current += 1
    cursor = prev_week(cursor)
    while week_key(cursor) in met:
        current += 1
        cursor = prev_week(cursor)

    longest = 0
    if workout_dates:
        start = min(workout_dates)
        cursor = start - timedelta(days=start.weekday())
        run = 0
        while cursor <= today:
            if week_key(cursor) in met:
                run += 1
                longest = max(longest, run)
            else:
                run = 0
            cursor += timedelta(days=7)

    this_week = per_week.get(week_key(today), 0)
    return {
        "current_streak_weeks": current,
        "longest_streak_weeks": longest,
        "total_workouts": len(workout_dates),
        "weekly_target": target,
        "this_week_workouts": this_week,
        "explanation": (f"Your streak counts consecutive weeks (Mon–Sun) in which you completed at least {target} "
                        "workout(s). Rest days never break it, and the current week only counts once you hit "
                        "your target."),
    }


def personal_records(db: Session, user_id: uuid.UUID) -> list[dict]:
    """Chronological PR events: a set whose estimated 1RM beats all earlier sessions."""
    best: dict[str, float] = {}
    events: list[dict] = []
    for session in _completed_sessions(db, user_id):
        session_best: dict[str, tuple[float, WorkoutSet, WorkoutExercise]] = {}
        for ex in session.exercises:
            for s in ex.sets:
                if not is_valid_set(s) or not s.weight_kg or not s.reps or s.reps > 12:
                    continue
                e = epley_1rm(s.weight_kg, s.reps)
                if ex.exercise_ref not in session_best or e > session_best[ex.exercise_ref][0]:
                    session_best[ex.exercise_ref] = (e, s, ex)
        for ref, (e, s, ex) in session_best.items():
            if ref in best and e > best[ref] + 1e-6:
                events.append({"exercise_ref": ref, "exercise_name": ex.exercise_name, "session_id": str(session.id),
                               "weight_kg": s.weight_kg, "reps": s.reps, "estimated_1rm_kg": round(e, 1),
                               "previous_best_1rm_kg": round(best[ref], 1), "date": session.started_at.isoformat()})
            best[ref] = max(best.get(ref, 0.0), e)
    return events


def evaluate_achievements(db: Session, user_id: uuid.UUID) -> list[str]:
    """Unlock any newly earned achievements. Returns ids unlocked now."""
    profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
    tz = tz_for(profile)
    sessions = [s for s in _completed_sessions(db, user_id) if session_valid_sets(s)]
    dates = sorted(local_date(s.started_at, tz) for s in sessions)
    total_sets = sum(len(session_valid_sets(s)) for s in sessions)
    target = profile.weekly_target if profile else 3

    earned: set[str] = set()
    if sessions:
        earned.add("first_workout")
    if total_sets >= 100:
        earned.add("sets_100")
    for i in range(len(dates) - 2):
        if (dates[i + 2] - dates[i]).days < 7:
            earned.add("three_sessions")
            break
    per_week: dict[str, int] = defaultdict(int)
    for d in dates:
        per_week[week_key(d)] += 1
    if any(n >= max(1, target) for n in per_week.values()):
        earned.add("weekly_consistency")
    if personal_records(db, user_id):
        earned.add("first_pr")
    if dates and (dates[-1] - dates[0]).days >= 30 and len(dates) >= 8:
        earned.add("first_month")

    have = set(db.scalars(select(UserAchievement.achievement_id).where(UserAchievement.user_id == user_id)))
    new = sorted(earned - have)
    for aid in new:
        db.add(UserAchievement(user_id=user_id, achievement_id=aid, unlocked_at=utcnow()))
    db.flush()
    return new


def seed_achievements(db: Session) -> None:
    for aid, (title, desc) in ACHIEVEMENTS.items():
        row = db.get(Achievement, aid)
        if row is None:
            db.add(Achievement(id=aid, title=title, description=desc))
        else:
            row.title, row.description = title, desc
    db.commit()


def delete_session_xp(db: Session, user_id: uuid.UUID, session_id: uuid.UUID) -> None:
    db.execute(delete(XPTransaction).where(XPTransaction.user_id == user_id,
                                           XPTransaction.source_id == str(session_id)))
    db.flush()
