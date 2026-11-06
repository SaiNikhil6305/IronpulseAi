from __future__ import annotations

import hashlib
import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import SecurityAuditEvent, User, UserProfile
from app.models.base import utcnow


def user_hash(user_id: uuid.UUID) -> str:
    return hashlib.sha256(str(user_id).encode()).hexdigest()


def ensure_user(db: Session, user_id: uuid.UUID, email: str | None) -> User:
    user = db.get(User, user_id)
    if user is None:
        user = User(id=user_id, email=email)
        db.add(user)
        try:
            db.commit()
        except IntegrityError:  # concurrent first request
            db.rollback()
            user = db.get(User, user_id)
            assert user is not None
    return user


def get_or_create_profile(db: Session, user_id: uuid.UUID) -> UserProfile:
    profile = db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
    if profile is None:
        profile = UserProfile(user_id=user_id)
        db.add(profile)
        db.commit()
    return profile


def audit(db: Session, event_type: str, user_id: uuid.UUID | None = None, **detail) -> None:
    db.add(SecurityAuditEvent(
        user_hash=user_hash(user_id) if user_id else None,
        event_type=event_type,
        detail=detail,
        created_at=utcnow(),
    ))
    db.commit()
