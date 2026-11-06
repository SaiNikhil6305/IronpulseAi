import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../domain/split.dart';
import '../domain/workout_models.dart';

/// All non-discarded sessions, newest first.
final sessionsProvider = Provider<List<WorkoutSession>>((ref) {
  final docs = ref.watch(docsProvider(Col.sessions)).value ?? const [];
  final list = <WorkoutSession>[];
  for (final d in docs) {
    try {
      final s = WorkoutSession.fromJson(d);
      if (s.status != 'discarded') list.add(s);
    } catch (_) {
      // Skip malformed documents rather than crash the app.
    }
  }
  list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return list;
});

final sessionsLoadedProvider = Provider<bool>((ref) => ref.watch(docsProvider(Col.sessions)).hasValue);

final completedSessionsProvider =
    Provider<List<WorkoutSession>>((ref) => ref.watch(sessionsProvider).where((s) => s.isCompleted).toList());

final lastCompletedSessionProvider = Provider<WorkoutSession?>((ref) => ref.watch(completedSessionsProvider).firstOrNull);

final sessionByIdProvider = Provider.family<WorkoutSession?, String>(
    (ref, id) => ref.watch(sessionsProvider).where((s) => s.id == id).firstOrNull);

final activeSplitProvider = Provider<WorkoutSplit?>((ref) {
  final doc = ref.watch(docProvider((Col.meta, Meta.split))).value;
  if (doc == null) return null;
  try {
    return WorkoutSplit.fromJson(doc);
  } catch (_) {
    return null;
  }
});

final scheduleProvider = Provider<List<ScheduleDay>>((ref) {
  final doc = ref.watch(docProvider((Col.meta, Meta.schedule))).value;
  final days = doc?['days'] as List? ?? const [];
  return [for (final d in days) ScheduleDay.fromJson(Map<String, dynamic>.from(d))]
    ..sort((a, b) => a.weekday.compareTo(b.weekday));
});

final todayPlanProvider = Provider<TodayPlan>((ref) => planForToday(
      split: ref.watch(activeSplitProvider),
      history: ref.watch(sessionsProvider),
      schedule: ref.watch(scheduleProvider),
      now: DateTime.now(),
    ));

/// Most recent completed performance of an exercise, excluding [excludeSessionId].
class PreviousPerformance {
  const PreviousPerformance(this.session, this.sets);
  final WorkoutSession session;
  final List<WorkoutSet> sets;
}

PreviousPerformance? findPreviousPerformance(List<WorkoutSession> sessions, String exerciseRef,
    {String? excludeSessionId}) {
  for (final s in sessions) {
    if (!s.isCompleted || s.id == excludeSessionId) continue;
    final sets = [
      for (final e in s.exercises)
        if (e.exerciseRef == exerciseRef) ...e.sets.where((x) => x.completed)
    ];
    if (sets.isNotEmpty) return PreviousPerformance(s, sets);
  }
  return null;
}

final previousPerformanceProvider = Provider.family<PreviousPerformance?, (String, String?)>(
    (ref, key) => findPreviousPerformance(ref.watch(sessionsProvider), key.$1, excludeSessionId: key.$2));

/// Server-confirmed sync result for a session (XP etc.), if synced.
final sessionSyncProvider = Provider.family<Map<String, dynamic>?, String>((ref, id) {
  final docs = ref.watch(docsProvider(Col.sessionSync)).value ?? const [];
  return docs.where((d) => d['id'] == id).firstOrNull;
});

class WorkoutRepository {
  WorkoutRepository(this.ref);
  final Ref ref;

  DataWriter get _w => ref.read(dataWriterProvider);

  Future<void> saveSession(WorkoutSession s) =>
      _w.save(Col.sessions, s.id, s.toJson(), path: '/v1/sessions/${s.id}', body: s.toApi());

  Future<void> deleteSession(String id) => _w.remove(Col.sessions, id, path: '/v1/sessions/$id');

  Future<void> saveSplit(WorkoutSplit split) =>
      _w.save(Col.meta, Meta.split, split.toJson(), path: '/v1/splits/${split.id}', body: split.toApi());

  Future<void> saveSchedule(List<ScheduleDay> days) => _w.save(
        Col.meta,
        Meta.schedule,
        {'days': [for (final d in days) d.toJson()]},
        path: '/v1/schedule',
        body: {'items': [for (final d in days) d.toJson()]},
      );
}

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) => WorkoutRepository(ref));
