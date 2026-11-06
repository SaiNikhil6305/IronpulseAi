# Implementation status (2026-10-25)

Legend: ✅ done · 🧪 covered by automated tests · 📱 verified on a real device · ⚙️ needs external configuration
· 🟡 partial · ⏳ planned

**No feature has been verified on a physical device yet** (no phone/emulator was available in the build
environment). Device verification is the next step — see TESTING.md.

| Feature | Status | Notes |
|---|---|---|
| Flutter app, dark design system, 5-tab navigation | ✅ 🧪 | `flutter analyze` clean |
| Android project & APK | ✅ | Debug and release APKs built and verified (release is debug-signed until you add a keystore) |
| iOS project | 🟡 | Configured (bundle id, plist, Google xcconfig); **not built** — needs macOS |
| Email sign-up/in, reset, session restore, sign-out | ✅ ⚙️ | Real Supabase Auth code; untested against a live project |
| Google Sign-In (native) | ✅ ⚙️ | `google_sign_in` 7 → ID token → Supabase; needs OAuth clients |
| Device-only mode (no backend) | ✅ 🧪 | Clearly labelled; real local data |
| Onboarding (all fields, skip, resume, edit later) | ✅ 🧪 | |
| Split selection: PPL, muscle-group, upper/lower, full body, custom editor | ✅ 🧪 | History never deleted on change |
| Exercise library (40 exercises, search, filters, favourites, custom, alternatives, history) | ✅ 🧪 | Demo video per exercise (public-domain photos + IronPulse muscle map & best-angle gauge) |
| Extra muscle groups per session | ✅ 🧪 | |
| Workout logger (sets, RPE, duration/distance, L/R, add/remove/reorder/replace, notes, copy previous) | ✅ 🧪 | |
| Workout timer pause/resume, rest timer (sound/vibration/skip/±15 s) | ✅ 🧪 | Background alert via local notification |
| Crash/close-safe unfinished workouts | ✅ 🧪 | |
| Offline queue, retry, idempotency, conflict policy | ✅ 🧪 | |
| Workout summary, history, previous-workout pop-up | ✅ 🧪 | |
| XP ledger, levels, achievements, PRs, streaks (server-validated) | ✅ 🧪 | Client mirror shows "pending sync" |
| Supplement & habit checklist | ✅ 🧪 | |
| Nutrition tracker (meals, saved meals, recent, copy yesterday, targets, weekly avg) | ✅ 🧪 | Open Food Facts search (crowd-sourced, labelled) |
| Optional food photo | ⏳ | Not implemented |
| Goals, weekly weigh-in, weight chart | ✅ 🧪 | |
| Progress photos (private) | ✅ ⚙️ | Local storage; private Supabase bucket when signed in |
| Progress analytics + insights | ✅ 🧪 | Insights only with enough data |
| IronPulse AI (backend proxy, limits, scopes, history, delete) | ✅ 🧪 ⚙️ | Provider mocked in tests; needs `AI_API_KEY` |
| Gym schedule & local reminders | ✅ 🧪 | Delivery with app closed not yet device-verified |
| Health Connect integration | ✅ ⚙️ | Read-only daily aggregates; not device-tested. Apple Health code path untested |
| Fitbit API / Wear OS app / generic Bluetooth | ⏳ | Shown as unavailable in-app |
| Settings, export (JSON + CSV), account deletion | ✅ 🧪 | |
| Backend API (57 operations), Alembic migration, RLS SQL | ✅ 🧪 | Tested on SQLite and PostgreSQL 16 |
| Docs, legal drafts, CI | ✅ | Legal drafts not lawyer-reviewed |
| Sign in with Apple | ⏳ | Required before App Store submission |
| Error-tracking SDK (Sentry etc.) | ⏳ | JSON logs only |
| Moving device-only data into a new account | ⏳ | Export is available; automatic migration not implemented |
| Languages other than English | ⏳ | |

## Remaining external configuration

1. Supabase project (URL, anon key, service role key, DB URL) → run migrations + `policies.sql`.
2. Google Cloud OAuth: consent screen, web/Android(SHA-1)/iOS clients; Supabase Google provider.
3. Deploy the backend (HTTPS) and set `API_BASE_URL`.
4. AI provider key and model (`AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL`).
5. Android upload keystore (`android/key.properties`) and Play Console app.
6. Apple Developer account, macOS build, HealthKit capability.
7. Legal: entity name, contacts, grievance officer, lawyer review, hosted privacy policy + deletion URL.

## Known limitations

* In-process API rate limiter (use Redis when running multiple instances).
* Reminders use inexact alarms (may be minutes late); OEM battery savers can block them.
* Health Connect history limited to 30 days by default (app imports the last 7 days).
* Last-write-wins for concurrent edits of the same workout on two devices.
* Exercise library is bundled in the app (same file the backend seeds), so new exercises need an app update.
