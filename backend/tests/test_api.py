import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

import httpx

from tests.conftest import Api, make_token


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat()


def session_payload(status="completed", sets=None, started=None, updated=None, ref="barbell-bench-press",
                    ex_id=None):
    started = started or datetime.now(timezone.utc) - timedelta(hours=1)
    sets = sets if sets is not None else [
        {"id": str(uuid.uuid4()), "position": i, "weight_kg": 40, "reps": 10 - i, "completed": True,
         "completed_at": iso(started + timedelta(minutes=5 * i))} for i in range(3)]
    return {
        "name": "Push Day", "workout_day_name": "Push", "status": status, "started_at": iso(started),
        "ended_at": iso(started + timedelta(minutes=50)) if status == "completed" else None,
        "client_updated_at": iso(updated or datetime.now(timezone.utc)),
        "exercises": [{"id": ex_id or str(uuid.uuid4()), "exercise_ref": ref, "exercise_name": "Bench Press",
                       "position": 0, "sets": sets}],
    }


# ---- Operational & authentication ---------------------------------------------
def test_health_and_ready(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json()["status"] == "ready"


def test_unauthenticated_requests_rejected(client):
    r = client.get("/v1/profile")
    assert r.status_code == 401 and r.json()["error"]["code"] == "unauthorized"


def test_invalid_and_expired_tokens_rejected(client):
    uid = uuid.uuid4()
    bad = client.get("/v1/profile", headers={"authorization": f"Bearer {make_token(uid, secret='wrong' * 10)}"})
    assert bad.status_code == 401 and bad.json()["error"]["code"] == "invalid_token"
    exp = client.get("/v1/profile", headers={"authorization": f"Bearer {make_token(uid, exp_offset=-10)}"})
    assert exp.status_code == 401 and exp.json()["error"]["code"] == "token_expired"
    aud = client.get("/v1/profile", headers={"authorization": f"Bearer {make_token(uid, aud='anon')}"})
    assert aud.status_code == 401


def test_payload_validation(alice):
    r = alice.put("/v1/profile", json={"display_name": "", "timezone": "Mars/Base"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "validation_error"


# ---- Profile & onboarding --------------------------------------------------------
def test_profile_roundtrip_and_onboarding(alice):
    r = alice.get("/v1/profile")
    assert r.status_code == 200 and r.json()["onboarding_completed"] is False
    body = {"display_name": "Arjun", "age_range": "25-34", "height_cm": 178, "current_weight_kg": 74,
            "experience": "beginner", "goals": ["build_muscle"], "training_days": [5, 1, 3, 3],
            "timezone": "Asia/Kolkata", "weekly_target": 4}
    r = alice.put("/v1/profile", json=body)
    assert r.status_code == 200 and r.json()["training_days"] == [1, 3, 5]
    assert alice.post("/v1/profile/complete-onboarding").json()["onboarding_completed"] is True


# ---- Workouts, idempotency, XP -----------------------------------------------------
def test_exercise_library_seeded_and_filterable(alice):
    allx = alice.get("/v1/exercises").json()
    assert len(allx) >= 40
    chest = alice.get("/v1/exercises", params={"muscle": "chest"}).json()
    assert chest and all(e["primary_muscle"] == "chest" for e in chest)
    assert any("Bench" in e["name"] for e in alice.get("/v1/exercises", params={"q": "bench"}).json())


def test_session_sync_is_idempotent_and_awards_xp_once(alice):
    sid = str(uuid.uuid4())
    payload = session_payload()
    first = alice.put(f"/v1/sessions/{sid}", json=payload).json()
    assert first["applied"] is True and first["xp_from_session"] == 3 * 10 + 25
    assert "first_workout" in first["new_achievements"]
    # Retry the identical request (e.g. network retry / repeated offline sync).
    for _ in range(3):
        again = alice.put(f"/v1/sessions/{sid}", json=payload).json()
        assert again["applied"] is False and again["xp_from_session"] == 55
    hist = alice.get("/v1/sessions").json()["items"]
    assert len(hist) == 1
    summary = alice.get("/v1/gamification/summary").json()
    assert summary["level"]["total_xp"] == 55


def test_editing_and_reopening_sets_cannot_farm_xp(alice):
    sid = str(uuid.uuid4())
    p = session_payload()
    alice.put(f"/v1/sessions/{sid}", json=p)
    # Re-open a completed set, then complete it again with new values -> still one reward per set.
    p["exercises"][0]["sets"][0]["completed"] = False
    p["client_updated_at"] = iso(datetime.now(timezone.utc) + timedelta(seconds=1))
    assert alice.put(f"/v1/sessions/{sid}", json=p).json()["xp_from_session"] == 2 * 10 + 25
    p["exercises"][0]["sets"][0].update(completed=True, reps=12)
    p["client_updated_at"] = iso(datetime.now(timezone.utc) + timedelta(seconds=2))
    assert alice.put(f"/v1/sessions/{sid}", json=p).json()["xp_from_session"] == 55
    assert alice.get("/v1/gamification/summary").json()["level"]["total_xp"] == 55


def test_implausible_sets_earn_no_xp(alice):
    sets = [{"id": str(uuid.uuid4()), "position": 0, "weight_kg": 40, "reps": 0, "completed": True},
            {"id": str(uuid.uuid4()), "position": 1, "weight_kg": 40, "reps": 8, "completed": False}]
    r = alice.put(f"/v1/sessions/{uuid.uuid4()}", json=session_payload(sets=sets)).json()
    assert r["xp_from_session"] == 0


def test_stale_snapshot_does_not_overwrite_newer(alice):
    sid = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    newer = session_payload(updated=now)
    older = session_payload(updated=now - timedelta(minutes=5))
    older["notes"] = "stale edit"
    assert alice.put(f"/v1/sessions/{sid}", json=newer).json()["applied"] is True
    assert alice.put(f"/v1/sessions/{sid}", json=older).json()["applied"] is False
    assert alice.get(f"/v1/sessions/{sid}").json()["notes"] is None


def test_previous_performance_and_personal_record(alice):
    day1 = datetime.now(timezone.utc) - timedelta(days=3)
    alice.put(f"/v1/sessions/{uuid.uuid4()}", json=session_payload(started=day1, ref="leg-press"))
    prev = alice.get("/v1/exercises/leg-press/previous").json()
    assert [s["reps"] for s in prev["sets"]] == [10, 9, 8] and prev["sets"][0]["weight_kg"] == 40
    heavier = [{"id": str(uuid.uuid4()), "position": 0, "weight_kg": 50, "reps": 10, "completed": True}]
    r = alice.put(f"/v1/sessions/{uuid.uuid4()}", json=session_payload(sets=heavier, ref="leg-press")).json()
    assert r["personal_records"] and r["personal_records"][0]["weight_kg"] == 50
    assert "first_pr" in r["new_achievements"]


def test_discarding_session_removes_its_xp(alice):
    sid = str(uuid.uuid4())
    alice.put(f"/v1/sessions/{sid}", json=session_payload())
    assert alice.delete(f"/v1/sessions/{sid}").status_code == 204
    assert alice.delete(f"/v1/sessions/{sid}").status_code == 204  # idempotent
    assert alice.get("/v1/gamification/summary").json()["level"]["total_xp"] == 0


def test_split_change_preserves_history(alice):
    alice.put(f"/v1/sessions/{uuid.uuid4()}", json=session_payload())
    s1, s2 = uuid.uuid4(), uuid.uuid4()
    ppl = {"name": "PPL", "split_type": "ppl", "days": [
        {"name": "Push", "muscle_groups": ["chest"], "weekdays": [1],
         "template_exercises": [{"exercise_ref": "barbell-bench-press", "target_sets": 3}]}]}
    assert alice.put(f"/v1/splits/{s1}", json=ppl).status_code == 200
    fb = {"name": "Full", "split_type": "full_body", "days": [{"name": "Full A", "muscle_groups": ["legs"]}]}
    alice.put(f"/v1/splits/{s2}", json=fb)
    assert alice.get("/v1/splits/active").json()["name"] == "Full"
    assert len(alice.get("/v1/sessions").json()["items"]) == 1


# ---- Authorization / isolation ---------------------------------------------------
def test_user_isolation(alice, bob):
    sid = str(uuid.uuid4())
    alice.put(f"/v1/sessions/{sid}", json=session_payload())
    assert bob.get(f"/v1/sessions/{sid}").status_code == 404
    # Bob cannot overwrite Alice's session by guessing its id.
    hijack = session_payload(updated=datetime.now(timezone.utc) + timedelta(days=1))
    assert bob.put(f"/v1/sessions/{sid}", json=hijack).status_code == 404
    bob.delete(f"/v1/sessions/{sid}")
    assert alice.get(f"/v1/sessions/{sid}").status_code == 200
    assert bob.get("/v1/sessions").json()["items"] == []
    wid = str(uuid.uuid4())
    alice.put(f"/v1/weights/{wid}", json={"id": wid, "day": date.today().isoformat(), "weight_kg": 70})
    assert bob.put(f"/v1/weights/{wid}", json={"id": wid, "day": date.today().isoformat(),
                                              "weight_kg": 99}).status_code == 404
    assert bob.get("/v1/weights").json() == []
    export = bob.get("/v1/account/export").json()
    assert export["workout_sessions"] == [] and export["weight_measurements"] == []


def test_photo_paths_must_be_in_own_folder(alice, bob):
    pid = str(uuid.uuid4())
    body = {"id": pid, "storage_path": f"{bob.id}/{pid}.jpg", "view": "front", "taken_on": date.today().isoformat()}
    assert alice.put(f"/v1/photos/{pid}", json=body).status_code == 403
    body["storage_path"] = f"{alice.id}/{pid}.jpg"
    assert alice.put(f"/v1/photos/{pid}", json=body).status_code == 200


# ---- Checklist & weigh-ins ----------------------------------------------------
def test_checklist_toggle_awards_once(alice):
    iid = str(uuid.uuid4())
    alice.put(f"/v1/checklist/items/{iid}", json={"id": iid, "name": "Creatine", "category": "supplement"})
    today = date.today().isoformat()
    for completed in (True, True, False, True, True):
        r = alice.put(f"/v1/checklist/items/{iid}/completion",
                      json={"day": today, "completed": completed, "completion_id": str(uuid.uuid4())})
        assert r.status_code == 200
    assert r.json()["completed_item_ids"] == [iid]
    assert alice.get("/v1/gamification/summary").json()["level"]["total_xp"] == 5


def test_weekly_weigh_in_xp_once_per_week(alice):
    monday = date.today() - timedelta(days=date.today().weekday())
    for d in (monday, monday + timedelta(days=1)):
        wid = str(uuid.uuid4())
        alice.put(f"/v1/weights/{wid}", json={"id": wid, "day": d.isoformat(), "weight_kg": 72.5})
    assert alice.get("/v1/gamification/summary").json()["level"]["total_xp"] == 15


# ---- Nutrition --------------------------------------------------------------------
def test_meal_crud_and_totals(alice):
    mid = str(uuid.uuid4())
    day = date.today().isoformat()
    e1, e2 = str(uuid.uuid4()), str(uuid.uuid4())
    meal = {"id": mid, "day": day, "category": "morning", "entries": [
        {"id": e1, "food_name": "Eggs", "quantity": 3, "calories": 70, "protein_g": 6},
        {"id": e2, "food_name": "Oats", "quantity": 1, "calories": None, "protein_g": None}]}
    assert alice.put(f"/v1/meals/{mid}", json=meal).status_code == 200
    d = alice.get("/v1/nutrition/day", params={"day": day}).json()
    assert d["totals"]["calories"] == 210 and d["totals"]["protein_g"] == 18
    assert d["totals"]["entries_with_missing_values"] == 1
    alice.put(f"/v1/meals/{mid}/entries/{e1}", json={"id": e1, "food_name": "Eggs", "quantity": 2, "calories": 70,
                                                     "protein_g": 6, "is_estimate": True})
    d = alice.get("/v1/nutrition/day", params={"day": day}).json()
    assert d["totals"]["protein_g"] == 12 and d["totals"]["includes_estimates"] is True
    alice.delete(f"/v1/meals/{mid}/entries/{e1}")
    assert alice.get("/v1/nutrition/day", params={"day": day}).json()["totals"]["protein_g"] == 0
    alice.delete(f"/v1/meals/{mid}")
    assert alice.get("/v1/nutrition/day", params={"day": day}).json()["meals"] == []


def test_goal_progress(alice):
    gid = str(uuid.uuid4())
    start = date.today() - timedelta(days=1)
    alice.put(f"/v1/goals/{gid}", json={"id": gid, "goal_type": "target_weight", "title": "Reach 70",
                                       "start_date": start.isoformat(),
                                       "target_date": (start + timedelta(days=60)).isoformat(),
                                       "start_value": 80, "target_value": 70})
    wid = str(uuid.uuid4())
    alice.put(f"/v1/weights/{wid}", json={"id": wid, "day": date.today().isoformat(), "weight_kg": 75})
    g = alice.get("/v1/goals").json()[0]
    assert g["progress"] == 0.5 and g["current_value"] == 75
    bad = alice.put(f"/v1/goals/{gid}", json={"id": gid, "goal_type": "strength", "title": "x",
                                             "start_date": "2026-05-01", "target_date": "2026-04-01"})
    assert bad.status_code == 422


# ---- AI ---------------------------------------------------------------------------
class _FakeResponse:
    status_code = 200

    def __init__(self, text="Progressive overload means gradually increasing training demand."):
        self._text = text

    def raise_for_status(self):
        return None

    def json(self):
        return {"content": [{"type": "text", "text": self._text}]}


def test_ai_chat_scopes_and_history(alice):
    sent = {}

    def fake_post(self, url, headers=None, json=None):
        sent["system"] = json["system"]
        sent["headers"] = headers
        return _FakeResponse()

    alice.put("/v1/profile", json={"display_name": "A", "ai_context_scopes": ["goals"], "goals": ["strength"]})
    with patch.object(httpx.Client, "post", fake_post):
        r = alice.post("/v1/ai/messages", json={"message": "Explain progressive overload",
                                                "context_scopes": ["goals", "nutrition"]})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["context_scopes_used"] == ["goals"]  # nutrition not authorised in profile
    assert "strength" in sent["system"] and "Logged nutrition" not in sent["system"]
    conv = body["conversation_id"]
    msgs = alice.get(f"/v1/ai/conversations/{conv}/messages").json()
    assert [m["role"] for m in msgs] == ["user", "assistant"]


def test_ai_conversation_isolation_and_delete(alice, bob):
    with patch.object(httpx.Client, "post", lambda self, url, headers=None, json=None: _FakeResponse()):
        conv = alice.post("/v1/ai/messages", json={"message": "hi"}).json()["conversation_id"]
        assert bob.get(f"/v1/ai/conversations/{conv}/messages").status_code == 404
        assert bob.post("/v1/ai/messages", json={"message": "hi", "conversation_id": conv}).status_code == 404
    assert alice.delete(f"/v1/ai/conversations/{conv}").status_code == 204
    assert alice.get(f"/v1/ai/conversations/{conv}/messages").status_code == 404


def test_ai_rate_limit_and_daily_limit(client):
    user = Api(client, uuid.uuid4())
    with patch.object(httpx.Client, "post", lambda self, url, headers=None, json=None: _FakeResponse()):
        codes = [user.post("/v1/ai/messages", json={"message": f"q{i}"}).status_code for i in range(4)]
        assert codes == [200, 200, 200, 429]
        from app.core.rate_limit import limiter
        limiter.reset()
        codes = [user.post("/v1/ai/messages", json={"message": f"r{i}"}).json() for i in range(3)]
        assert codes[1]["remaining_today"] == 0
        assert codes[2]["error"]["code"] == "daily_limit_reached"


def test_ai_provider_errors_are_not_fabricated(alice):
    def boom(self, url, headers=None, json=None):
        raise httpx.ReadTimeout("slow")

    with patch.object(httpx.Client, "post", boom):
        r = alice.post("/v1/ai/messages", json={"message": "hello"})
    assert r.status_code == 504 and r.json()["error"]["code"] == "ai_timeout"


def test_ai_not_configured(client, alice):
    from app.core.config import get_settings

    s = get_settings()
    old = s.ai_api_key
    s.ai_api_key = ""
    try:
        r = alice.post("/v1/ai/messages", json={"message": "hello"})
        assert r.status_code == 503 and r.json()["error"]["code"] == "ai_not_configured"
        assert alice.get("/v1/ai/status").json()["available"] is False
    finally:
        s.ai_api_key = old


# ---- Account deletion & export --------------------------------------------------
def test_account_deletion_removes_all_data(client):
    user = Api(client, uuid.uuid4())
    user.put("/v1/profile", json={"display_name": "Temp"})
    user.put(f"/v1/sessions/{uuid.uuid4()}", json=session_payload())
    assert user.get("/v1/account/export").json()["workout_sessions"]
    r = user.delete("/v1/account").json()
    # Without a service-role key the Supabase auth user cannot be removed; this is reported, not hidden.
    assert r["status"] == "partial" and "auth" in r["notes"]
    # Same token, fresh empty account: all previous records are gone.
    assert user.get("/v1/sessions").json()["items"] == []
    assert user.get("/v1/profile").json()["display_name"] == ""
    assert user.get("/v1/gamification/summary").json()["level"]["total_xp"] == 0


def test_tokens_never_logged(client, caplog):
    import logging
    caplog.set_level(logging.INFO)
    token = make_token(uuid.uuid4())
    client.get("/v1/profile", headers={"authorization": f"Bearer {token}"})
    assert token not in caplog.text


def test_wearable_sync_dedupes(alice):
    rec = {"record_uid": "steps-2026-10-25", "data_type": "steps", "value": 8000, "unit": "count",
           "start_at": "2026-10-25T00:00:00Z", "end_at": "2026-10-25T23:59:59Z"}
    body = {"provider": "health_connect", "granted_types": ["steps"], "records": [rec]}
    assert alice.post("/v1/wearables/sync", json=body).json()["inserted"] == 1
    second = alice.post("/v1/wearables/sync", json=body).json()
    assert second["inserted"] == 0 and second["unchanged"] == 1
    rec["value"] = 9500
    third = alice.post("/v1/wearables/sync", json=body).json()
    assert third["inserted"] == 0 and third["updated"] == 1


def test_schedule_and_notification_prefs(alice):
    items = [{"weekday": 1, "time_local": "18:00", "workout_day_name": "Push"},
             {"weekday": 3, "is_rest_day": True}]
    r = alice.put("/v1/schedule", json={"items": items})
    assert r.status_code == 200 and [d["weekday"] for d in r.json()] == [1, 3]
    dup = alice.put("/v1/schedule", json={"items": [items[0], items[0]]})
    assert dup.status_code == 422
    p = alice.put("/v1/notification-preferences", json={"reminder_offsets_min": [10, 30, 30, 0]}).json()
    assert p["reminder_offsets_min"] == [30, 10, 0]
    bad = alice.put("/v1/notification-preferences", json={"reminder_offsets_min": [15]})
    assert bad.status_code == 422


def test_snapshot_contains_only_own_data(alice, bob):
    alice.put(f"/v1/sessions/{uuid.uuid4()}", json=session_payload())
    snap = bob.get("/v1/sync/snapshot").json()
    assert snap["sessions"] == [] and snap["profile"]["display_name"] == ""
    assert len(alice.get("/v1/sync/snapshot").json()["sessions"]) == 1
