# Database schema

PostgreSQL (Supabase). Schema is defined by SQLAlchemy models in `backend/app/models/` and versioned with
Alembic (`backend/migrations/versions/`). Verified: `alembic upgrade head` + `alembic check` on PostgreSQL 16
reports no drift.

## Ownership & access

* Every private table has `user_id → users.id ON DELETE CASCADE`. Deleting the `users` row erases all of a user's data.
* `users.id` equals the Supabase `auth.users.id` (taken from the verified JWT `sub`, never from a request body).
* **RLS** (`backend/supabase/policies.sql`): enabled and forced on every table with no policies for `anon` /
  `authenticated`, and table privileges revoked. The mobile app cannot read or write tables through PostgREST
  even with a valid user JWT. Verified locally: `SET ROLE authenticated; SELECT … FROM workout_sessions` →
  `permission denied`.
* The backend connects as the database owner and scopes every query by the authenticated user id.
* Private storage bucket `progress-photos`: objects only under `<auth.uid()>/…`, owner-only select/insert/update/delete.

## Tables

| Table | Purpose | Keys & constraints |
|---|---|---|
| users | Mirror of Supabase auth user | PK id (= auth uid) |
| user_profiles | Onboarding/profile fields, units, timezone, weekly target, AI context scopes | unique(user_id) |
| consent_records | Privacy/terms/AI/health consents with version | idx user_id |
| workout_splits | Splits; old ones archived (`is_active=false`), never deleted on change | idx user_id |
| workout_days | Days of a split, weekdays, muscle groups | FK split_id cascade |
| workout_templates | Exercise slots in a day (target sets/reps) | FK day_id cascade |
| exercise_library | Shared catalogue seeded from `app/data/exercises.json` | PK slug |
| user_exercises | Custom exercises and favourites | idx user_id |
| workout_sessions | Sessions; **PK generated on device** | idx (user_id, started_at) |
| workout_exercises | Exercises in a session | FK session_id cascade; PK from device |
| workout_sets | Sets (weight, reps, RPE, duration, distance, side, completed) | FK cascade; PK from device |
| xp_transactions | XP ledger | **unique(user_id, event_key)** |
| achievements / user_achievements | Achievement catalogue / unlocks | unique(user_id, achievement_id) |
| gym_schedules | Per-weekday time / rest / split day | unique(user_id, weekday) |
| notification_preferences | Reminder offsets, checklist & weigh-in reminders | unique(user_id) |
| notification_events | Push-token registry (reserved; reminders are local) | unique(user_id, kind, value) |
| checklist_items | Foods / supplements / habits (soft delete keeps history) | PK from device |
| checklist_completions | One per item per day | **unique(item_id, day)** |
| meals / food_entries | Meals by day & category, saved meals (`is_saved_template`) | FK cascade |
| nutrition_targets | Optional targets, can be disabled | unique(user_id) |
| fitness_goals | Goals with milestones and status | PK from device |
| weight_measurements | Weigh-ins | idx (user_id, day) |
| progress_photos | Photo metadata; path must start with the user's id | — |
| ai_conversations / ai_conversation_messages | Chat history | FK cascade |
| ai_usage_days | Daily AI message counter | unique(user_id, day) |
| wearable_connections | Health Connect / Apple Health status | unique(user_id, provider) |
| synced_health_records | Daily aggregates from wearables | **unique(user_id, provider, record_uid)** (upsert) |
| account_deletion_requests | Proof of erasure: sha256(user id) + status, no personal data | — |
| security_audit_events | Audit log with hashed user id | idx created_at |

## Retention & deletion

| Data | Retention |
|---|---|
| All user data | While the account exists. Deleted immediately on account deletion (cascade). |
| Progress photo objects | Deleted from storage on account deletion (service role) or when the user deletes a photo. |
| account_deletion_requests | Kept as proof of erasure (hash only). |
| security_audit_events, request logs | ≥ 1 year (DPDP Rules 2025 log-retention requirement), then purge — see PRIVACY_AND_COMPLIANCE.md. |
| Backups (Supabase PITR/daily) | Rotate per plan (e.g. 7–30 days); deleted users disappear from backups as they expire. |

## Client vs backend operations

| Operation | Where |
|---|---|
| Sign up / sign in / Google / reset password / session refresh | App ↔ Supabase Auth |
| Upload / view (signed URL) / delete own progress photos | App ↔ Supabase Storage (RLS-scoped) |
| Everything else (profile, workouts, XP, nutrition, goals, AI, export) | App ↔ FastAPI only |
| XP awards, PRs, achievements, streaks | Backend only (trusted) |
| Account deletion (auth user + storage cleanup) | Backend only (service role) |
| Schema changes | Alembic (backend) + `policies.sql` |
