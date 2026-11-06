from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import JSON, Boolean, Date, DateTime, Float, Integer, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base
from app.models.base import OwnedMixin, TimestampMixin, utcnow, uuid_pk


class User(TimestampMixin, Base):
    """Mirror of a Supabase auth user. The id equals auth.users.id."""

    __tablename__ = "users"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    email: Mapped[str | None] = mapped_column(String(320))


class UserProfile(TimestampMixin, OwnedMixin, Base):
    __tablename__ = "user_profiles"
    id: Mapped[uuid.UUID] = uuid_pk()
    display_name: Mapped[str] = mapped_column(String(60), default="")
    age_range: Mapped[str | None] = mapped_column(String(20))
    height_cm: Mapped[float | None] = mapped_column(Float)
    current_weight_kg: Mapped[float | None] = mapped_column(Float)
    target_weight_kg: Mapped[float | None] = mapped_column(Float)
    experience: Mapped[str | None] = mapped_column(String(20))
    goals: Mapped[list] = mapped_column(JSON, default=list)
    training_days: Mapped[list] = mapped_column(JSON, default=list)  # ISO weekday ints 1..7
    preferred_gym_time: Mapped[str | None] = mapped_column(String(5))  # HH:MM
    workout_duration_min: Mapped[int | None] = mapped_column(Integer)
    equipment: Mapped[list] = mapped_column(JSON, default=list)
    dietary_preferences: Mapped[list] = mapped_column(JSON, default=list)
    allergies: Mapped[str | None] = mapped_column(Text)
    units: Mapped[str] = mapped_column(String(8), default="metric")
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    weekly_target: Mapped[int] = mapped_column(Integer, default=3)
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    ai_context_scopes: Mapped[list] = mapped_column(JSON, default=list)  # user-authorised AI context

    __table_args__ = (UniqueConstraint("user_id", name="uq_profile_user"),)


class ConsentRecord(OwnedMixin, Base):
    __tablename__ = "consent_records"
    id: Mapped[uuid.UUID] = uuid_pk()
    consent_type: Mapped[str] = mapped_column(String(40))  # privacy_policy, terms, ai_processing, health_data
    version: Mapped[str] = mapped_column(String(20))
    granted: Mapped[bool] = mapped_column(Boolean)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AccountDeletionRequest(Base):
    """Kept after deletion as proof of erasure; contains no personal data."""

    __tablename__ = "account_deletion_requests"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_hash: Mapped[str] = mapped_column(String(64), index=True)  # sha256 of user id
    requested_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    notes: Mapped[str | None] = mapped_column(Text)


class SecurityAuditEvent(Base):
    __tablename__ = "security_audit_events"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_hash: Mapped[str | None] = mapped_column(String(64), index=True)
    event_type: Mapped[str] = mapped_column(String(60))
    detail: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class AIUsageDay(OwnedMixin, Base):
    """Per-user daily AI message counter used for usage limits."""

    __tablename__ = "ai_usage_days"
    id: Mapped[uuid.UUID] = uuid_pk()
    day: Mapped[date] = mapped_column(Date)
    message_count: Mapped[int] = mapped_column(Integer, default=0)
    __table_args__ = (UniqueConstraint("user_id", "day", name="uq_ai_usage_day"),)
