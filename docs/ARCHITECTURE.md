# Architecture

```
┌──────────────────────── Flutter app (Android / iOS) ────────────────────────┐
│ presentation (screens, widgets)                                             │
│        │ Riverpod providers (read models recompute on local DB changes)     │
│ application/data (controllers, repositories, DataWriter)                   │
│        │                                     │                              │
│  SQLite (sqflite)                     Sync service ── Dio ──► FastAPI /v1/* │
│   • docs   (JSON per collection)       (outbox, retry,         │            │
│   • outbox (pending idempotent ops)     hydration)             │            │
│  Secure storage (Keystore/Keychain): Supabase session          │            │
│  Shared prefs: non-sensitive settings                          │            │
│  Local notifications (reminders, rest timer)                   │            │
│  Health Connect / HealthKit (read-only)                        │            │
└──────────────┬─────────────────────────────────────────────────┼────────────┘
               │ Supabase Auth (email, Google ID token)          │ Bearer JWT
               ▼                                                  ▼
        ┌─────────────┐   JWKS / HS256 verify   ┌──────────────────────────────┐
        │ Supabase    │◄────────────────────────┤ FastAPI backend              │
        │ Auth        │                         │ • authz: every query scoped  │
        │ Storage     │◄── service role (only   │   to the token's user id     │
        │ (private    │    for account deletion)│ • XP ledger, PRs, streaks    │
        │  photos)    │                         │ • AI proxy (provider-agnostic│
        │ Postgres ◄──┼─────── SQLAlchemy ──────┤   rate + daily limits)       │
        │ (RLS: deny  │       (DATABASE_URL)    │ • export / account deletion  │
        │  all client)│                         │ • Alembic migrations         │
        └─────────────┘                         └──────────────┬───────────────┘
                                                                ▼
                                                     AI provider (Anthropic or
                                                     any OpenAI-compatible API)
```

## Key decisions

| Decision | Why |
|---|---|
| **Local-first app.** Every screen reads SQLite; writes go to SQLite first and are queued. | The gym is often offline. A set must never be lost and the logger must never wait on the network. |
| **Client never talks to Postgres directly.** RLS denies everything to `anon`/`authenticated`; the backend owns all data access. | One authorization layer that is unit-tested (`tests/test_api.py::test_user_isolation`); UI checks are never the only control. |
| **Client-generated UUIDs + idempotent `PUT`/`DELETE`.** | Offline replays, retries and duplicate submissions can never create duplicates. |
| **XP is derived on the server** with a unique `(user_id, event_key)` ledger that is reconciled against current records. | Edits, re-opened sets, toggled checklist items and repeated syncs can't farm XP. The app mirrors the rules (`xp_rules.dart`) for instant/offline display and shows "pending sync" until the server confirms. |
| **AI only via backend**, provider chosen by env (`AI_PROVIDER`). | Keys stay server-side; rate/usage limits and data minimisation are enforced centrally. |
| **Device-only mode** when the build has no backend config. | Lets the APK be installed and used for real training before Supabase/Google/AI are set up; clearly labelled, nothing is synced. |
| Hand-written models instead of Freezed/json_serializable. | ~10 small models; avoids a code-generation step in CI while JSON round-trips are unit-tested (`test/unit/domain_test.dart`). |
| Riverpod 3 + GoRouter. | Redirect logic is a pure function (`resolveRedirect`) and unit-tested. |

## Code layout

```
lib/
  core/        config (Env), theme, routing (router, shell, bootstrap), network (ApiClient),
               storage (LocalDb, providers), sync (SyncService, DataWriter), utils, widgets
  features/<feature>/{data,domain,presentation}
    auth, onboarding, home, workouts, exercises, gamification, nutrition, checklist,
    goals, progress, ai_assistant, notifications, wearables, profile, settings
backend/app/
  api/ (routers)  core/ (config, db, security, errors, logging, rate limit)
  models/  schemas/  services/ (workouts, gamification, ai, account, users)  data/exercises.json
backend/migrations/  (Alembic)   backend/supabase/policies.sql   backend/tests/
```

## Offline sync

1. `DataWriter.save()` writes the document to SQLite, then enqueues an outbox op
   `{op_id, method, path, body, coalesce_key=path}`. A newer op for the same path replaces an unsent older one
   (a workout produces one snapshot upload, not one per keystroke).
2. `SyncService` runs on writes (2 s debounce), connectivity regained, app resume and every 2 minutes.
   Ops are sent strictly in order.
3. Outcomes: `2xx` → removed; `DELETE 404` → removed; network/timeout/`5xx`/`429`/`401` → kept, attempt counted,
   processing stops to preserve order; other `4xx` → **kept and marked failed**, shown in Settings › Sync status
   with *Retry failed*. Nothing is silently discarded.
4. After sign-in, `hydrate()` pulls `/v1/sync/snapshot` and replaces local collections **except** documents with
   unsent changes.

**Conflict resolution.** Workout sessions carry `client_updated_at` (monotonic per device). The server applies a
snapshot only if it is newer than what it has (last-write-wins); stale replays are acknowledged with
`applied=false` and change nothing. Other resources are small documents written whole; the last request to reach
the server wins. Deleting a session on one device while editing it on another: the delete wins unless the other
device's newer snapshot arrives afterwards, which re-creates it (no data is silently lost).

## Unfinished workouts

`ActiveWorkoutController` writes the full session to SQLite on every change and stores its id in
`meta/active_session_id`. On start-up the controller restores it, so closing the app, navigating away, losing
network or restarting the phone resumes the workout (`test/unit/data_test.dart` "survives an app restart").
The rest timer persists its end time and schedules a local notification, so it also alerts in the background.
