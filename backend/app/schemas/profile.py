from __future__ import annotations

from typing import Literal
from zoneinfo import available_timezones

from pydantic import BaseModel, Field, field_validator

from app.schemas.common import ORMModel

Goal = Literal["build_muscle", "lose_fat", "recomposition", "strength", "endurance", "consistency", "maintain"]
AIScope = Literal["goals", "split", "workouts", "nutrition", "progress", "profile"]
HHMM = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")


class ProfileIn(BaseModel):
    display_name: str = Field(min_length=1, max_length=60)
    age_range: Literal["13-17", "18-24", "25-34", "35-44", "45-54", "55-64", "65+"] | None = None
    height_cm: float | None = Field(default=None, ge=80, le=260)
    current_weight_kg: float | None = Field(default=None, ge=25, le=400)
    target_weight_kg: float | None = Field(default=None, ge=25, le=400)
    experience: Literal["beginner", "intermediate", "advanced"] | None = None
    goals: list[Goal] = Field(default_factory=list, max_length=7)
    training_days: list[int] = Field(default_factory=list, max_length=7)
    preferred_gym_time: str | None = HHMM
    workout_duration_min: int | None = Field(default=None, ge=10, le=300)
    equipment: list[str] = Field(default_factory=list, max_length=20)
    dietary_preferences: list[str] = Field(default_factory=list, max_length=10)
    allergies: str | None = Field(default=None, max_length=300)
    units: Literal["metric", "imperial"] = "metric"
    timezone: str = "UTC"
    weekly_target: int = Field(default=3, ge=1, le=7)
    ai_context_scopes: list[AIScope] = Field(default_factory=list)

    @field_validator("training_days")
    @classmethod
    def _days(cls, v: list[int]) -> list[int]:
        if any(d < 1 or d > 7 for d in v):
            raise ValueError("training_days must be ISO weekdays 1..7")
        return sorted(set(v))

    @field_validator("timezone")
    @classmethod
    def _tz(cls, v: str) -> str:
        if v not in available_timezones():
            raise ValueError("unknown IANA timezone")
        return v


class ProfileOut(ProfileIn, ORMModel):
    display_name: str = ""
    onboarding_completed: bool


class ConsentIn(BaseModel):
    consent_type: Literal["privacy_policy", "terms", "ai_processing", "health_data"]
    version: str = Field(max_length=20)
    granted: bool
