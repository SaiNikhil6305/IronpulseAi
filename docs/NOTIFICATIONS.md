# Notifications & reminders

All reminders are **local notifications** scheduled on the phone with `flutter_local_notifications`
(no server push). Implemented:

| Reminder | Schedule | Notes |
|---|---|---|
| Gym reminders | Weekly per scheduled day, 30/20/10/0 min before (any combination) | Text names the planned day and the last session's first exercises, e.g. "Your Push Day starts in 20 minutes… Your previous session included Bench Press and Incline Dumbbell Press." Tapping opens the Workout tab. |
| Weekly weigh-in | Chosen weekday + time | Opens the weight screen. |
| Checklist items | Daily at the item's time (if checklist reminders are on) | Opening never ticks the item. |
| Rest timer | When the rest period ends | Sound / vibration per settings; works with the app in the background. |

**No duplicates:** each reminder has a deterministic id (`100 + weekday*10 + offset index`). Rescheduling
cancels the whole id range and re-creates it, and runs at sign-in, app resume, and after schedule/checklist
changes (unit-tested in `test/unit/domain_test.dart`).

**Time zones / DST:** reminders are scheduled at wall-clock time in the device's IANA zone
(`flutter_timezone` + `timezone`) with `matchDateTimeComponents`, so 6 PM stays 6 PM across daylight-saving
changes. A time-zone change is picked up the next time the app resumes.

**Permissions:** Android 13+ asks for `POST_NOTIFICATIONS` when the user saves a schedule with reminders.
If denied, the schedule still works in-app and the screen shows *Allow* / *Open settings*.

## OS limitations (not yet verified on physical devices)

* Reminders use **inexact** alarms (`inexactAllowWhileIdle`) to avoid the restricted exact-alarm permission:
  Android may deliver them several minutes late in Doze.
* Some manufacturers (Xiaomi, Oppo/Realme, Vivo, Samsung "sleeping apps", OnePlus) kill background work for
  battery saving. If reminders don't arrive, set IronPulse's battery usage to *Unrestricted*.
* Force-stopping the app cancels its alarms until it is opened again. Rebooting is handled (boot receiver).
* iOS limits an app to 64 pending local notifications; IronPulse schedules at most 28 gym + 1 weigh-in +
  checklist reminders.

**Do not assume reminders arrive while the app is closed** until the device test plan in TESTING.md has
been run on the target phones.
