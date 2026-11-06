import os
import tempfile
import time
import uuid

_tmp = tempfile.mkdtemp()
os.environ.update({
    "ENVIRONMENT": "test",
    # Set TEST_DATABASE_URL to run the suite against a migrated PostgreSQL database.
    "DATABASE_URL": os.environ.get("TEST_DATABASE_URL", f"sqlite:///{_tmp}/test.db"),
    "SUPABASE_JWT_SECRET": "test-secret-for-hs256-tokens-only-0123456789",
    "SUPABASE_URL": "",
    "SUPABASE_SERVICE_ROLE_KEY": "",
    "AI_PROVIDER": "anthropic",
    "AI_API_KEY": "test-key",
    "AI_MODEL": "test-model",
    "AI_RATE_LIMIT_PER_MINUTE": "3",
    "AI_DAILY_MESSAGE_LIMIT": "5",
})

import jwt  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.rate_limit import limiter  # noqa: E402
from app.main import app  # noqa: E402

SECRET = os.environ["SUPABASE_JWT_SECRET"]


def make_token(user_id: uuid.UUID, exp_offset: int = 3600, aud: str = "authenticated", secret: str = SECRET) -> str:
    return jwt.encode({"sub": str(user_id), "email": f"{user_id.hex[:6]}@example.test", "aud": aud,
                       "exp": int(time.time()) + exp_offset, "role": "authenticated"}, secret, algorithm="HS256")


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _reset_limits():
    limiter.reset()
    yield


class Api:
    def __init__(self, client: TestClient, user_id: uuid.UUID):
        self.c = client
        self.id = user_id
        self.h = {"authorization": f"Bearer {make_token(user_id)}"}

    def __getattr__(self, method):
        def call(path, **kw):
            return getattr(self.c, method)(path, headers=self.h, **kw)
        return call


@pytest.fixture
def alice(client):
    return Api(client, uuid.uuid4())


@pytest.fixture
def bob(client):
    return Api(client, uuid.uuid4())
