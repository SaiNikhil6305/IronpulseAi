import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../checklist/data/checklist_repository.dart';
import '../../workouts/domain/split.dart';
import '../../workouts/domain/workout_models.dart';
import '../domain/reminder_planner.dart';
import 'notification_service.dart';

class NotificationPrefs {
  const NotificationPrefs({this.gymRemindersEnabled = true, this.offsets = const [20], this.checklistEnabled = false,
      this.weighInWeekday, this.weighInTime});
  final bool gymRemindersEnabled;
  final List<int> offsets;
  final bool checklistEnabled;
  final int? weighInWeekday;
  final String? weighInTime;

  factory NotificationPrefs.fromJson(Map<String, dynamic>? j) => j == null
      ? const NotificationPrefs()
      : NotificationPrefs(
          gymRemindersEnabled: j['gym_reminders_enabled'] != false,
          offsets: [for (final o in (j['reminder_offsets_min'] as List? ?? const [20])) (o as num).toInt()],
          checklistEnabled: j['checklist_reminders_enabled'] == true,
          weighInWeekday: (j['weigh_in_weekday'] as num?)?.toInt(),
          weighInTime: j['weigh_in_time'] as String?,
        );

  Map<String, dynamic> toJson() => {
        'gym_reminders_enabled': gymRemindersEnabled,
        'reminder_offsets_min': offsets,
        'checklist_reminders_enabled': checklistEnabled,
        'weigh_in_weekday': weighInWeekday,
        'weigh_in_time': weighInTime,
      };
}

final notificationPrefsProvider = Provider<NotificationPrefs>(
    (ref) => NotificationPrefs.fromJson(ref.watch(docProvider((Col.meta, Meta.notificationPrefs))).value));

/// Rebuilds every scheduled local notification from current data. Safe to call
/// repeatedly: deterministic ids replace existing notifications.
class ReminderSync {
  ReminderSync(this.ref);
  final Ref ref;
  static const _checklistIdsKey = 'reminders.checklist_ids';

  Future<int> resyncAll() async {
    final n = ref.read(notificationServiceProvider);
    final db = ref.read(localDbProvider);
    final prefsDoc = await db.getDoc(Col.meta, Meta.notificationPrefs);
    final prefs = NotificationPrefs.fromJson(prefsDoc);
    final schedDoc = await db.getDoc(Col.meta, Meta.schedule);
    // Read straight from storage: this runs at start-up before read models have loaded.
    final schedule = [
      for (final d in (schedDoc?['days'] as List? ?? const [])) ScheduleDay.fromJson(Map<String, dynamic>.from(d))
    ];
    final splitDoc = await db.getDoc(Col.meta, Meta.split);
    final history = <WorkoutSession>[];
    for (final d in await db.listDocs(Col.sessions)) {
      try {
        history.add(WorkoutSession.fromJson(d));
      } catch (_) {}
    }
    history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final count = await n.rescheduleGymReminders(prefs.gymRemindersEnabled
        ? planGymReminders(
            schedule: schedule,
            offsetsMinutes: prefs.offsets,
            history: history,
            split: splitDoc == null ? null : WorkoutSplit.fromJson(splitDoc),
          )
        : const []);
    await n.scheduleWeighIn(prefs.weighInWeekday, prefs.weighInTime);

    final sp = ref.read(prefsProvider);
    final previous = (sp.getStringList(_checklistIdsKey) ?? const []).toSet();
    final checklist = [for (final d in await db.listDocs(Col.checklistItems)) ChecklistItem.fromJson(d)];
    final items = prefs.checklistEnabled
        ? [
            for (final i in checklist)
              if (i.reminderTime != null && !i.paused) (id: i.id, name: i.name, hhmm: i.reminderTime!)
          ]
        : <({String id, String name, String hhmm})>[];
    await n.scheduleChecklist(items, previous);
    await sp.setStringList(_checklistIdsKey, [for (final i in items) i.id]);
    return count;
  }
}

final reminderSyncProvider = Provider<ReminderSync>((ref) => ReminderSync(ref));
