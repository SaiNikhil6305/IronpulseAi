# IronPulse

**Train Smart. Track Every Rep. Become Stronger.**

IronPulse is a Flutter fitness app for Android and iOS: fast gym-floor workout logging that works offline, custom
splits, previous-performance hints, XP and streaks, nutrition and habit tracking, goals and weight, progress
analytics, gym reminders, Health Connect import and **IronPulse AI** — backed by a FastAPI service on Supabase.

| | |
|---|---|
| App | Flutter 3.47 · Dart 3.13 · Riverpod 3 · GoRouter · Dio · sqflite · flutter_local_notifications · fl_chart · health |
| Backend | Python 3.13 · FastAPI · Pydantic 2 · SQLAlchemy 2 · Alembic |
| Platform | Supabase (Auth, Postgres with RLS, private Storage) · Google Sign-In · configurable AI provider |

Feature-by-feature status, what's tested and what still needs configuration: **[docs/STATUS.md](docs/STATUS.md)**.

## Quick start

```bash
# 1. App — runs without any backend in "device-only" mode
flutter pub get
flutter analyze && flutter test
flutter build apk --debug          # → build/app/outputs/flutter-apk/app-debug.apk

# 2. Backend
cd backend && pip install -r requirements-dev.txt && pytest -q
cp .env.example .env && uvicorn app.main:app --reload

# 3. Full app with accounts, sync and AI
cp config/app_config.example.json config/app_config.json   # public values only
flutter build apk --release --dart-define-from-file=config/app_config.json
```

Setup guides: [Auth (Supabase + Google)](docs/AUTH_SETUP.md) · [Deployment](docs/DEPLOYMENT.md) ·
[Android build & install](docs/ANDROID_BUILD.md) · [iOS build](docs/IOS_BUILD.md)

## Repository layout

```
lib/                 Flutter app (core/ + features/<name>/{data,domain,presentation})
test/, integration_test/
assets/data/exercises.json   exercise catalogue (identical copy of backend/app/data/exercises.json)
android/, ios/       platform projects (app id / bundle id: com.ironpulse.app)
backend/             FastAPI app, Alembic migrations, Supabase RLS SQL, tests, Dockerfile
config/              app_config.example.json (public build-time values)
docs/                architecture, schema, API, security, privacy, testing, builds, legal drafts
tool/                icon and license-inventory generators
.github/workflows/   CI (backend on SQLite + Postgres, Flutter analyze/test, release APK/AAB)
```

## Documentation

[Architecture](docs/ARCHITECTURE.md) · [Database schema](docs/DATABASE_SCHEMA.md) ·
[API](docs/API_SPECIFICATION.md) ([OpenAPI](docs/openapi.json)) · [Security](docs/SECURITY.md) ·
[Privacy & compliance](docs/PRIVACY_AND_COMPLIANCE.md) · [Testing](docs/TESTING.md) ·
[Notifications](docs/NOTIFICATIONS.md) · [Third-party services](docs/THIRD_PARTY_SERVICES.md) ·
[Dependency licenses](docs/DEPENDENCY_LICENSES.md) · [Incident response](docs/INCIDENT_RESPONSE.md) ·
[Privacy policy draft](docs/PRIVACY_POLICY.md) · [Terms draft](docs/TERMS.md)

## Safety

IronPulse and IronPulse AI give general fitness information, not medical advice. The AI is instructed never to
diagnose, recommend steroids, guarantee results or encourage unsafe lifting, and to refer pain or injury to a
qualified professional.
