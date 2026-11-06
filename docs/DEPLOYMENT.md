# Deployment

## Local development

```bash
# Backend (SQLite, no external services needed for tests)
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env            # set SUPABASE_URL (and SUPABASE_JWT_SECRET for legacy projects)
pytest -q                       # 34 tests
uvicorn app.main:app --reload   # http://localhost:8000/docs

# App
cd ..
flutter pub get
flutter analyze && flutter test
cp config/app_config.example.json config/app_config.json   # API_BASE_URL=http://10.0.2.2:8000 for the emulator
flutter run --dart-define-from-file=config/app_config.json
```
Note: release builds forbid cleartext HTTP; use HTTPS (or a tunnel) for anything other than local debugging.

## Production backend

1. **Database:** Supabase project → `DATABASE_URL` (direct connection or session pooler; use
   `postgresql+psycopg://`). Run migrations: `alembic upgrade head`. Then run `backend/supabase/policies.sql`.
2. **Container:** `backend/Dockerfile` (non-root user; runs migrations then uvicorn). Deploy to any container
   host (Cloud Run, Fly.io, Render, Railway, ECS, a VPS behind Caddy/nginx). Terminate TLS at the host.
3. **Environment** (secrets in the host's secret store):

| Variable | Required | Notes |
|---|---|---|
| `ENVIRONMENT=production` | yes | Enforces Postgres + service role key; disables `/docs` |
| `DATABASE_URL` | yes | Supabase Postgres |
| `SUPABASE_URL` | yes | JWKS verification |
| `SUPABASE_JWT_SECRET` | legacy projects | Only if tokens are HS256 |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Account deletion only |
| `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL`, `AI_BASE_URL` | for AI | Empty = AI disabled (app shows "not configured") |
| `AI_RATE_LIMIT_PER_MINUTE`, `AI_DAILY_MESSAGE_LIMIT` | optional | Defaults 6 / 50 |
| `API_RATE_LIMIT_PER_MINUTE`, `MAX_REQUEST_BYTES`, `LOG_LEVEL` | optional | |

4. **Startup checks:** the app refuses to start in production with missing critical config and logs
   `configuration_problem` entries in other environments. `GET /health` (liveness), `GET /ready` (DB + AI flag).
5. **Scaling:** one instance is fine to start. With several instances, replace the in-process rate limiter
   with Redis (same interface in `app/core/rate_limit.py`).
6. **Logs & monitoring:** JSON logs on stdout → host log service; alert on 5xx rate and `/ready` failures.
   Keep request/audit logs ≥ 1 year (PRIVACY_AND_COMPLIANCE.md).
7. **Backups:** enable Supabase PITR/daily backups; test a restore.

## Releasing the app

1. Fill `config/app_config.json` (public values only), bump `version:` in `pubspec.yaml`.
2. `flutter build appbundle --release --dart-define-from-file=config/app_config.json` (signed with the upload key).
3. Upload to Play Console (internal testing → closed → production). Complete Data safety, Health Connect
   declaration, content rating, privacy-policy URL, account-deletion URL.
4. iOS: see IOS_BUILD.md.

## CI/CD

`.github/workflows/ci.yml`: backend tests on SQLite and PostgreSQL 16 (+ `alembic check`, `pip-audit`),
`flutter analyze` + `flutter test`, and release APK/AAB artefacts. Public app config comes from repository
**variables**; the signing keystore from repository **secrets**.
