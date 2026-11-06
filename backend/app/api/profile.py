from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.db import get_db
from app.core.security import CurrentUser, get_current_user
from app.models import ConsentRecord
from app.schemas.profile import ConsentIn, ProfileIn, ProfileOut
from app.services import account
from app.services.users import audit, get_or_create_profile

router = APIRouter(prefix="/v1", tags=["profile & account"])


@router.get("/profile", response_model=ProfileOut)
def get_profile(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    return get_or_create_profile(db, user.id)


@router.put("/profile", response_model=ProfileOut)
def put_profile(body: ProfileIn, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    p = get_or_create_profile(db, user.id)
    for k, v in body.model_dump().items():
        setattr(p, k, v)
    db.commit()
    return p


@router.post("/profile/complete-onboarding", response_model=ProfileOut)
def complete_onboarding(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    p = get_or_create_profile(db, user.id)
    p.onboarding_completed = True
    db.commit()
    return p


@router.post("/consents", status_code=201)
def record_consent(body: ConsentIn, user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    db.add(ConsentRecord(user_id=user.id, **body.model_dump()))
    db.commit()
    return {"recorded": True}


@router.get("/account/export")
def export(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db)):
    data = account.export_user_data(db, user.id)
    audit(db, "data_exported", user.id)
    return JSONResponse(data, headers={"content-disposition": 'attachment; filename="ironpulse-export.json"'})


@router.delete("/account", status_code=200)
def delete_account(user: CurrentUser = Depends(get_current_user), db: Session = Depends(get_db),
                   settings: Settings = Depends(get_settings)):
    req = account.delete_account(db, settings, user.id)
    return {"request_id": str(req.id), "status": req.status, "notes": req.notes}

