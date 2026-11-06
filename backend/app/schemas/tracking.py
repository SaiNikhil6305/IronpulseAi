from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from app.schemas.common import ORMModel

HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"


# ---- Checklist ---------------------------------------------------------------------
class ChecklistItemIO(ORMModel):
    id: uuid.UUID
    name: str = Field(min_length=1, max_length=60)
    category: Literal["food", "supplement", "habit"]
    quantity: str | None = Field(default=None, max_length=40)
    protein_g: float | None = Field(default=None, ge=0, le=300)
    calories: float | None = Field(default=None, ge=0, le=5000)
    reminder_time: str | None = Field(default=None, pattern=HHMM)
    paused: bool = False
    position: int = 0


class ChecklistToggleIn(BaseModel):
    day: date
    completed: bool
    completion_id: uuid.UUID
    completed_at: datetime | None = None


class ChecklistDayOut(BaseModel):
    day: date
    items: list[ChecklistItemIO]
    completed_item_ids: list[uuid.UUID]


# ---- Nutrition ---------------------------------------------------------------------
class FoodEntryIO(ORMModel):
    id: uuid.UUID
    food_name: str = Field(min_length=1, max_length=120)
    serving_size: str | None = Field(default=None, max_length=40)
    quantity: float = Field(default=1, gt=0, le=100)
    calories: float | None = Field(default=None, ge=0, le=10000)
    protein_g: float | None = Field(default=None, ge=0, le=1000)
    carbs_g: float | None = Field(default=None, ge=0, le=2000)
    fat_g: float | None = Field(default=None, ge=0, le=1000)
    is_estimate: bool = False
    notes: str | None = Field(default=None, max_length=500)


class MealIO(ORMModel):
    id: uuid.UUID
    day: date
    category: str = Field(min_length=1, max_length=30)
    name: str | None = Field(default=None, max_length=80)
    is_saved_template: bool = False
    entries: list[FoodEntryIO] = Field(default_factory=list, max_length=40)


class Totals(BaseModel):
    calories: float = 0
    protein_g: float = 0
    carbs_g: float = 0
    fat_g: float = 0
    meals_logged: int = 0
    entries_with_missing_values: int = 0
    includes_estimates: bool = False


class DailyNutritionOut(BaseModel):
    day: date
    totals: Totals
    meals: list[MealIO]
    targets: NutritionTargetIO | None


class NutritionTargetIO(ORMModel):
    enabled: bool = True
    calories: float | None = Field(default=None, ge=0, le=10000)
    protein_g: float | None = Field(default=None, ge=0, le=600)
    carbs_g: float | None = Field(default=None, ge=0, le=1500)
    fat_g: float | None = Field(default=None, ge=0, le=600)


DailyNutritionOut.model_rebuild()


# ---- Goals / weight / photos -----------------------------------------------------------
class GoalIO(ORMModel):
    id: uuid.UUID
    goal_type: Literal["build_muscle", "lose_fat", "target_weight", "strength", "consistency", "workout_count"]
    title: str = Field(min_length=1, max_length=100)
    start_date: date
    target_date: date
    target_value: float | None = None
    start_value: float | None = None
    milestones: list[dict] = Field(default_factory=list, max_length=20)
    status: Literal["active", "completed", "abandoned"] = "active"
    notes: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def _dates(self):
        if self.target_date <= self.start_date:
            raise ValueError("target_date must be after start_date")
        return self


class GoalProgressOut(GoalIO):
    current_value: float | None
    progress: float | None  # 0..1 when measurable
    days_remaining: int


class WeightIO(ORMModel):
    id: uuid.UUID
    day: date
    weight_kg: float = Field(ge=25, le=400)
    notes: str | None = Field(default=None, max_length=300)


class PhotoIO(ORMModel):
    id: uuid.UUID
    storage_path: str = Field(max_length=300)
    view: Literal["front", "side", "back"]
    taken_on: date
    notes: str | None = Field(default=None, max_length=300)
    hidden: bool = False


# ---- Schedule / notifications -------------------------------------------------------
class ScheduleDayIO(ORMModel):
    weekday: int = Field(ge=1, le=7)
    is_rest_day: bool = False
    time_local: str | None = Field(default=None, pattern=HHMM)
    workout_day_name: str | None = Field(default=None, max_length=60)


class ScheduleIn(BaseModel):
    items: list[ScheduleDayIO] = Field(max_length=7)


class NotificationPrefIO(ORMModel):
    gym_reminders_enabled: bool = True
    reminder_offsets_min: list[Literal[0, 10, 20, 30]] = Field(default_factory=lambda: [20])
    checklist_reminders_enabled: bool = False
    weigh_in_weekday: int | None = Field(default=None, ge=1, le=7)
    weigh_in_time: str | None = Field(default=None, pattern=HHMM)


class PushTokenIn(BaseModel):
    platform: Literal["android", "ios"]
    token: str = Field(min_length=10, max_length=500)


# ---- Wearables --------------------------------------------------------------------
class HealthRecordIn(BaseModel):
    record_uid: str = Field(max_length=120)
    data_type: Literal["steps", "heart_rate", "active_minutes", "sleep", "workout", "calories"]
    value: float = Field(ge=0, le=1_000_000)
    unit: str = Field(max_length=20)
    start_at: datetime
    end_at: datetime


class HealthSyncIn(BaseModel):
    provider: Literal["health_connect", "apple_health"]
    granted_types: list[str] = Field(default_factory=list, max_length=10)
    records: list[HealthRecordIn] = Field(default_factory=list, max_length=2000)


# ---- AI --------------------------------------------------------------------------
class AIMessageIn(BaseModel):
    conversation_id: uuid.UUID | None = None
    message: str = Field(min_length=1, max_length=4000)
    context_scopes: list[Literal["goals", "split", "workouts", "nutrition", "progress", "profile"]] = Field(
        default_factory=list)


class AIMessageOut(BaseModel):
    conversation_id: uuid.UUID
    reply: str
    remaining_today: int


class AIConversationOut(ORMModel):
    id: uuid.UUID
    title: str
    created_at: datetime
    updated_at: datetime


class AIChatMessageOut(ORMModel):
    id: uuid.UUID
    role: str
    content: str
    created_at: datetime
