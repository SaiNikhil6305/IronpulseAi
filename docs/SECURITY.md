# Security

## Threat model (summary)

| Asset | Threat | Control |
|---|---|---|
| Other users' records | IDOR / guessing ids | Server derives user from verified JWT; every query filtered by `user_id`; foreign ids → `404`. Tested: `test_user_isolation`, `test_photo_paths_must_be_in_own_folder`, `test_ai_conversation_isolation_and_delete`, `test_snapshot_contains_only_own_data`. |
| Database via Supabase REST | Leaked anon key / user JWT used against PostgREST | RLS forced on all tables with no client policies + privileges revoked (`policies.sql`), verified against PostgreSQL 16. |
| Progress photos | Public URLs, cross-user reads | Private bucket; storage policies restrict to `<auth.uid()>/…`; server rejects metadata outside the user's folder; viewing uses short-lived signed URLs. |
| Server secrets | Shipping keys in the APK | App receives only public values (Supabase URL, anon key, API URL, OAuth client IDs). Service-role key, DB password, AI key, Google client secret live only in `backend/.env` / Supabase. Verified: `grep` of `lib/` finds no secret variables. |
| Tokens on device | Theft from storage / backups | Supabase session + PKCE verifier in Android Keystore / iOS Keychain; `allowBackup=false` and data-extraction rules exclude app data from cloud backup/device transfer. |
| Tokens in logs | Leakage | JSON logger redacts `authorization`, `password`, `token`, `api_key`, `secret` keys and `Bearer …` strings; request logs record method/path/status only. Tested: `test_tokens_never_logged`. |
| XP / achievements | Farming via retries, toggles, edits | Unique `(user_id, event_key)` ledger reconciled from current records; tested for retries, re-opened sets, toggled checklist items and stale snapshots. |
| AI endpoint | Cost abuse, prompt data leakage | Auth required; 6 req/min + 50/day per user; 2,000-char input cap; 30 s timeout; only user-enabled context scopes sent; provider errors never produce fabricated text. |
| API | Abuse / large payloads | 240 req/min per user; 1 MB request limit; Pydantic validation with bounds on every field. |
| Transport | Interception | HTTPS only (`usesCleartextTraffic=false`); deploy the API behind TLS. |
| Account deletion | Incomplete erasure | Cascade delete + storage cleanup + auth-user deletion; `partial` status is surfaced, never hidden; hashed deletion record. Tested: `test_account_deletion_removes_all_data`. |

## Secrets management

* `backend/.env` (git-ignored) or the host's secret manager. `.env.example` files contain placeholders only.
* Rotate the Supabase service-role key and AI key if they are ever exposed; the app needs no update.
* Release keystore: never in Git; CI uses base64 secrets.

## Dependency auditing

* Python: `pip-audit -r backend/requirements.txt` (runs in CI).
* Dart: `flutter pub outdated` monthly; review advisories for direct dependencies.
* License inventory: `docs/DEPENDENCY_LICENSES.md` (regenerate with `tool/license_inventory.py`).

## Monitoring & error tracking

Structured JSON logs to stdout with a request id per call (`x-request-id`). Ship them to your host's log
service. An error-tracking SDK (e.g. Sentry) is **not integrated** — add one with PII scrubbing before launch if
needed. Unhandled exceptions are logged server-side and return a generic `internal_error`.

## Backups

Use Supabase daily backups / Point-in-Time Recovery (paid plans). Test a restore before launch. Progress photos
live in Supabase Storage (include in your backup plan or accept they are user-recoverable from the device).

## Security review checklist (run before each release)

- [ ] `grep -rnE "service_role|SERVICE_ROLE|sk-|AI_API_KEY|DATABASE_URL" lib/` → no matches
- [ ] `config/app_config.json` contains only public values; not committed
- [ ] `backend/supabase/policies.sql` applied; RLS check: `select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where nspname='public' and relkind='r' and not relrowsecurity;` → only `alembic_version`
- [ ] Two test accounts: A cannot read/modify B's sessions, weights, photos, AI chats (backend tests + manual)
- [ ] `ENVIRONMENT=production` (disables `/docs`, enforces Postgres + service role key)
- [ ] API served over HTTPS only; CORS origins empty (mobile app needs none)
- [ ] `pip-audit` clean; Flutter dependencies reviewed
- [ ] Logs reviewed for tokens / personal data
- [ ] Release APK signed with the upload key (not debug)
- [ ] Rate limits appropriate; if running >1 API instance, move the limiter to Redis
- [ ] Privacy policy & terms reviewed by a lawyer; placeholders filled

## Incident response

See [INCIDENT_RESPONSE.md](INCIDENT_RESPONSE.md).

## Known gaps

* The rate limiter is in-process (per instance). Use Redis-backed limits when scaling horizontally.
* Request-size guard relies on `Content-Length`; also set a body limit at the reverse proxy.
* No certificate pinning (standard TLS validation only).
* Sign in with Apple not implemented (needed for App Store with Google sign-in).
