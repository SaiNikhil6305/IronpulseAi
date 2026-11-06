from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (JSON, Boolean, DateTime, Float, ForeignKey, Index, Integer, String, Text,
                        UniqueConstraint, Uuid)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base
from app.models.base import OwnedMixin, TimestampMixin, uuid_pk


class ExerciseLibrary(TimestampMixin, Base):
    """Shared, read-only exercise catalogue seeded from app/data/exercises.json."""

    __tablename__ = "exercise_library"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # stable slug, e.g. "barbell-bench-press"
    name: Mapped[str] = mapped_column(String(120))
    primary_muscle: Mapped[str] = mapped_column(String(40), index=True)
    secondary_muscles: Mapped[list] = mapped_column(JSON, default=list)
    equipment: Mapped[str] = mapped_column(String(40))
    difficulty: Mapped[str] = mapped_column(String(20))
    instructions: Mapped[list] = mapped_column(JSON, default=list)
    safety: Mapped[list] = mapped_column(JSON, default=list)
    alternatives: Mapped[list] = mapped_column(JSON, default=list)
    unilateral: Mapped[bool] = mapped_column(Boolean, default=False)
    tracking: Mapped[str] = mapped_column(String(20), default="weight_reps")  # weight_reps|reps|duration|distance
    media_url: Mapped[str | None] = mapped_column(String(500))  # only licensed media
    media_license: Mapped[str | None] = mapped_column(String(200))


class UserExercise(TimestampMixin, OwnedMixin, Base):
    """User-created custom exercises and favourites of library exercises."""

    __tablename__ = "user_exercises"
    id: Mapped[uuid.UUID] = uuid_pk()
    library_exercise_id: Mapped[str | None] = mapped_column(String(64))  # set for favourites
    name: Mapped[str | None] = mapped_column(String(120))
    primary_muscle: Mapped[str | None] = mapped_column(String(40))
    equipment: Mapped[str | None] = mapped_column(String(40))
    tracking: Mapped[str] = mapped_column(String(20), default="weight_reps")
    unilateral: Mapped[bool] = mapped_column(Boolean, default=False)
    is_favorite: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[str | None] = mapped_column(Text)


class WorkoutSplit(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "workout_splits"
    id: Mapped[uuid.UUID] = uuid_pk()
    name: Mapped[str] = mapped_column(String(60))
    split_type: Mapped[str] = mapped_column(String(20))  # ppl|bro|upper_lower|full_body|custom
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    days: Mapped[list[WorkoutDay]] = relationship(
        back_populates="split", cascade="all, delete-orphan", order_by="WorkoutDay.position"
    )


class WorkoutDay(TimestampMixin, Base):
    __tablename__ = "workout_days"
    id: Mapped[uuid.UUID] = uuid_pk()
    split_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("workout_splits.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(60))
    position: Mapped[int] = mapped_column(Integer)
    muscle_groups: Mapped[list] = mapped_column(JSON, default=list)
    weekdays: Mapped[list] = mapped_column(JSON, default=list)  # ISO weekdays assigned to this day
    split: Mapped[WorkoutSplit] = relationship(back_populates="days")
    template_exercises: Mapped[list[WorkoutTemplate]] = relationship(
        back_populates="day", cascade="all, delete-orphan", order_by="WorkoutTemplate.position"
    )


class WorkoutTemplate(Base):
    """An exercise slot within a workout day template."""

    __tablename__ = "workout_templates"
    id: Mapped[uuid.UUID] = uuid_pk()
    day_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("workout_days.id", ondelete="CASCADE"), index=True)
    exercise_ref: Mapped[str] = mapped_column(String(64))  # library slug or "custom:<uuid>"
    position: Mapped[int] = mapped_column(Integer)
    target_sets: Mapped[int] = mapped_column(Integer, default=3)
    target_reps: Mapped[str | None] = mapped_column(String(20))
    day: Mapped[WorkoutDay] = relationship(back_populates="template_exercises")


class WorkoutSession(TimestampMixin, OwnedMixin, Base):
    """Primary key is generated on the device so offline sync is idempotent."""

    __tablename__ = "workout_sessions"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    workout_day_name: Mapped[str | None] = mapped_column(String(60))
    status: Mapped[str] = mapped_column(String(20), default="in_progress")  # in_progress|completed|discarded
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    extra_muscle_groups: Mapped[list] = mapped_column(JSON, default=list)
    notes: Mapped[str | None] = mapped_column(Text)
    client_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    exercises: Mapped[list[WorkoutExercise]] = relationship(
        back_populates="session", cascade="all, delete-orphan", order_by="WorkoutExercise.position"
    )
    __table_args__ = (Index("ix_sessions_user_started", "user_id", "started_at"),)


class WorkoutExercise(Base):
    __tablename__ = "workout_exercises"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    session_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("workout_sessions.id", ondelete="CASCADE"), index=True)
    exercise_ref: Mapped[str] = mapped_column(String(64), index=True)
    exercise_name: Mapped[str] = mapped_column(String(120))
    position: Mapped[int] = mapped_column(Integer)
    notes: Mapped[str | None] = mapped_column(Text)
    session: Mapped[WorkoutSession] = relationship(back_populates="exercises")
    sets: Mapped[list[WorkoutSet]] = relationship(
        back_populates="exercise", cascade="all, delete-orphan", order_by="WorkoutSet.position"
    )


class WorkoutSet(Base):
    __tablename__ = "workout_sets"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    workout_exercise_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("workout_exercises.id", ondelete="CASCADE"), index=True)
    position: Mapped[int] = mapped_column(Integer)
    side: Mapped[str | None] = mapped_column(String(5))  # left|right|None
    weight_kg: Mapped[float | None] = mapped_column(Float)
    reps: Mapped[int | None] = mapped_column(Integer)
    rpe: Mapped[float | None] = mapped_column(Float)
    duration_s: Mapped[int | None] = mapped_column(Integer)
    distance_m: Mapped[float | None] = mapped_column(Float)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    exercise: Mapped[WorkoutExercise] = relationship(back_populates="sets")


class XPTransaction(OwnedMixin, Base):
    """Append/delete ledger. (user_id, event_key) is unique, so a qualifying
    event can never be rewarded twice regardless of retries or re-syncs."""

    __tablename__ = "xp_transactions"
    id: Mapped[uuid.UUID] = uuid_pk()
    event_key: Mapped[str] = mapped_column(String(120))
    source: Mapped[str] = mapped_column(String(40))  # set|workout|checklist|weigh_in|weekly_target
    source_id: Mapped[str | None] = mapped_column(String(64), index=True)
    amount: Mapped[int] = mapped_column(Integer)
    description: Mapped[str] = mapped_column(String(160))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("user_id", "event_key", name="uq_xp_user_event"),)


class Achievement(Base):
    __tablename__ = "achievements"
    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    title: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(String(200))


class UserAchievement(OwnedMixin, Base):
    __tablename__ = "user_achievements"
    id: Mapped[uuid.UUID] = uuid_pk()
    achievement_id: Mapped[str] = mapped_column(String(40), ForeignKey("achievements.id"))
    unlocked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("user_id", "achievement_id", name="uq_user_achievement"),)
