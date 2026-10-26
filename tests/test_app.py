import os

os.environ["IRONPULSE_AI_TOKEN"] = "t" * 32
os.environ["RATE_LIMIT_PER_MINUTE"] = "3"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import app as server  # noqa: E402

REAL_CALL = server.call_model

AUTH = {"authorization": "Bearer " + "t" * 32}
BODY = {"messages": [{"role": "user", "content": "Give me a push day"}]}


@pytest.fixture(autouse=True)
def reset(monkeypatch):
    server.limiter.minute.clear()
    server.limiter.day.clear()
    seen = {}

    async def fake(settings, messages):
        seen["messages"] = messages
        return "Bench press 3x8..."

    monkeypatch.setattr(server, "call_model", fake)
    yield seen


client = TestClient(server.app)


def test_rejects_missing_and_wrong_token():
    assert client.post("/v1/chat", json=BODY).status_code == 401
    r = client.post("/v1/chat", json=BODY, headers={"authorization": "Bearer nope"})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthorized"


def test_chat_ok_and_system_prompt_has_safety(reset):
    r = client.post("/v1/chat", json=BODY, headers=AUTH)
    assert r.status_code == 200
    assert r.json()["reply"].startswith("Bench")
    system = reset["messages"][0]["content"]
    assert "steroids" in system and "not a doctor" in system


def test_context_only_included_when_sent(reset):
    client.post("/v1/chat", json=BODY, headers=AUTH)
    assert "shared with their permission" not in reset["messages"][0]["content"]
    client.post("/v1/chat", json={**BODY, "context": "Goal: Build muscle"}, headers=AUTH)
    assert "Goal: Build muscle" in reset["messages"][0]["content"]


def test_validation():
    too_long = {"messages": [{"role": "user", "content": "x" * 4001}]}
    assert client.post("/v1/chat", json=too_long, headers=AUTH).status_code == 422
    last_assistant = {"messages": [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "yo"}]}
    assert client.post("/v1/chat", json=last_assistant, headers=AUTH).status_code == 422
    too_many = {"messages": [{"role": "user", "content": "hi"}] * 21}
    assert client.post("/v1/chat", json=too_many, headers=AUTH).status_code == 422


def test_body_size_limit():
    r = client.post("/v1/chat", content=b"x" * 70_000, headers={**AUTH, "content-type": "application/json"})
    assert r.status_code == 413


def test_rate_limit():
    codes = [client.post("/v1/chat", json=BODY, headers=AUTH).status_code for _ in range(4)]
    assert codes == [200, 200, 200, 429]


def test_provider_down_gives_clear_error(monkeypatch):
    async def down(settings, messages):
        raise server.ProviderError("Cannot reach the AI model. Is Ollama running? Start it with: ollama serve")

    monkeypatch.setattr(server, "call_model", down)
    r = client.post("/v1/chat", json=BODY, headers=AUTH)
    assert r.status_code == 503
    assert "ollama serve" in r.json()["error"]["message"]


def test_real_connect_error_is_translated():
    import asyncio

    s = server.Settings(ollama_url="http://127.0.0.1:1")
    with pytest.raises(server.ProviderError) as e:
        asyncio.run(REAL_CALL(s, [{"role": "user", "content": "hi"}]))
    assert "ollama serve" in e.value.message


def test_health_is_public():
    assert client.get("/health").json() == {"status": "ok"}


def test_supabase_user_token_accepted(reset, monkeypatch):
    async def fake(settings, token):
        return "abc" if token == "a.b.c" else None
    monkeypatch.setattr(server, "verify_supabase_user", fake)
    r = client.post("/v1/chat", json=BODY, headers={"authorization": "Bearer a.b.c"})
    assert r.status_code == 200
    assert client.post("/v1/chat", json=BODY, headers={"authorization": "Bearer x.y.z"}).status_code == 401


def test_supabase_disabled_rejects_jwt():
    s = server.Settings(supabase_url=None)
    import asyncio
    assert asyncio.run(server.verify_supabase_user(s, "a.b.c")) is None
