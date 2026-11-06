# Testing

## Automated (run on every change; all passing on 2026-10-25)

```bash
cd backend && pytest -q                                   # SQLite
TEST_DATABASE_URL=postgresql+psycopg://…/ironpulse pytest -q   # against a migrated PostgreSQL
cd .. && flutter analyze && flutter test                  # unit + widget
flutter test integration_test/app_test.dart               # needs an emulator/phone (not run here)
```

### Backend — 34 tests (`backend/tests/`), passing on SQLite **and** PostgreSQL 16

| Area | Tests |
|---|---|
| Auth | missing token, wrong signature, expired token, wrong audience rejected |
| Validation | bad profile payload → 422 envelope; goal date order; schedule duplicate weekdays; reminder offsets |
| Authorization / isolation | user B can't read, overwrite (even with a newer snapshot), delete or list A's sessions/weights; export only own rows; photo path must be in own folder; AI conversation isolation; sync snapshot isolation |
| Idempotency & XP | session retried 3× → one session, XP once; re-opened/re-completed set no extra XP; implausible sets no XP; stale snapshot doesn't overwrite newer; discard removes XP; checklist toggled 5× → 5 XP; weigh-ins → once per week |
| Workouts | catalogue seeded/filterable; previous performance; PR + achievement detection; split change keeps history |
| Nutrition | meal CRUD, totals × quantity, missing values, estimates flag, entry update/delete |
| AI | scopes intersected with user authorisation; history stored; rate limit (4th/min → 429); daily limit; timeout → 504 (no fabricated reply); not configured → 503 |
| Account | deletion removes everything and reports `partial` when service role is absent; tokens never in logs |
| Wearables | aggregate upsert: insert, unchanged, updated — never duplicated |
| Rules | levels, streak weeks, unfinished week, missed week, Epley |

Plus migration checks: `alembic upgrade head` + `alembic check` (no drift) on PostgreSQL 16, and RLS lockdown
verified (`authenticated` role → permission denied).

### Flutter — 38 tests

| File | Covers |
|---|---|
| `test/unit/domain_test.dart` (22) | validators, unit conversion, ISO week parity with backend, set validity, XP rules incl. bonus cap, levels, streaks, PRs, split weekday assignment, today's plan (weekday / schedule override / rest / rotation), reminder planning (ids, offsets, midnight wrap, personalised text), nutrition totals, catalogue integrity (app asset == backend file, all preset/alternative refs exist), CSV export escaping, session JSON round trip |
| `test/unit/data_test.dart` (13) | SQLite docs CRUD + change events; outbox coalescing; failed ops kept & retryable; hydration keeps unsent docs; **active workout survives restart**; copy previous / reorder / replace / L-R; monotonic timestamps; rest timer persistence & notification; **offline queue → reconnect → uploaded exactly once**; rejection vs transient vs 404 handling with order preserved; device-only mode never queues; checklist idempotency + nutrition link; router redirects |
| `test/widget/app_flow_test.dart` (3) | unconfigured build shows what's missing (no fake Google button) and enables device-only mode; new user → onboarding; **home → Start workout → extra muscle group → logger → enter 40 × 10 → ✓ → persisted to SQLite**, bottom navigation, no fabricated insights |

The widget test caught and fixed real bugs: three layout overflows on a 1080×2400 phone and a 1-second timer
that kept running after leaving the workout screen.

## Manual device test plan (not yet executed — requires a phone and configured services)

**Install & core (device-only build)**
- [ ] APK installs on Android 8+; icon and name correct; dark theme; portrait
- [ ] Onboarding resumes after force-closing mid-way
- [ ] Each split preset previews and applies; custom split editor (rename, weekdays, reorder, add/remove)
- [ ] Start today's workout; extras prompt; log sets with keyboard; ✓ starts rest timer
- [ ] Lock the phone during rest → rest-complete notification arrives
- [ ] Swipe the app away mid-workout → reopen → "Resume" banner, all sets intact
- [ ] Finish → summary (volume labelled weight × reps), PR shown on a heavier session
- [ ] Previous-workout sheet on next launch; Repeat vs Start today's
- [ ] Nutrition: add/edit/delete, saved meals, copy yesterday, Open Food Facts search (online/offline)
- [ ] Checklist: tick/untick/undo; protein item adds a "From checklist" entry
- [ ] Goals, weight chart, progress photos (camera + gallery, hide, delete)
- [ ] Progress filters (7d/30d/3m/all/custom) on small and large screens
- [ ] Android back button behaviour on every screen; keyboard never hides inputs

**With backend** — see AUTH_SETUP.md checklist, plus:
- [ ] Two accounts on two phones: no cross-visibility
- [ ] Airplane mode workout → reconnect → server has it once; XP matches app
- [ ] AI: answers; rate limit message; delete conversation; scopes respected
- [ ] Export (JSON + CSV share sheet); delete account → can't sign in; data gone in Supabase

**Notifications** (see NOTIFICATIONS.md): permission denial path; reminders at 30/20/10/0 with app closed,
after reboot, across a DST change (set phone time zone); no duplicates after editing the schedule twice.

**Health Connect**: install prompt when missing; permission grant/deny; sync shows steps matching the Health
Connect app; disconnect with delete removes data.
