from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.db import get_db
from app.core.errors import AppError
from app.core.security import CurrentUser, get_current_user
from app.models import AIConversation
from app.schemas.tracking import AIChatMessageOut, AIConversationOut, AIMessageIn
from app.services import ai

router = APIRouter(prefix="/v1/ai", tags=["ironpulse ai"])


@router.get("/status")
def status(_: CurrentUser = Depends(get_current_user), settings: Settings = Depends(get_settings)):
    return {"available": settings.ai_configured, "daily_limit": settings.ai_daily_message_limit,
            "max_input_chars": settings.ai_max_input_chars}


@router.post("/messages")
def send_message(body: AIMessageIn, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db),
                 settings: Settings = Depends(get_settings)):
    return ai.chat(db, settings, user.id, body.conversation_id, body.message, body.context_scopes)


@router.get("/conversations", response_model=list[AIConversationOut])
def conversations(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return list(db.scalars(select(AIConversation).where(AIConversation.user_id == user.id)
                           .order_by(AIConversation.updated_at.desc()).limit(50)))


@router.get("/conversations/{conversation_id}/messages", response_model=list[AIChatMessageOut])
def messages(conversation_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
             db: Session = Depends(get_db)):
    conv = db.get(AIConversation, conversation_id)
    if conv is None or conv.user_id != user.id:
        raise AppError(404, "not_found", "Conversation not found.")
    return conv.messages


@router.delete("/conversations/{conversation_id}", status_code=204)
def delete_conversation(conversation_id: uuid.UUID, user: CurrentUser = Depends(get_current_user),
                        db: Session = Depends(get_db)):
    conv = db.get(AIConversation, conversation_id)
    if conv is not None and conv.user_id == user.id:
        db.delete(conv)
        db.commit()
    return Response(status_code=204)
