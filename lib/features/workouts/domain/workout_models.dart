import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();
double? _d(Object? v) => (v as num?)?.toDouble();
int? _i(Object? v) => (v as num?)?.toInt();

class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.position,
    this.side,
    this.weightKg,
    this.reps,
    this.rpe,
    this.durationS,
    this.distanceM,
    this.completed = false,
    this.completedAt,
  });

  final String id;
  final int position;
  final String? side; // left | right | null
  final double? weightKg;
  final int? reps;
  final double? rpe;
  final int? durationS;
  final double? distanceM;
  final bool completed;
  final DateTime? completedAt;

  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
        id: j['id'] as String,
        position: _i(j['position']) ?? 0,
        side: j['side'] as String?,
        weightKg: _d(j['weight_kg']),
        reps: _i(j['reps']),
        rpe: _d(j['rpe']),
        durationS: _i(j['duration_s']),
        distanceM: _d(j['distance_m']),
        completed: j['completed'] == true,
        completedAt: _dt(j['completed_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'position': position,
        'side': side,
        'weight_kg': weightKg,
        'reps': reps,
        'rpe': rpe,
        'duration_s': durationS,
        'distance_m': distanceM,
        'completed': completed,
        'completed_at': completedAt?.toUtc().toIso8601String(),
      };

  static const _keep = Object();

  WorkoutSet copyWith({
    int? position,
    Object? side = _keep,
    Object? weightKg = _keep,
    Object? reps = _keep,
    Object? rpe = _keep,
    Object? durationS = _keep,
    Object? distanceM = _keep,
    bool? completed,
    Object? completedAt = _keep,
  }) =>
      WorkoutSet(
        id: id,
        position: position ?? this.position,
        side: identical(side, _keep) ? this.side : side as String?,
        weightKg: identical(weightKg, _keep) ? this.weightKg : weightKg as double?,
        reps: identical(reps, _keep) ? this.reps : reps as int?,
        rpe: identical(rpe, _keep) ? this.rpe : rpe as double?,
        durationS: identical(durationS, _keep) ? this.durationS : durationS as int?,
        distanceM: identical(distanceM, _keep) ? this.distanceM : distanceM as double?,
        completed: completed ?? this.completed,
        completedAt: identical(completedAt, _keep) ? this.completedAt : completedAt as DateTime?,
      );

  /// Mirrors the backend's is_valid_set: only completed, plausible sets count.
  bool get isValid {
    if (!completed) return false;
    final w = weightKg;
    if (w != null && (w < 0 || w > 500)) return false;
    final r = reps;
    final repsOk = r != null && r >= 1 && r <= 100;
    final durOk = durationS != null && durationS! >= 1 && durationS! <= 7200;
    final distOk = distanceM != null && distanceM! >= 1 && distanceM! <= 10000;
    if (r != null && !repsOk) return false;
    return repsOk || durOk || distOk;
  }

  double get volumeKg => (completed && weightKg != null && reps != null) ? weightKg! * reps! : 0;
}

class SessionExercise {
  const SessionExercise({
    required this.id,
    required this.exerciseRef,
    required this.exerciseName,
    required this.position,
    this.notes,
    this.sets = const [],
  });

  final String id;
  final String exerciseRef;
  final String exerciseName;
  final int position;
  final String? notes;
  final List<WorkoutSet> sets;

  factory SessionExercise.fromJson(Map<String, dynamic> j) => SessionExercise(
        id: j['id'] as String,
        exerciseRef: j['exercise_ref'] as String,
        exerciseName: j['exercise_name'] as String,
        position: _i(j['position']) ?? 0,
        notes: j['notes'] as String?,
        sets: [for (final s in (j['sets'] as List? ?? const [])) WorkoutSet.fromJson(Map<String, dynamic>.from(s))]
          ..sort((a, b) => a.position.compareTo(b.position)),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'exercise_ref': exerciseRef,
        'exercise_name': exerciseName,
        'position': position,
        'notes': notes,
        'sets': [for (final s in sets) s.toJson()],
      };

  SessionExercise copyWith({int? position, String? notes, List<WorkoutSet>? sets, String? exerciseRef,
          String? exerciseName}) =>
      SessionExercise(
        id: id,
        exerciseRef: exerciseRef ?? this.exerciseRef,
        exerciseName: exerciseName ?? this.exerciseName,
        position: position ?? this.position,
        notes: notes ?? this.notes,
        sets: sets ?? this.sets,
      );

  List<WorkoutSet> get completedSets => sets.where((s) => s.completed).toList();
}

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.name,
    this.workoutDayName,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.extraMuscleGroups = const [],
    this.notes,
    required this.clientUpdatedAt,
    this.exercises = const [],
    this.pausedAt,
    this.pausedTotalS = 0,
  });

  final String id;
  final String name;
  final String? workoutDayName;
  final String status; // in_progress | completed | discarded
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<String> extraMuscleGroups;
  final String? notes;
  final DateTime clientUpdatedAt;
  final List<SessionExercise> exercises;

  // Local-only workout-timer state (not sent to the server).
  final DateTime? pausedAt;
  final int pausedTotalS;

  bool get inProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isPaused => pausedAt != null;

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        id: j['id'] as String,
        name: j['name'] as String,
        workoutDayName: j['workout_day_name'] as String?,
        status: j['status'] as String,
        startedAt: _dt(j['started_at'])!,
        endedAt: _dt(j['ended_at']),
        extraMuscleGroups: [for (final m in (j['extra_muscle_groups'] as List? ?? const [])) '$m'],
        notes: j['notes'] as String?,
        clientUpdatedAt: _dt(j['client_updated_at']) ?? _dt(j['started_at'])!,
        exercises: [
          for (final e in (j['exercises'] as List? ?? const [])) SessionExercise.fromJson(Map<String, dynamic>.from(e))
        ]..sort((a, b) => a.position.compareTo(b.position)),
        pausedAt: _dt(j['paused_at']),
        pausedTotalS: _i(j['paused_total_s']) ?? 0,
      );

  /// Payload for PUT /v1/sessions/{id}.
  Map<String, dynamic> toApi() => {
        'name': name,
        'workout_day_name': workoutDayName,
        'status': status,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'extra_muscle_groups': extraMuscleGroups,
        'notes': notes,
        'client_updated_at': clientUpdatedAt.toUtc().toIso8601String(),
        'exercises': [for (final e in exercises) e.toJson()],
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toApi(),
        'paused_at': pausedAt?.toUtc().toIso8601String(),
        'paused_total_s': pausedTotalS,
      };

  static const _keep = Object();

  WorkoutSession copyWith({
    String? name,
    String? status,
    Object? endedAt = _keep,
    List<String>? extraMuscleGroups,
    Object? notes = _keep,
    DateTime? clientUpdatedAt,
    List<SessionExercise>? exercises,
    Object? pausedAt = _keep,
    int? pausedTotalS,
  }) =>
      WorkoutSession(
        id: id,
        name: name ?? this.name,
        workoutDayName: workoutDayName,
        status: status ?? this.status,
        startedAt: startedAt,
        endedAt: identical(endedAt, _keep) ? this.endedAt : endedAt as DateTime?,
        extraMuscleGroups: extraMuscleGroups ?? this.extraMuscleGroups,
        notes: identical(notes, _keep) ? this.notes : notes as String?,
        clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
        exercises: exercises ?? this.exercises,
        pausedAt: identical(pausedAt, _keep) ? this.pausedAt : pausedAt as DateTime?,
        pausedTotalS: pausedTotalS ?? this.pausedTotalS,
      );

  /// Active training time, excluding paused periods.
  Duration elapsed([DateTime? now]) {
    final end = endedAt ?? pausedAt ?? (now ?? DateTime.now()).toUtc();
    final d = end.difference(startedAt) - Duration(seconds: pausedTotalS);
    return d.isNegative ? Duration.zero : d;
  }

  List<WorkoutSet> get allSets => [for (final e in exercises) ...e.sets];
  List<WorkoutSet> get completedSets => allSets.where((s) => s.completed).toList();
  List<WorkoutSet> get validSets => allSets.where((s) => s.isValid).toList();
  int get totalReps => completedSets.fold(0, (a, s) => a + (s.reps ?? 0));
  double get volumeKg => completedSets.fold(0.0, (a, s) => a + s.volumeKg);
  int get exercisesCompleted => exercises.where((e) => e.sets.any((s) => s.completed)).length;
}

double epley1rm(double weight, int reps) => weight * (1 + reps / 30.0);
