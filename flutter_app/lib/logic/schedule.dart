// Pure reminder planning: turns a weekly gym schedule + reminder offsets into weekly alarms.

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const reminderOffsets = [30, 20, 10, 0];

class PlannedReminder {
  /// Stable id: one per (gym day, offset). Re-planning reuses ids, so reminders never duplicate.
  final int id;
  final int weekday; // 1 = Monday ... 7 = Sunday (day the reminder fires)
  final int hour, minute;
  final int gymWeekday;
  final int offset;
  const PlannedReminder(this.id, this.weekday, this.hour, this.minute, this.gymWeekday, this.offset);
}

/// [schedule] maps weekday (1-7) to minutes after midnight, or null for a rest day.
List<PlannedReminder> planReminders(Map<int, int?> schedule, Iterable<int> offsets) {
  final out = <PlannedReminder>[];
  final uniq = offsets.toSet().toList()..sort((a, b) => b.compareTo(a));
  for (final e in schedule.entries) {
    final start = e.value;
    if (start == null) continue;
    for (final off in uniq) {
      var m = start - off;
      var wd = e.key;
      if (m < 0) {
        // e.g. 00:10 gym with a 30-minute reminder fires the previous evening.
        m += 24 * 60;
        wd = wd == 1 ? 7 : wd - 1;
      }
      out.add(PlannedReminder(e.key * 100 + off, wd, m ~/ 60, m % 60, e.key, off));
    }
  }
  return out;
}

/// Next DateTime on [weekday] at [hour]:[minute] strictly after [now] (same week if still ahead).
DateTime nextWeekly(DateTime now, int weekday, int hour, int minute) {
  var d = DateTime(now.year, now.month, now.day, hour, minute);
  var add = (weekday - now.weekday) % 7;
  d = d.add(Duration(days: add));
  if (!d.isAfter(now)) d = d.add(const Duration(days: 7));
  return d;
}

String fmtClock(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String reminderText(String dayName, int offset, List<String> lastExercises) {
  final when = offset == 0 ? 'starts now' : 'starts in $offset minutes';
  final head = 'Your $dayName $when.${offset == 0 ? '' : " Let's get moving."}';
  if (lastExercises.isEmpty) return head;
  return '$head Last time: ${lastExercises.take(2).join(' and ')}. Your history is ready.';
}
