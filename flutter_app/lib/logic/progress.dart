// Pure progress logic: levels, weekly streaks, dates. No database access, easy to unit test.

class Level {
  final String name;
  final int minXp;
  const Level(this.name, this.minXp);
}

const levels = <Level>[
  Level('Rookie', 0),
  Level('Gym Beginner', 250),
  Level('Consistent Lifter', 750),
  Level('Iron Mind', 1500),
  Level('Gym Beast', 3000),
  Level('Elite Grinder', 6000),
];

class LevelInfo {
  final Level current;
  final Level? next;
  final int xp;
  const LevelInfo(this.current, this.next, this.xp);

  double get progress =>
      next == null ? 1 : ((xp - current.minXp) / (next!.minXp - current.minXp)).clamp(0.0, 1.0);
  int get xpToNext => next == null ? 0 : next!.minXp - xp;
}

LevelInfo levelFor(int xp) {
  var i = 0;
  while (i + 1 < levels.length && xp >= levels[i + 1].minXp) {
    i++;
  }
  return LevelInfo(levels[i], i + 1 < levels.length ? levels[i + 1] : null, xp);
}

DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String weekKey(DateTime d) {
  final m = weekStart(d);
  return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

class StreakInfo {
  final int current, longest, thisWeek, target;
  const StreakInfo(this.current, this.longest, this.thisWeek, this.target);
}

/// A streak counts consecutive weeks (Mon-Sun) in which the weekly target was met.
/// Rest days never break it, and the current week never breaks it while still in progress.
StreakInfo streaks(List<DateTime> sessions, int target, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final counts = <String, int>{};
  for (final d in sessions) {
    counts.update(weekKey(d), (v) => v + 1, ifAbsent: () => 1);
  }
  bool met(DateTime w) => (counts[weekKey(w)] ?? 0) >= target;

  final thisWeek = weekStart(today);
  var current = 0;
  var w = met(thisWeek) ? thisWeek : thisWeek.subtract(const Duration(days: 7));
  while (met(w)) {
    current++;
    w = w.subtract(const Duration(days: 7));
  }

  var longest = 0;
  if (sessions.isNotEmpty) {
    final first = sessions.reduce((a, b) => a.isBefore(b) ? a : b);
    var run = 0;
    for (var x = weekStart(first); !x.isAfter(thisWeek); x = x.add(const Duration(days: 7))) {
      run = met(x) ? run + 1 : 0;
      if (run > longest) longest = run;
    }
  }
  return StreakInfo(current, longest, counts[weekKey(today)] ?? 0, target);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String fmtDate(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

String fmtDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class Achievement {
  final String title, description;
  final bool unlocked;
  const Achievement(this.title, this.description, this.unlocked);
}

List<Achievement> achievements({required int workouts, required int sets, required int longestStreak, required int prs, required DateTime? firstWorkout, DateTime? now}) {
  final today = now ?? DateTime.now();
  return [
    Achievement('First Workout', 'Finish your first session', workouts >= 1),
    Achievement('First 100 Sets', 'Complete 100 sets', sets >= 100),
    Achievement('Three-Week Streak', 'Hit your weekly target 3 weeks in a row', longestStreak >= 3),
    Achievement('First Personal Record', 'Beat your best weight on any exercise', prs >= 1),
    Achievement('First Month of Training', 'Keep training 30 days after your first session',
        firstWorkout != null && today.difference(firstWorkout).inDays >= 30 && workouts >= 8),
    Achievement('25 Workouts', 'Finish 25 sessions', workouts >= 25),
  ];
}
