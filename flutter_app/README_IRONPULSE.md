# IronPulse - Flutter app (Phases 1-9)

## Install into your project (PowerShell)
cd C:\projects\Ironpulse
Expand-Archive "$env:USERPROFILE\Downloads\ironpulse_flutter.zip" -DestinationPath . -Force
flutter --version          # needs Flutter 3.38 or newer; if older: flutter upgrade --force
flutter pub get
dart run tool/setup_android.dart   # once: Android permissions + settings for reminders
flutter test
flutter run -d fd33a430

## What works now (offline, stored on the phone in SQLite)
- Onboarding (name, optional weight/height, experience, goal, weekly target)
- Split choice: Push/Pull/Legs, Muscle-group days, Upper/Lower, Full Body, Custom (rename, reorder, add/remove days and muscles)
- Home: today's workout, resume unfinished workout, previous-workout pop-up (Previous vs Today's split), level, XP, streak
- Extra muscle groups for one session only
- Workout logger: weight/reps per set, last session shown as hints, copy last session, add/remove sets,
  add/replace/remove exercises, rest timer (pause, +30s, skip, vibration), auto-save, summary with PRs
- Exercise library with search, filters, instructions, custom exercises
- XP ledger with unique ids (no farming), 6 levels, weekly streaks, achievements, personal bests, progress charts

## Phase 4 (new)
- Daily checklist: supplements / food / habits, quantity, optional protein & kcal, pause, edit, delete,
  14-day history, XP once per item per day, undo removes XP and any nutrition entry it created
- Nutrition: Morning / Afternoon / Night / Snacks, user-entered calories & macros, recent foods quick-fill,
  edit/delete, copy yesterday's meal, day switcher, 7-day average, optional targets (off by default)
- Weight: log weigh-ins (one per day), trend chart, +15 XP once per week
- Goals: 2/3/6/12 months, target weight and workout-count goals measured from real data

## Phase 5 (new)
- Gym schedule per weekday (time or rest day), shown on the Home "Today" card (bell icon top right)
- Reminders 30 / 20 / 10 min before and/or at start time, weekly, stable ids (no duplicates)
- Text uses your next split day and your real last session; tapping opens the workout
- Permission denial handled; test-notification button; reminders refresh after every workout
- Limitation: Android may deliver a few minutes late; aggressive battery savers (Realme etc.)
  can block them until IronPulse is set to "Allow background activity". Needs testing on your phone.

## Phase 6 (new) - IronPulse AI
- Chat with suggestion chips, history, copy, delete chat / delete all, clear errors with retry
- Server in ai_server/ (see ai_server/README.md): token auth, rate limits, size limits, timeouts,
  safety prompt (no diagnosis, no steroids, no dangerous lifting, no guarantees), no content logging
- Default model: free local Ollama on your PC, reached over USB (adb reverse) - nothing leaves your PC
- Sharing your training / nutrition summary is OFF by default; "Preview exactly what is sent" button
- Token kept in Android Keystore via flutter_secure_storage; chat history stays on the phone

## Phase 7 (new) - Wearables via Android Health Connect
- Watch icon on Home -> Wearables: install/connect Health Connect, sync last 7 days, disconnect (deletes imports)
- Reads steps (platform de-duplicated total), heart rate, resting heart rate, sleep - read-only
- Fitbit / Samsung / Wear OS / Mi Band data arrives through Health Connect; Apple Health planned; no raw Bluetooth
- Progress tab: 7-day averages card. Only daily summaries are stored, never raw samples
- AI chat now renders bold text, lists and headings
- Requires Android 8.0+ (minSdk 26); run `dart run tool/setup_android.dart` again

## Phase 8 (new) - Privacy & security
- Person icon on Home -> Profile & settings: edit profile (name, body, goal, weekly target, default rest timer)
  plus one place for split, schedule, targets, checklist, wearables, AI
- Privacy policy + Terms (drafts describing real behaviour), open-source licenses page
- "Your privacy choices": append-only record of every opt-in/out with policy version + time
- Export my data: full JSON + CSV (workouts, food, weight) via share sheet; tokens never exported
- Delete all my data (type DELETE): database, tokens, exports, reminders, Health Connect access
- docs/PRIVACY_AND_COMPLIANCE.md (DPDP Act 2023 + Rules 2025, GDPR), docs/SECURITY.md (review + incident
  response), docs/THIRD_PARTY_SERVICES.md (processor register), LICENSES_INVENTORY.md (103 packages)
- Before publishing: set contactEmail in lib/screens/legal.dart

## Phase 9 (new) - Accounts, Google Sign-In, cloud backup, release build
- Settings -> Account & cloud backup: email sign-up/sign-in with 6-digit email codes, password reset,
  Continue with Google (native, via Supabase signInWithIdToken), sign out, delete cloud account
- Cloud backup: one private row per user (Row Level Security), Back up now / Restore, automatic backup
  after each workout; restore is all-or-nothing (transaction) and tolerant of newer/older versions
- Without env.json the app runs exactly as before (offline) and says cloud is not set up
- supabase/schema.sql (table, RLS policies, delete_my_account), env.example.json, .gitignore
- Release signing from android/key.properties (setup_android.dart), verified with a signed build
- ci/ci.yml: GitHub Actions - tests, analyze, dependency audit, no-secrets check, APK build
- Setup guide: docs/PHASE9_SETUP.md

## Not built yet
- iOS build (needs a Mac + Apple developer account) - documented in docs/PHASE9_SETUP.md
- Login / Google Sign-In / cloud sync (needs backend + Supabase setup)
