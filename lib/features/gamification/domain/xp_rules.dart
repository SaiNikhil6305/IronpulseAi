import '../../../core/utils/units.dart';
import '../../workouts/domain/workout_models.dart';

/// Client-side mirror of backend/app/services/gamification.py.
///
/// The backend ledger is authoritative for signed-in users. This mirror is
/// used for instant feedback, offline display and device-only mode, and is
/// unit-tested against the same scenarios as the server.
class XpRules {
  const XpRules._();
  static const set = 10;
  static const workout = 25;
  static const checklist = 5;
  static const weighIn = 15;
  static const weeklyTarget = 30;
  static const maxSetsPerSession = 50;
  static const maxWorkoutBonusesPerDay = 2;

  static const levels = <(int, String)>[
    (0, 'Rookie'),
    (250, 'Gym Beginner'),
    (750, 'Consistent Lifter'),
    (1750, 'Iron Mind'),
    (3500, 'Gym Beast'),
    (6500, 'Elite Grinder'),
  ];

  static const achievements = <String, (String, String)>{
    'first_workout': ('First Workout', 'Complete your first workout.'),
    'sets_100': ('First 100 Sets', 'Complete 100 valid sets.'),
    'three_sessions': ('Three-Session Streak', 'Complete three workouts within seven days.'),
    'weekly_consistency': ('Seven-Day Consistency Challenge', 'Hit your weekly training target in a calendar week.'),
    'first_pr': ('First Personal Record', 'Beat your previous best on any exercise.'),
    'first_month': ('First Month of Training', 'Train for 30 days with at least 8 completed workouts.'),
  };
}

class LevelInfo {
  const LevelInfo({required this.level, required this.name, required this.totalXp, required this.floorXp,
      this.nextXp, this.nextName});
  final int level;
  final String name;
  final int totalXp;
  final int floorXp;
  final int? nextXp;
  final String? nextName;

  double get progress => nextXp == null ? 1 : (totalXp - floorXp) / (nextXp! - floorXp);
  int? get xpToNext => nextXp == null ? null : nextXp! - totalXp;

  factory LevelInfo.fromXp(int xp) {
    var idx = 0;
    for (var i = 0; i < XpRules.levels.length; i++) {
      if (xp >= XpRules.levels[i].$1) idx = i;
    }
    final next = idx + 1 < XpRules.levels.length ? XpRules.levels[idx + 1] : null;
    return LevelInfo(level: idx + 1, name: XpRules.levels[idx].$2, totalXp: xp, floorXp: XpRules.levels[idx].$1,
        nextXp: next?.$1, nextName: next?.$2);
  }

  factory LevelInfo.fromServer(Map<String, dynamic> j) => LevelInfo(
        level: (j['level'] as num).toInt(),
        name: j['name'] as String,
        totalXp: (j['total_xp'] as num).toInt(),
        floorXp: (j['level_floor_xp'] as num).toInt(),
        nextXp: (j['next_level_xp'] as num?)?.toInt(),
        nextName: j['next_level_name'] as String?,
      );
}

class StreakInfo {
  const StreakInfo({required this.current, required this.longest, required this.total, required this.weeklyTarget,
      required this.thisWeek});
  final int current;
  final int longest;
  final int total;
  final int weeklyTarget;
  final int thisWeek;

  String get explanation => 'Your streak counts consecutive weeks (Mon–Sun) with at least $weeklyTarget '
      'workout${weeklyTarget == 1 ? '' : 's'}. Rest days never break it, and the current week only counts '
      'once you hit your target — an unfinished week never resets you.';
}

/// Consistency streak in weeks; identical to the backend's compute_streaks.
StreakInfo computeStreaks(List<DateTime> workoutDays, int weeklyTarget, DateTime today) {
  final target = weeklyTarget < 1 ? 1 : weeklyTarget;
  final perWeek = <String, int>{};
  for (final d in workoutDays) {
    perWeek.update(Dates.weekKey(d), (v) => v + 1, ifAbsent: () => 1);
  }
  final met = {for (final e in perWeek.entries) if (e.value >= target) e.key};

  var current = 0;
  var cursor = DateTime.utc(today.year, today.month, today.day);
  if (met.contains(Dates.weekKey(cursor))) current++;
  cursor = cursor.subtract(const Duration(days: 7));
  while (met.contains(Dates.weekKey(cursor))) {
    current++;
    cursor = cursor.subtract(const Duration(days: 7));
  }

  var longest = 0;
  if (workoutDays.isNotEmpty) {
    final start = workoutDays.reduce((a, b) => a.isBefore(b) ? a : b);
    var c = DateTime.utc(start.year, start.month, start.day).subtract(Duration(days: start.weekday - 1));
    final end = DateTime.utc(today.year, today.month, today.day);
    var run = 0;
    while (!c.isAfter(end)) {
      if (met.contains(Dates.weekKey(c))) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
      c = c.add(const Duration(days: 7));
    }
  }
  return StreakInfo(
    current: current,
    longest: longest,
    total: workoutDays.length,
    weeklyTarget: target,
    thisWeek: perWeek[Dates.weekKey(today)] ?? 0,
  );
}

class PersonalRecord {
  const PersonalRecord({required this.exerciseRef, required this.exerciseName, required this.sessionId,
      required this.weightKg, required this.reps, required this.e1rm, required this.previousE1rm, required this.date});
  final String exerciseRef;
  final String exerciseName;
  final String sessionId;
  final double weightKg;
  final int reps;
  final double e1rm;
  final double previousE1rm;
  final DateTime date;
}

/// Chronological PR events: a session's best estimated 1RM beating all earlier sessions.
List<PersonalRecord> personalRecords(List<WorkoutSession> sessions) {
  final done = sessions.where((s) => s.isCompleted).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final best = <String, double>{};
  final out = <PersonalRecord>[];
  for (final s in done) {
    final sessionBest = <String, (double, WorkoutSet, SessionExercise)>{};
    for (final ex in s.exercises) {
      for (final st in ex.sets) {
        if (!st.isValid || st.weightKg == null || st.weightKg == 0 || st.reps == null || st.reps! > 12) continue;
        final e = epley1rm(st.weightKg!, st.reps!);
        final cur = sessionBest[ex.exerciseRef];
        if (cur == null || e > cur.$1) sessionBest[ex.exerciseRef] = (e, st, ex);
      }
    }
    for (final entry in sessionBest.entries) {
      final (e, st, ex) = entry.value;
      final prev = best[entry.key];
      if (prev != null && e > prev + 1e-6) {
        out.add(PersonalRecord(exerciseRef: entry.key, exerciseName: ex.exerciseName, sessionId: s.id,
            weightKg: st.weightKg!, reps: st.reps!, e1rm: e, previousE1rm: prev, date: s.startedAt));
      }
      best[entry.key] = prev == null || e > prev ? e : prev;
    }
  }
  return out;
}

/// XP for one session exactly as the server awards it (excluding the per-day bonus cap,
/// which depends on other sessions and is applied in [computeLocalXp]).
int sessionXp(WorkoutSession s, {bool workoutBonus = true}) {
  if (!s.isCompleted) return 0;
  final valid = s.validSets.length;
  final capped = valid > XpRules.maxSetsPerSession ? XpRules.maxSetsPerSession : valid;
  return capped * XpRules.set + (valid > 0 && workoutBonus ? XpRules.workout : 0);
}

class LocalXpResult {
  const LocalXpResult(this.total, this.breakdown, this.unlocked);
  final int total;
  final Map<String, int> breakdown;
  final Set<String> unlocked;
}

/// Full local XP ledger + achievements, mirroring the server's rules.
LocalXpResult computeLocalXp({
  required List<WorkoutSession> sessions,
  required int checklistCompletions,
  required List<DateTime> weighInDays,
  required int weeklyTarget,
}) {
  final done = sessions.where((s) => s.isCompleted && s.validSets.isNotEmpty).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  var setsXp = 0, workoutXp = 0;
  final bonusesPerDay = <String, int>{};
  for (final s in done) {
    setsXp += sessionXp(s, workoutBonus: false);
    final day = Dates.iso(s.startedAt.toLocal());
    final n = bonusesPerDay[day] ?? 0;
    if (n < XpRules.maxWorkoutBonusesPerDay) {
      workoutXp += XpRules.workout;
      bonusesPerDay[day] = n + 1;
    }
  }
  final days = [for (final s in done) Dates.dayOnly(s.startedAt.toLocal())];
  final perWeek = <String, int>{};
  for (final d in days) {
    perWeek.update(Dates.weekKey(d), (v) => v + 1, ifAbsent: () => 1);
  }
  final target = weeklyTarget < 1 ? 1 : weeklyTarget;
  final weeksMet = perWeek.values.where((n) => n >= target).length;
  final weighWeeks = {for (final d in weighInDays) Dates.weekKey(d)}.length;

  final breakdown = {
    'sets': setsXp,
    'workouts': workoutXp,
    'checklist': checklistCompletions * XpRules.checklist,
    'weigh_ins': weighWeeks * XpRules.weighIn,
    'weekly_targets': weeksMet * XpRules.weeklyTarget,
  };

  final unlocked = <String>{};
  if (done.isNotEmpty) unlocked.add('first_workout');
  if (done.fold<int>(0, (a, s) => a + s.validSets.length) >= 100) unlocked.add('sets_100');
  final sortedDays = List<DateTime>.of(days)..sort();
  for (var i = 0; i + 2 < sortedDays.length; i++) {
    if (sortedDays[i + 2].difference(sortedDays[i]).inDays < 7) {
      unlocked.add('three_sessions');
      break;
    }
  }
  if (weeksMet > 0) unlocked.add('weekly_consistency');
  if (personalRecords(sessions).isNotEmpty) unlocked.add('first_pr');
  if (sortedDays.isNotEmpty && sortedDays.last.difference(sortedDays.first).inDays >= 30 && sortedDays.length >= 8) {
    unlocked.add('first_month');
  }
  return LocalXpResult(breakdown.values.fold(0, (a, b) => a + b), breakdown, unlocked);
}
