import 'workout_models.dart';

class TemplateExercise {
  const TemplateExercise({required this.exerciseRef, this.targetSets = 3, this.targetReps});
  final String exerciseRef;
  final int targetSets;
  final String? targetReps;

  factory TemplateExercise.fromJson(Map<String, dynamic> j) => TemplateExercise(
        exerciseRef: j['exercise_ref'] as String,
        targetSets: (j['target_sets'] as num?)?.toInt() ?? 3,
        targetReps: j['target_reps'] as String?,
      );

  Map<String, dynamic> toJson() => {'exercise_ref': exerciseRef, 'target_sets': targetSets, 'target_reps': targetReps};
}

class SplitDay {
  const SplitDay({required this.name, this.muscleGroups = const [], this.weekdays = const [], this.exercises = const []});
  final String name;
  final List<String> muscleGroups;
  final List<int> weekdays; // ISO 1=Mon..7=Sun
  final List<TemplateExercise> exercises;

  factory SplitDay.fromJson(Map<String, dynamic> j) => SplitDay(
        name: j['name'] as String,
        muscleGroups: [for (final m in (j['muscle_groups'] as List? ?? const [])) '$m'],
        weekdays: [for (final d in (j['weekdays'] as List? ?? const [])) (d as num).toInt()],
        exercises: [
          for (final t in (j['template_exercises'] as List? ?? const []))
            TemplateExercise.fromJson(Map<String, dynamic>.from(t))
        ],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'muscle_groups': muscleGroups,
        'weekdays': weekdays,
        'template_exercises': [for (final e in exercises) e.toJson()],
      };

  SplitDay copyWith({String? name, List<String>? muscleGroups, List<int>? weekdays, List<TemplateExercise>? exercises}) =>
      SplitDay(
        name: name ?? this.name,
        muscleGroups: muscleGroups ?? this.muscleGroups,
        weekdays: weekdays ?? this.weekdays,
        exercises: exercises ?? this.exercises,
      );
}

class WorkoutSplit {
  const WorkoutSplit({required this.id, required this.name, required this.splitType, required this.days});
  final String id;
  final String name;
  final String splitType; // ppl | bro | upper_lower | full_body | custom
  final List<SplitDay> days;

  factory WorkoutSplit.fromJson(Map<String, dynamic> j) => WorkoutSplit(
        id: j['id'] as String,
        name: j['name'] as String,
        splitType: j['split_type'] as String,
        days: [for (final d in (j['days'] as List? ?? const [])) SplitDay.fromJson(Map<String, dynamic>.from(d))],
      );

  Map<String, dynamic> toApi() =>
      {'name': name, 'split_type': splitType, 'days': [for (final d in days) d.toJson()]};

  Map<String, dynamic> toJson() => {'id': id, 'is_active': true, ...toApi()};

  WorkoutSplit copyWith({String? name, List<SplitDay>? days}) =>
      WorkoutSplit(id: id, name: name ?? this.name, splitType: splitType, days: days ?? this.days);
}

TemplateExercise _t(String ref, [int sets = 3, String reps = '8-12']) =>
    TemplateExercise(exerciseRef: ref, targetSets: sets, targetReps: reps);

class SplitPreset {
  const SplitPreset(this.type, this.title, this.subtitle, this.days);
  final String type;
  final String title;
  final String subtitle;
  final List<SplitDay> days;
}

final splitPresets = <SplitPreset>[
  SplitPreset('ppl', 'Push / Pull / Legs', 'Three focused days you can run 3 or 6 times a week.', [
    SplitDay(name: 'Push', muscleGroups: const ['chest', 'shoulders', 'triceps'], exercises: [
      _t('barbell-bench-press', 3, '6-10'),
      _t('incline-dumbbell-press'),
      _t('shoulder-press'),
      _t('dumbbell-lateral-raise', 3, '12-15'),
      _t('cable-pushdown', 3, '10-12'),
      _t('overhead-cable-extension', 2, '10-12'),
    ]),
    SplitDay(name: 'Pull', muscleGroups: const ['back', 'rear_delts', 'biceps', 'traps'], exercises: [
      _t('lat-pulldown'),
      _t('seated-cable-row'),
      _t('chest-supported-row'),
      _t('reverse-pec-deck', 3, '12-15'),
      _t('dumbbell-curl', 3, '10-12'),
      _t('hammer-curl', 2, '10-12'),
      _t('dumbbell-shrug', 2, '10-15'),
    ]),
    SplitDay(name: 'Legs', muscleGroups: const ['quads', 'hamstrings', 'glutes', 'calves'], exercises: [
      _t('back-squat', 3, '6-10'),
      _t('romanian-deadlift'),
      _t('leg-press', 3, '10-12'),
      _t('leg-curl', 3, '10-12'),
      _t('leg-extension', 2, '12-15'),
      _t('calf-raise', 3, '10-15'),
    ]),
  ]),
  SplitPreset('bro', 'Muscle-group days', 'One main muscle group per session.', [
    SplitDay(name: 'Chest', muscleGroups: const ['chest'], exercises: [
      _t('barbell-bench-press', 4, '6-10'), _t('incline-dumbbell-press'), _t('machine-chest-press'), _t('cable-fly', 3, '12-15'),
    ]),
    SplitDay(name: 'Back', muscleGroups: const ['back'], exercises: [
      _t('pull-up', 3, 'AMRAP'), _t('lat-pulldown'), _t('seated-cable-row'), _t('one-arm-dumbbell-row'),
    ]),
    SplitDay(name: 'Shoulders', muscleGroups: const ['shoulders', 'rear_delts'], exercises: [
      _t('shoulder-press'), _t('dumbbell-lateral-raise', 4, '12-15'), _t('cable-lateral-raise', 3, '12-15'),
      _t('reverse-pec-deck', 3, '12-15'),
    ]),
    SplitDay(name: 'Arms', muscleGroups: const ['biceps', 'triceps'], exercises: [
      _t('dumbbell-curl'), _t('cable-pushdown'), _t('preacher-curl'), _t('overhead-cable-extension'), _t('hammer-curl'),
    ]),
    SplitDay(name: 'Legs', muscleGroups: const ['quads', 'hamstrings', 'glutes', 'calves'], exercises: [
      _t('back-squat', 4, '6-10'), _t('leg-press'), _t('romanian-deadlift'), _t('leg-curl'), _t('calf-raise', 4, '10-15'),
    ]),
    SplitDay(name: 'Abs & core', muscleGroups: const ['core'], exercises: [
      _t('cable-crunch', 3, '12-15'), _t('hanging-knee-raise', 3, '10-15'), _t('plank', 3, '30-60s'),
    ]),
  ]),
  SplitPreset('upper_lower', 'Upper / Lower', 'Alternate upper- and lower-body sessions, 4 days a week.', [
    SplitDay(name: 'Upper A', muscleGroups: const ['chest', 'back', 'shoulders', 'biceps', 'triceps'], exercises: [
      _t('barbell-bench-press', 3, '6-10'), _t('seated-cable-row'), _t('shoulder-press'), _t('lat-pulldown'),
      _t('dumbbell-curl', 2, '10-12'), _t('cable-pushdown', 2, '10-12'),
    ]),
    SplitDay(name: 'Lower A', muscleGroups: const ['quads', 'hamstrings', 'glutes', 'calves'], exercises: [
      _t('back-squat', 3, '6-10'), _t('romanian-deadlift'), _t('leg-extension'), _t('calf-raise', 3, '10-15'),
    ]),
    SplitDay(name: 'Upper B', muscleGroups: const ['chest', 'back', 'shoulders', 'biceps', 'triceps'], exercises: [
      _t('incline-dumbbell-press'), _t('chest-supported-row'), _t('dumbbell-lateral-raise', 3, '12-15'),
      _t('pull-up', 3, 'AMRAP'), _t('hammer-curl', 2, '10-12'), _t('overhead-cable-extension', 2, '10-12'),
    ]),
    SplitDay(name: 'Lower B', muscleGroups: const ['quads', 'hamstrings', 'glutes', 'calves', 'core'], exercises: [
      _t('leg-press'), _t('hip-thrust'), _t('leg-curl'), _t('seated-calf-raise', 3, '12-15'), _t('cable-crunch', 3, '12-15'),
    ]),
  ]),
  SplitPreset('full_body', 'Full Body', 'Train every major muscle group each session, 2–3 days a week.', [
    SplitDay(name: 'Full Body A', muscleGroups: const ['quads', 'chest', 'back', 'shoulders', 'core'], exercises: [
      _t('back-squat', 3, '6-10'), _t('barbell-bench-press', 3, '6-10'), _t('seated-cable-row'),
      _t('dumbbell-lateral-raise', 2, '12-15'), _t('plank', 2, '30-60s'),
    ]),
    SplitDay(name: 'Full Body B', muscleGroups: const ['hamstrings', 'chest', 'back', 'arms'], exercises: [
      _t('romanian-deadlift'), _t('incline-dumbbell-press'), _t('lat-pulldown'), _t('dumbbell-curl', 2, '10-12'),
      _t('cable-pushdown', 2, '10-12'),
    ]),
    SplitDay(name: 'Full Body C', muscleGroups: const ['quads', 'glutes', 'shoulders', 'back', 'calves'], exercises: [
      _t('leg-press'), _t('shoulder-press'), _t('chest-supported-row'), _t('hip-thrust'), _t('calf-raise', 3, '10-15'),
    ]),
  ]),
  const SplitPreset('custom', 'Custom Split', 'Build your own schedule, days and exercises.', [
    SplitDay(name: 'Day 1'),
  ]),
];

/// Spread split days over the user's preferred training days (or a sensible default).
List<SplitDay> assignWeekdays(List<SplitDay> days, List<int> trainingDays) {
  final slots = trainingDays.isNotEmpty
      ? (List<int>.of(trainingDays)..sort())
      : switch (days.length) {
          1 => [1, 3, 5],
          2 => [1, 2, 4, 5],
          3 => [1, 3, 5],
          4 => [1, 2, 4, 5],
          5 => [1, 2, 3, 4, 5],
          _ => [1, 2, 3, 4, 5, 6],
        };
  final assigned = [for (final _ in days) <int>[]];
  for (var i = 0; i < slots.length; i++) {
    assigned[i % days.length].add(slots[i]);
  }
  return [for (var i = 0; i < days.length; i++) days[i].copyWith(weekdays: assigned[i])];
}

class ScheduleDay {
  const ScheduleDay({required this.weekday, this.isRestDay = false, this.timeLocal, this.workoutDayName});
  final int weekday;
  final bool isRestDay;
  final String? timeLocal; // HH:MM
  final String? workoutDayName;

  factory ScheduleDay.fromJson(Map<String, dynamic> j) => ScheduleDay(
        weekday: (j['weekday'] as num).toInt(),
        isRestDay: j['is_rest_day'] == true,
        timeLocal: j['time_local'] as String?,
        workoutDayName: j['workout_day_name'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'weekday': weekday, 'is_rest_day': isRestDay, 'time_local': timeLocal, 'workout_day_name': workoutDayName};

  ScheduleDay copyWith({bool? isRestDay, Object? timeLocal = _k, Object? workoutDayName = _k}) => ScheduleDay(
        weekday: weekday,
        isRestDay: isRestDay ?? this.isRestDay,
        timeLocal: identical(timeLocal, _k) ? this.timeLocal : timeLocal as String?,
        workoutDayName: identical(workoutDayName, _k) ? this.workoutDayName : workoutDayName as String?,
      );
  static const _k = Object();
}

class TodayPlan {
  const TodayPlan({this.day, this.isRestDay = false, this.time, this.reason});
  final SplitDay? day;
  final bool isRestDay;
  final String? time;
  final String? reason;
}

/// Decide today's planned session from the gym schedule, split weekdays or rotation.
TodayPlan planForToday({
  required WorkoutSplit? split,
  required List<WorkoutSession> history,
  required List<ScheduleDay> schedule,
  required DateTime now,
}) {
  if (split == null || split.days.isEmpty) return const TodayPlan(reason: 'No split selected');
  final wd = now.weekday;
  final sched = schedule.where((s) => s.weekday == wd).firstOrNull;
  if (sched != null) {
    if (sched.isRestDay) return TodayPlan(isRestDay: true, reason: 'Scheduled rest day');
    if (sched.workoutDayName != null) {
      final d = split.days.where((x) => x.name == sched.workoutDayName).firstOrNull;
      if (d != null) return TodayPlan(day: d, time: sched.timeLocal);
    }
  }
  final hasWeekdays = split.days.any((d) => d.weekdays.isNotEmpty);
  if (hasWeekdays) {
    final d = split.days.where((x) => x.weekdays.contains(wd)).firstOrNull;
    if (d == null) return TodayPlan(isRestDay: true, time: sched?.timeLocal, reason: 'Rest day in your split');
    return TodayPlan(day: d, time: sched?.timeLocal);
  }
  // Rotation: the day after the most recent completed split day.
  final done = history.where((s) => s.isCompleted).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  for (final s in done) {
    final idx = split.days.indexWhere((d) => d.name == s.workoutDayName);
    if (idx >= 0) return TodayPlan(day: split.days[(idx + 1) % split.days.length], time: sched?.timeLocal);
  }
  return TodayPlan(day: split.days.first, time: sched?.timeLocal);
}

/// Exercises suggested for optional extra muscle groups ("Want to train anything extra today?").
const extraGroupExercises = <String, List<String>>{
  'traps': ['dumbbell-shrug', 'farmers-carry'],
  'forearms': ['wrist-curl', 'reverse-wrist-curl', 'farmers-carry'],
  'core': ['cable-crunch', 'hanging-knee-raise', 'plank'],
  'calves': ['calf-raise', 'seated-calf-raise'],
};
