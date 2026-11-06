from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from app.schemas.common import ORMModel

SplitType = Literal["ppl", "bro", "upper_lower", "full_body", "custom"]


class ExerciseOut(ORMModel):
    id: str
    name: str
    primary_muscle: str
    secondary_muscles: list[str]
    equipment: str
    difficulty: str
    instructions: list[str]
    safety: list[str]
    alternatives: list[str]
    unilateral: bool
    tracking: str
    media_url: str | None = None
    media_license: str | None = None


class CustomExerciseIn(BaseModel):
    id: uuid.UUID | None = None
    library_exercise_id: str | None = Field(default=None, max_length=64)
    name: str | None = Field(default=None, max_length=120)
    primary_muscle: str | None = Field(default=None, max_length=40)
    equipment: str | None = Field(default=None, max_length=40)
    tracking: Literal["weight_reps", "reps", "duration", "distance"] = "weight_reps"
    unilateral: bool = False
    is_favorite: bool = False
    notes: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _either(self):
        if not self.library_exercise_id and not self.name:
            raise ValueError("Provide library_exercise_id (favourite) or name (custom exercise).")
        return self


class CustomExerciseOut(CustomExerciseIn, ORMModel):
    id: uuid.UUID


class TemplateExerciseIO(ORMModel):
    exercise_ref: str = Field(max_length=64)
    target_sets: int = Field(default=3, ge=1, le=12)
    target_reps: str | None = Field(default=None, max_length=20)


class WorkoutDayIO(ORMModel):
    name: str = Field(min_length=1, max_length=60)
    muscle_groups: list[str] = Field(default_factory=list, max_length=15)
    weekdays: list[int] = Field(default_factory=list, max_length=7)
    template_exercises: list[TemplateExerciseIO] = Field(default_factory=list, max_length=20)


class SplitIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    split_type: SplitType
    days: list[WorkoutDayIO] = Field(min_length=1, max_length=7)


class SplitOut(ORMModel):
    id: uuid.UUID
    name: str
    split_type: str
    is_active: bool
    days: list[WorkoutDayIO]


# ---- Sessions (sync payload) -------------------------------------------------------
class SetIO(ORMModel):
    id: uuid.UUID
    position: int = Field(ge=0, le=100)
    side: Literal["left", "right"] | None = None
    weight_kg: float | None = Field(default=None, ge=0, le=1000)
    reps: int | None = Field(default=None, ge=0, le=1000)
    rpe: float | None = Field(default=None, ge=1, le=10)
    duration_s: int | None = Field(default=None, ge=0, le=86400)
    distance_m: float | None = Field(default=None, ge=0, le=100000)
    completed: bool = False
    completed_at: datetime | None = None


class SessionExerciseIO(ORMModel):
    id: uuid.UUID
    exercise_ref: str = Field(max_length=64)
    exercise_name: str = Field(max_length=120)
    position: int = Field(ge=0, le=50)
    notes: str | None = Field(default=None, max_length=1000)
    sets: list[SetIO] = Field(default_factory=list, max_length=40)


class SessionIn(BaseModel):
    """Full snapshot of a session as known by the device (idempotent PUT)."""

    name: str = Field(min_length=1, max_length=80)
    workout_day_name: str | None = Field(default=None, max_length=60)
    status: Literal["in_progress", "completed", "discarded"]
    started_at: datetime
    ended_at: datetime | None = None
    extra_muscle_groups: list[str] = Field(default_factory=list, max_length=10)
    notes: str | None = Field(default=None, max_length=2000)
    client_updated_at: datetime
    exercises: list[SessionExerciseIO] = Field(default_factory=list, max_length=30)

    @model_validator(mode="after")
    def _check(self):
        if self.status == "completed" and self.ended_at is None:
            raise ValueError("completed sessions require ended_at")
        if self.ended_at and self.ended_at < self.started_at:
            raise ValueError("ended_at must be after started_at")
        return self


class SessionOut(SessionIn, ORMModel):
    id: uuid.UUID


class SessionSyncResult(BaseModel):
    id: uuid.UUID
    applied: bool  # False when the server already had a newer version (last-write-wins)
    server_updated_at: datetime
    xp_from_session: int
    new_achievements: list[str]
    personal_records: list[dict]


class PreviousPerformance(BaseModel):
    exercise_ref: str
    session_id: uuid.UUID | None
    date: datetime | None
    sets: list[SetIO]
