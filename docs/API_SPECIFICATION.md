# API specification

Interactive docs: run the backend and open `/docs` (disabled when `ENVIRONMENT=production`).
Machine-readable: [`openapi.json`](openapi.json) (generated from the code).

## Conventions

* **Auth:** every `/v1/*` request needs `Authorization: Bearer <Supabase access token>`. Tokens are verified
  locally (JWKS for RS256/ES256 projects, or `SUPABASE_JWT_SECRET` for legacy HS256). Audience `authenticated`,
  `exp` and `sub` required. The user id always comes from the token.
* **Errors:** `{"error": {"code": "...", "message": "...", "details": ...}}`. Codes include `unauthorized`,
  `invalid_token`, `token_expired`, `validation_error`, `not_found`, `id_conflict`, `rate_limited`,
  `daily_limit_reached`, `ai_not_configured`, `ai_timeout`, `ai_provider_error`, `payload_too_large`.
  Other users' resources return `404` (existence is not revealed).
* **Idempotency:** resources are created/updated with `PUT /…/{client_uuid}`; deletes return `204` even when
  already deleted. Session `PUT` is last-write-wins on `client_updated_at` and returns `applied=false` for stale or
  duplicate snapshots.
* **Rate limits:** 240 requests/min per user (`API_RATE_LIMIT_PER_MINUTE`); AI 6/min and 50/day per user.
  Bodies over 1 MB are rejected (`413`).
* **Pagination:** `GET /v1/sessions?limit=&before=` returns `{items, next_cursor}` (cursor = ISO `started_at`).
* **Headers:** responses carry `x-request-id`, `cache-control: no-store`, `x-content-type-options: nosniff`.

## Key payloads

`PUT /v1/sessions/{id}` — full snapshot:
```json
{"name": "Push", "workout_day_name": "Push", "status": "completed",
 "started_at": "2026-10-25T12:00:00Z", "ended_at": "2026-10-25T12:55:00Z",
 "client_updated_at": "2026-10-25T12:55:01.123Z", "extra_muscle_groups": ["core"], "notes": null,
 "exercises": [{"id": "uuid", "exercise_ref": "barbell-bench-press", "exercise_name": "Barbell Bench Press",
   "position": 0, "notes": null,
   "sets": [{"id": "uuid", "position": 0, "side": null, "weight_kg": 40, "reps": 10, "rpe": 8,
             "duration_s": null, "distance_m": null, "completed": true, "completed_at": "…"}]}]}
```
→ `{"id", "applied", "server_updated_at", "xp_from_session", "new_achievements": [..], "personal_records": [..]}`

`POST /v1/ai/messages` — `{"message": "...", "conversation_id": null, "context_scopes": ["goals","workouts"]}`
→ `{"conversation_id", "reply", "remaining_today", "context_scopes_used"}`. Only scopes the user enabled in
their profile (`ai_context_scopes`) **and** requested are used.

`DELETE /v1/account` → `{"request_id", "status": "completed" | "partial", "notes"}` (`partial` means data was
erased but remote cleanup — auth user or storage — needs operator follow-up; it is never hidden).

## Endpoints

### ops

| Method | Path | Summary |
|---|---|---|
| GET | `/health` | Health |
| GET | `/ready` | Ready |

### ironpulse ai

| Method | Path | Summary |
|---|---|---|
| GET | `/v1/ai/conversations` | Conversations |
| DELETE | `/v1/ai/conversations/{conversation_id}` | Delete Conversation |
| GET | `/v1/ai/conversations/{conversation_id}/messages` | Messages |
| POST | `/v1/ai/messages` | Send Message |
| GET | `/v1/ai/status` | Status |

### profile & account

| Method | Path | Summary |
|---|---|---|
| DELETE | `/v1/account` | Delete Account |
| GET | `/v1/account/export` | Export |
| POST | `/v1/consents` | Record Consent |
| GET | `/v1/profile` | Get Profile |
| PUT | `/v1/profile` | Put Profile |
| POST | `/v1/profile/complete-onboarding` | Complete Onboarding |

### sync

| Method | Path | Summary |
|---|---|---|
| GET | `/v1/sync/snapshot` | Snapshot |

### tracking

| Method | Path | Summary |
|---|---|---|
| GET | `/v1/checklist` | Checklist Day |
| GET | `/v1/checklist/history` | Checklist History |
| DELETE | `/v1/checklist/items/{item_id}` | Delete Checklist Item |
| PUT | `/v1/checklist/items/{item_id}` | Put Checklist Item |
| PUT | `/v1/checklist/items/{item_id}/completion` | Toggle Completion |
| GET | `/v1/gamification/summary` | Gamification Summary |
| GET | `/v1/gamification/xp-history` | Xp History |
| GET | `/v1/goals` | List Goals |
| DELETE | `/v1/goals/{goal_id}` | Delete Goal |
| PUT | `/v1/goals/{goal_id}` | Put Goal |
| GET | `/v1/meals/saved` | Saved Meals |
| DELETE | `/v1/meals/{meal_id}` | Delete Meal |
| PUT | `/v1/meals/{meal_id}` | Put Meal |
| DELETE | `/v1/meals/{meal_id}/entries/{entry_id}` | Delete Entry |
| PUT | `/v1/meals/{meal_id}/entries/{entry_id}` | Put Entry |
| GET | `/v1/notification-preferences` | Get Prefs |
| PUT | `/v1/notification-preferences` | Put Prefs |
| GET | `/v1/nutrition/day` | Nutrition Day |
| GET | `/v1/nutrition/history` | Nutrition History |
| PUT | `/v1/nutrition/targets` | Put Targets |
| GET | `/v1/photos` | List Photos |
| DELETE | `/v1/photos/{photo_id}` | Delete Photo |
| PUT | `/v1/photos/{photo_id}` | Put Photo |
| POST | `/v1/push-tokens` | Register Push Token |
| GET | `/v1/schedule` | Get Schedule |
| PUT | `/v1/schedule` | Put Schedule |
| GET | `/v1/wearables` | List Wearables |
| POST | `/v1/wearables/sync` | Wearable Sync |
| DELETE | `/v1/wearables/{provider}` | Disconnect Wearable |
| GET | `/v1/weights` | List Weights |
| DELETE | `/v1/weights/{weight_id}` | Delete Weight |
| PUT | `/v1/weights/{weight_id}` | Put Weight |

### workouts

| Method | Path | Summary |
|---|---|---|
| GET | `/v1/exercises` | List Exercises |
| GET | `/v1/exercises/{exercise_ref}/previous` | Previous |
| GET | `/v1/sessions` | List Sessions |
| DELETE | `/v1/sessions/{session_id}` | Delete Session |
| GET | `/v1/sessions/{session_id}` | Get Session |
| PUT | `/v1/sessions/{session_id}` | Put Session |
| GET | `/v1/splits/active` | Get Active Split |
| PUT | `/v1/splits/{split_id}` | Put Split |
| GET | `/v1/user-exercises` | List User Exercises |
| DELETE | `/v1/user-exercises/{item_id}` | Delete User Exercise |
| PUT | `/v1/user-exercises/{item_id}` | Put User Exercise |
