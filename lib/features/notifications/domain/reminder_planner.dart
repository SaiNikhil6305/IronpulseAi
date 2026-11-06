import '../../workouts/domain/split.dart';
import '../../workouts/domain/workout_models.dart';

/// A weekly repeating local notification.
class ReminderSpec {
  const ReminderSpec({required this.id, required this.weekday, required this.hour, required this.minute,
      required this.title, required this.body, this.payload});
  final int id;
  final int weekday; // ISO 1..7
  final int hour;
  final int minute;
  final String title;
  final String body;
  final String? payload;

  @override
  String toString() => 'Reminder#$id wd$weekday $hour:$minute "$body"';
}

class ReminderIds {
  const ReminderIds._();
  static const offsets = [30, 20, 10, 0];

  /// Deterministic ids mean re-scheduling replaces instead of duplicating.
  static int gym(int weekday, int offsetMinutes) => 100 + weekday * 10 + offsets.indexOf(offsetMinutes);
  static const gymRange = (110, 179);
  static const weighIn = 90;
  static const restTimer = 7001;
  static int checklist(String itemId) => 2000 + (itemId.hashCode.abs() % 1000);
}

/// Build gym reminders for the weekly schedule. Times are wall-clock in the
/// device's time zone, so daylight-saving changes keep "6 PM" at 6 PM.
List<ReminderSpec> planGymReminders({
  required List<ScheduleDay> schedule,
  required List<int> offsetsMinutes,
  required List<WorkoutSession> history,
  WorkoutSplit? split,
}) {
  final out = <ReminderSpec>[];
  final offsets = offsetsMinutes.where(ReminderIds.offsets.contains).toSet().toList()..sort((a, b) => b - a);
  for (final day in schedule) {
    if (day.isRestDay || day.timeLocal == null) continue;
    final parts = day.timeLocal!.split(':');
    final startMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    final dayName = day.workoutDayName ??
        split?.days.where((d) => d.weekdays.contains(day.weekday)).firstOrNull?.name;
    final label = dayName == null ? 'Your workout' : 'Your ${dayName.toLowerCase().endsWith('day') ? dayName : '$dayName Day'}';
    final last = dayName == null
        ? null
        : history.where((s) => s.isCompleted && s.workoutDayName == dayName).firstOrNull;
    final names = last == null ? const <String>[] : last.exercises.take(2).map((e) => e.exerciseName).toList();
    for (final off in offsets) {
      var m = startMin - off;
      var wd = day.weekday;
      if (m < 0) {
        m += 24 * 60;
        wd = wd == 1 ? 7 : wd - 1;
      }
      final body = off == 0
          ? '$label starts now. Let\'s get moving.'
          : '$label starts in $off minutes. Let\'s get moving.';
      final extra = names.isEmpty
          ? ''
          : ' Your previous session included ${names.join(' and ')}. Your workout history is ready.';
      out.add(ReminderSpec(
        id: ReminderIds.gym(day.weekday, off),
        weekday: wd,
        hour: m ~/ 60,
        minute: m % 60,
        title: 'IronPulse',
        body: body + extra,
        payload: 'route:/workout',
      ));
    }
  }
  return out;
}
