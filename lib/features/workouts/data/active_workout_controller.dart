import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/split.dart';
import '../domain/workout_models.dart';
import 'workout_repository.dart';

/// Owns the in-progress workout. Every mutation is written to SQLite
/// immediately (crash/close safe) and queued for idempotent sync.
class ActiveWorkoutController extends AsyncNotifier<WorkoutSession?> {
  DateTime _lastStamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  Future<WorkoutSession?> build() async {
    final db = ref.read(localDbProvider);
    final meta = await db.getDoc(Col.meta, Meta.activeSessionId);
    final id = meta?['id'] as String?;
    if (id == null) return null;
    final doc = await db.getDoc(Col.sessions, id);
    if (doc == null) return null;
    final s = WorkoutSession.fromJson(doc);
    if (!s.inProgress) {
      await db.deleteDoc(Col.meta, Meta.activeSessionId);
      return null;
    }
    _lastStamp = s.clientUpdatedAt;
    return s;
  }

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  /// Monotonic client timestamp so last-write-wins never goes backwards.
  DateTime _stamp() {
    var now = DateTime.now().toUtc();
    if (!now.isAfter(_lastStamp)) now = _lastStamp.add(const Duration(milliseconds: 1));
    _lastStamp = now;
    return now;
  }

  WorkoutSession? get current => state.value;

  Future<void> _commit(WorkoutSession next) async {
    final stamped = next.copyWith(clientUpdatedAt: _stamp());
    state = AsyncData(stamped);
    await _repo.saveSession(stamped);
  }

  Future<void> _update(WorkoutSession Function(WorkoutSession s) fn) async {
    final s = current;
    if (s == null) return;
    await _commit(fn(s));
  }

  // ---- Lifecycle ------------------------------------------------------------
  Future<WorkoutSession> start({
    required String name,
    String? workoutDayName,
    List<SessionExercise> exercises = const [],
    List<String> extraMuscleGroups = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final s = WorkoutSession(
      id: newId(),
      name: name,
      workoutDayName: workoutDayName,
      status: 'in_progress',
      startedAt: now,
      clientUpdatedAt: now,
      exercises: [for (var i = 0; i < exercises.length; i++) exercises[i].copyWith(position: i)],
      extraMuscleGroups: extraMuscleGroups,
    );
    await ref.read(localDbProvider).putDoc(Col.meta, Meta.activeSessionId, {'id': s.id});
    await _commit(s);
    return state.value!;
  }

  /// Start today's split day. Set values start empty: previous performance is
  /// shown as a hint with a one-tap copy instead of being assumed.
  Future<WorkoutSession> startFromDay(SplitDay day, Map<String, Exercise> index,
      {List<String> extraGroups = const []}) {
    final exercises = <SessionExercise>[
      for (final t in day.exercises)
        if (index[t.exerciseRef] != null) _blankExercise(index[t.exerciseRef]!, t.targetSets),
    ];
    for (final g in extraGroups) {
      final refs = extraGroupExercises[g] ?? const [];
      for (final r in refs.take(1)) {
        if (index[r] != null && !exercises.any((e) => e.exerciseRef == r)) {
          exercises.add(_blankExercise(index[r]!, 3));
        }
      }
    }
    return start(name: day.name, workoutDayName: day.name, exercises: exercises, extraMuscleGroups: extraGroups);
  }

  /// Repeat a previous session's exercise list (values are not prefilled).
  Future<WorkoutSession> repeat(WorkoutSession previous) => start(
        name: previous.name,
        workoutDayName: previous.workoutDayName,
        exercises: [
          for (final e in previous.exercises)
            SessionExercise(
              id: newId(),
              exerciseRef: e.exerciseRef,
              exerciseName: e.exerciseName,
              position: e.position,
              sets: [
                for (var i = 0; i < (e.sets.isEmpty ? 3 : e.sets.length); i++)
                  WorkoutSet(id: newId(), position: i, side: e.sets.isEmpty ? null : e.sets[i].side)
              ],
            )
        ],
      );

  static SessionExercise _blankExercise(Exercise ex, int sets) => SessionExercise(
        id: newId(),
        exerciseRef: ex.id,
        exerciseName: ex.name,
        position: 0,
        sets: [for (var i = 0; i < sets; i++) WorkoutSet(id: newId(), position: i)],
      );

  Future<WorkoutSession?> finish({String? notes}) async {
    final s = current;
    if (s == null) return null;
    var paused = s.pausedTotalS;
    if (s.pausedAt != null) paused += DateTime.now().toUtc().difference(s.pausedAt!).inSeconds;
    // Drop empty, never-touched sets so history only shows what was done.
    final exercises = [
      for (final e in s.exercises)
        e.copyWith(sets: [
          for (final st in e.sets)
            if (st.completed || st.weightKg != null || st.reps != null || st.durationS != null) st
        ])
    ];
    final done = s.copyWith(
      status: 'completed',
      endedAt: DateTime.now().toUtc(),
      notes: notes ?? s.notes,
      exercises: exercises,
      pausedAt: null,
      pausedTotalS: paused,
    );
    await _commit(done);
    await ref.read(localDbProvider).deleteDoc(Col.meta, Meta.activeSessionId);
    state = const AsyncData(null);
    return done;
  }

  Future<void> discard() async {
    final s = current;
    if (s == null) return;
    await ref.read(localDbProvider).deleteDoc(Col.meta, Meta.activeSessionId);
    await _repo.deleteSession(s.id);
    state = const AsyncData(null);
  }

  Future<void> togglePause() => _update((s) {
        final now = DateTime.now().toUtc();
        if (s.pausedAt == null) return s.copyWith(pausedAt: now);
        return s.copyWith(pausedAt: null, pausedTotalS: s.pausedTotalS + now.difference(s.pausedAt!).inSeconds);
      });

  Future<void> setNotes(String? notes) => _update((s) => s.copyWith(notes: notes));

  // ---- Exercises -----------------------------------------------------------
  Future<void> addExercise(Exercise ex, {int sets = 3}) => _update((s) => s.copyWith(exercises: [
        ...s.exercises,
        _blankExercise(ex, sets).copyWith(position: s.exercises.length),
      ]));

  Future<void> replaceExercise(int index, Exercise ex) => _update((s) {
        final list = [...s.exercises];
        list[index] = list[index].copyWith(exerciseRef: ex.id, exerciseName: ex.name);
        return s.copyWith(exercises: list);
      });

  Future<void> removeExercise(int index) => _update((s) {
        final list = [...s.exercises]..removeAt(index);
        return s.copyWith(exercises: [for (var i = 0; i < list.length; i++) list[i].copyWith(position: i)]);
      });

  Future<void> reorderExercise(int oldIndex, int newIndex) => _update((s) {
        final list = [...s.exercises];
        final item = list.removeAt(oldIndex);
        list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
        return s.copyWith(exercises: [for (var i = 0; i < list.length; i++) list[i].copyWith(position: i)]);
      });

  Future<void> setExerciseNotes(int index, String? notes) => _update((s) {
        final list = [...s.exercises];
        list[index] = list[index].copyWith(notes: notes ?? '');
        return s.copyWith(exercises: list);
      });

  // ---- Sets ------------------------------------------------------------------
  List<WorkoutSet> _renumber(List<WorkoutSet> sets) => [for (var i = 0; i < sets.length; i++) sets[i].copyWith(position: i)];

  Future<void> _updateSets(int exIndex, List<WorkoutSet> Function(List<WorkoutSet>) fn) => _update((s) {
        final list = [...s.exercises];
        list[exIndex] = list[exIndex].copyWith(sets: _renumber(fn([...list[exIndex].sets])));
        return s.copyWith(exercises: list);
      });

  /// Adds a set pre-filled from the previous set in this session (still editable, not completed).
  Future<void> addSet(int exIndex) => _updateSets(exIndex, (sets) {
        final last = sets.isEmpty ? null : sets.last;
        final paired = last?.side != null;
        WorkoutSet make(String? side) => WorkoutSet(
            id: newId(),
            position: sets.length,
            side: side,
            weightKg: last?.weightKg,
            reps: last?.reps,
            durationS: last?.durationS,
            distanceM: last?.distanceM);
        if (paired) return [...sets, make('left'), make('right')];
        return [...sets, make(null)];
      });

  Future<void> removeSet(int exIndex, int setIndex) => _updateSets(exIndex, (sets) => sets..removeAt(setIndex));

  Future<void> updateSet(int exIndex, int setIndex, WorkoutSet updated) =>
      _updateSets(exIndex, (sets) => sets..[setIndex] = updated);

  /// Returns the new completion state.
  Future<bool> toggleSetComplete(int exIndex, int setIndex) async {
    var nowDone = false;
    await _updateSets(exIndex, (sets) {
      final st = sets[setIndex];
      nowDone = !st.completed;
      sets[setIndex] = st.copyWith(completed: nowDone, completedAt: nowDone ? DateTime.now().toUtc() : null);
      return sets;
    });
    return nowDone;
  }

  /// One-tap copy of last session's values into this exercise's sets (not marked complete).
  Future<void> copyPrevious(int exIndex, List<WorkoutSet> previous) => _updateSets(exIndex, (sets) {
        final out = <WorkoutSet>[];
        final n = previous.length > sets.length ? previous.length : sets.length;
        for (var i = 0; i < n; i++) {
          final base = i < sets.length ? sets[i] : WorkoutSet(id: newId(), position: i);
          if (i < previous.length && !base.completed) {
            final p = previous[i];
            out.add(base.copyWith(
                side: p.side, weightKg: p.weightKg, reps: p.reps, durationS: p.durationS, distanceM: p.distanceM));
          } else {
            out.add(base);
          }
        }
        return out;
      });

  /// Switch an exercise between combined and separate left/right sets.
  Future<void> toggleUnilateral(int exIndex) => _updateSets(exIndex, (sets) {
        final paired = sets.any((s) => s.side != null);
        if (paired) {
          return [for (final s in sets) if (s.side != 'right') s.copyWith(side: null)];
        }
        return [
          for (final s in sets) ...[
            s.copyWith(side: 'left'),
            WorkoutSet(id: newId(), position: 0, side: 'right', weightKg: s.weightKg, reps: s.reps),
          ]
        ];
      });
}

final activeWorkoutProvider =
    AsyncNotifierProvider<ActiveWorkoutController, WorkoutSession?>(ActiveWorkoutController.new);

/// Keeps elapsed-time widgets ticking once a second.
/// Auto-disposed so the timer stops when no timer widget is on screen.
final secondTickerProvider = StreamProvider.autoDispose<DateTime>(
    (ref) => Stream<DateTime>.periodic(const Duration(seconds: 1), (_) => DateTime.now()));
