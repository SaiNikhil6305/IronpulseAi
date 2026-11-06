from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (JSON, Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text,
                        UniqueConstraint, Uuid)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base
from app.models.base import OwnedMixin, TimestampMixin, uuid_pk


# --- Schedules & notifications ------------------------------------------------
class GymSchedule(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "gym_schedules"
    id: Mapped[uuid.UUID] = uuid_pk()
    weekday: Mapped[int] = mapped_column(Integer)  # ISO 1=Mon..7=Sun
    is_rest_day: Mapped[bool] = mapped_column(Boolean, default=False)
    time_local: Mapped[str | None] = mapped_column(String(5))  # HH:MM in the profile timezone
    workout_day_name: Mapped[str | None] = mapped_column(String(60))
    __table_args__ = (UniqueConstraint("user_id", "weekday", name="uq_schedule_weekday"),)


class NotificationPreference(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "notification_preferences"
    id: Mapped[uuid.UUID] = uuid_pk()
    gym_reminders_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    reminder_offsets_min: Mapped[list] = mapped_column(JSON, default=lambda: [20])  # subset of 30,20,10,0
    checklist_reminders_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    weigh_in_weekday: Mapped[int | None] = mapped_column(Integer)
    weigh_in_time: Mapped[str | None] = mapped_column(String(5))
    __table_args__ = (UniqueConstraint("user_id", name="uq_notification_pref_user"),)


class NotificationEvent(OwnedMixin, Base):
    """Push-token registrations. Unused while reminders are local-only."""

    __tablename__ = "notification_events"
    id: Mapped[uuid.UUID] = uuid_pk()
    kind: Mapped[str] = mapped_column(String(30))  # push_token
    platform: Mapped[str] = mapped_column(String(10))
    value: Mapped[str] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("user_id", "kind", "value", name="uq_notification_event"),)


# --- Checklist ----------------------------------------------------------------
class ChecklistItem(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "checklist_items"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    name: Mapped[str] = mapped_column(String(60))
    category: Mapped[str] = mapped_column(String(20))  # food|supplement|habit
    quantity: Mapped[str | None] = mapped_column(String(40))
    protein_g: Mapped[float | None] = mapped_column(Float)
    calories: Mapped[float | None] = mapped_column(Float)
    reminder_time: Mapped[str | None] = mapped_column(String(5))
    paused: Mapped[bool] = mapped_column(Boolean, default=False)
    position: Mapped[int] = mapped_column(Integer, default=0)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)


class ChecklistCompletion(OwnedMixin, Base):
    __tablename__ = "checklist_completions"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    item_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("checklist_items.id", ondelete="CASCADE"))
    day: Mapped[date] = mapped_column(Date)
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("item_id", "day", name="uq_checklist_item_day"),)


# --- Nutrition ----------------------------------------------------------------
class Meal(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "meals"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    day: Mapped[date] = mapped_column(Date, index=True)
    category: Mapped[str] = mapped_column(String(30))  # morning|afternoon|night|snack|<custom>
    name: Mapped[str | None] = mapped_column(String(80))
    is_saved_template: Mapped[bool] = mapped_column(Boolean, default=False)
    entries: Mapped[list[FoodEntry]] = relationship(back_populates="meal", cascade="all, delete-orphan")


class FoodEntry(TimestampMixin, Base):
    __tablename__ = "food_entries"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    meal_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("meals.id", ondelete="CASCADE"), index=True)
    food_name: Mapped[str] = mapped_column(String(120))
    serving_size: Mapped[str | None] = mapped_column(String(40))
    quantity: Mapped[float] = mapped_column(Float, default=1)
    calories: Mapped[float | None] = mapped_column(Float)
    protein_g: Mapped[float | None] = mapped_column(Float)
    carbs_g: Mapped[float | None] = mapped_column(Float)
    fat_g: Mapped[float | None] = mapped_column(Float)
    is_estimate: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[str | None] = mapped_column(Text)
    meal: Mapped[Meal] = relationship(back_populates="entries")


class NutritionTarget(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "nutrition_targets"
    id: Mapped[uuid.UUID] = uuid_pk()
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    calories: Mapped[float | None] = mapped_column(Float)
    protein_g: Mapped[float | None] = mapped_column(Float)
    carbs_g: Mapped[float | None] = mapped_column(Float)
    fat_g: Mapped[float | None] = mapped_column(Float)
    __table_args__ = (UniqueConstraint("user_id", name="uq_nutrition_target_user"),)


# --- Goals, weight, photos ----------------------------------------------------
class FitnessGoal(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "fitness_goals"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    goal_type: Mapped[str] = mapped_column(String(30))
    title: Mapped[str] = mapped_column(String(100))
    start_date: Mapped[date] = mapped_column(Date)
    target_date: Mapped[date] = mapped_column(Date)
    target_value: Mapped[float | None] = mapped_column(Float)
    start_value: Mapped[float | None] = mapped_column(Float)
    milestones: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(20), default="active")  # active|completed|abandoned
    notes: Mapped[str | None] = mapped_column(Text)


class WeightMeasurement(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "weight_measurements"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    day: Mapped[date] = mapped_column(Date, index=True)
    weight_kg: Mapped[float] = mapped_column(Float)
    notes: Mapped[str | None] = mapped_column(Text)


class ProgressPhoto(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "progress_photos"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    storage_path: Mapped[str] = mapped_column(String(300))  # "<user_id>/<photo_id>.jpg" in a private bucket
    view: Mapped[str] = mapped_column(String(10))  # front|side|back
    taken_on: Mapped[date] = mapped_column(Date)
    notes: Mapped[str | None] = mapped_column(Text)
    hidden: Mapped[bool] = mapped_column(Boolean, default=False)


# --- AI -----------------------------------------------------------------------
class AIConversation(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "ai_conversations"
    id: Mapped[uuid.UUID] = uuid_pk()
    title: Mapped[str] = mapped_column(String(100))
    messages: Mapped[list[AIConversationMessage]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", order_by="AIConversationMessage.created_at"
    )


class AIConversationMessage(Base):
    __tablename__ = "ai_conversation_messages"
    id: Mapped[uuid.UUID] = uuid_pk()
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("ai_conversations.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(10))  # user|assistant
    content: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    conversation: Mapped[AIConversation] = relationship(back_populates="messages")


# --- Wearables ----------------------------------------------------------------
class WearableConnection(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "wearable_connections"
    id: Mapped[uuid.UUID] = uuid_pk()
    provider: Mapped[str] = mapped_column(String(30))  # health_connect|apple_health
    status: Mapped[str] = mapped_column(String(20))  # connected|revoked|error
    granted_types: Mapped[list] = mapped_column(JSON, default=list)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_error: Mapped[str | None] = mapped_column(String(300))
    __table_args__ = (UniqueConstraint("user_id", "provider", name="uq_wearable_provider"),)


class SyncedHealthRecord(OwnedMixin, Base):
    __tablename__ = "synced_health_records"
    id: Mapped[uuid.UUID] = uuid_pk()
    provider: Mapped[str] = mapped_column(String(30))
    record_uid: Mapped[str] = mapped_column(String(120))  # provider-side id or deterministic hash
    data_type: Mapped[str] = mapped_column(String(30))  # steps|heart_rate|active_minutes|sleep|workout|calories
    value: Mapped[float] = mapped_column(Float)
    unit: Mapped[str] = mapped_column(String(20))
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("user_id", "provider", "record_uid", name="uq_health_record"),)
