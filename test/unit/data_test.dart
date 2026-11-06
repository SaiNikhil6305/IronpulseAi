import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/core/routing/router.dart';
import 'package:ironpulse/core/storage/local_db.dart';
import 'package:ironpulse/core/storage/providers.dart';
import 'package:ironpulse/core/sync/sync_service.dart';
import 'package:ironpulse/features/auth/data/auth_controller.dart';
import 'package:ironpulse/features/checklist/data/checklist_repository.dart';
import 'package:ironpulse/features/exercises/domain/exercise.dart';
import 'package:ironpulse/features/nutrition/data/nutrition_repository.dart';
import 'package:ironpulse/features/profile/domain/profile.dart';
import 'package:ironpulse/features/workouts/data/active_workout_controller.dart';
import 'package:ironpulse/features/workouts/data/rest_timer.dart';
import 'package:ironpulse/features/workouts/domain/workout_models.dart';

import '../helpers/test_harness.dart';

const bench = Exercise(id: 'barbell-bench-press', name: 'Barbell Bench Press', primaryMuscle: 'chest');
const curl = Exercise(id: 'dumbbell-curl', name: 'Dumbbell Curl', primaryMuscle: 'biceps');

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late LocalDb db;
  setUp(() async => db = await openTestDb());
  tearDown(() async => db.close());

  group('LocalDb', () {
    test('documents CRUD and change notifications', () async {
      final events = <String>[];
      final sub = db.changes.listen(events.add);
      await db.putDoc('meals', 'a', {'id': 'a', 'x': 1});
      await db.putDoc('meals', 'a', {'id': 'a', 'x': 2});
      expect((await db.getDoc('meals', 'a'))!['x'], 2);
      expect(await db.listDocs('meals'), hasLength(1));
      await db.deleteDoc('meals', 'a');
      expect(await db.getDoc('meals', 'a'), isNull);
      await settle();
      expect(events, ['meals', 'meals', 'meals']);
      await sub.cancel();
    });

    test('outbox coalesces newer writes to the same resource', () async {
      for (var i = 0; i < 5; i++) {
        await db.enqueue(OutboxOp(opId: 'op$i', method: 'PUT', path: '/v1/sessions/s1', body: {'v': i}, coalesceKey: '/v1/sessions/s1'));
      }
      await db.enqueue(OutboxOp(opId: 'other', method: 'PUT', path: '/v1/weights/w1', body: {}, coalesceKey: '/v1/weights/w1'));
      final ops = await db.pendingOps();
      expect(ops.map((o) => o.opId), ['op4', 'other']);
      expect(ops.first.body, {'v': 4});
    });

    test('failed ops are kept, not dropped, and can be retried', () async {
      await db.enqueue(OutboxOp(opId: 'x', method: 'PUT', path: '/v1/goals/g', body: {}));
      await db.recordAttempt('x', 'validation_error', permanent: true);
      expect(await db.pendingOps(), isEmpty);
      expect(await db.pendingOps(includeFailed: true), hasLength(1));
      expect((await db.outboxCounts()).failed, 1);
      await db.retryFailed();
      expect(await db.pendingOps(), hasLength(1));
    });

    test('hydration keeps documents with unsent changes', () async {
      const id = '11111111-2222-3333-4444-555555555555';
      await db.putDoc('goals', id, {'id': id, 'title': 'local edit'});
      await db.putDoc('goals', 'stale', {'id': 'stale'});
      await db.enqueue(OutboxOp(opId: 'g', method: 'PUT', path: '/v1/goals/$id', body: {}));
      final keep = await db.idsWithPendingChanges();
      await db.replaceCollection('goals', {
        id: {'id': id, 'title': 'server'},
        'new': {'id': 'new'}
      }, keep: keep);
      expect((await db.getDoc('goals', id))!['title'], 'local edit');
      expect(await db.getDoc('goals', 'stale'), isNull);
      expect(await db.getDoc('goals', 'new'), isNotNull);
    });
  });

  group('Active workout (offline-first logger)', () {
    test('logs sets, persists every change and survives an app restart', () async {
      final c1 = await makeContainer(db: db);
      final ctrl = c1.read(activeWorkoutProvider.notifier);
      await c1.read(activeWorkoutProvider.future);
      final s = await ctrl.start(name: 'Push');
      await ctrl.addExercise(bench, sets: 2);
      await ctrl.updateSet(0, 0, c1.read(activeWorkoutProvider).value!.exercises[0].sets[0].copyWith(weightKg: 40.0, reps: 10));
      expect(await ctrl.toggleSetComplete(0, 0), isTrue);
      await ctrl.addSet(0); // copies previous values, not completed
      final sets = c1.read(activeWorkoutProvider).value!.exercises[0].sets;
      expect(sets, hasLength(3));
      expect((sets[2].weightKg, sets[2].reps, sets[2].completed), (null, null, false)); // copies from set 2 (empty)
      c1.dispose();

      // "Restart": a fresh container reading the same database restores the workout.
      final c2 = await makeContainer(db: db);
      final restored = await c2.read(activeWorkoutProvider.future);
      expect(restored, isNotNull);
      expect(restored!.id, s.id);
      expect(restored.exercises.single.sets.first.completed, isTrue);
      expect(restored.exercises.single.sets.first.weightKg, 40);

      final done = await c2.read(activeWorkoutProvider.notifier).finish();
      expect(done!.status, 'completed');
      expect(done.exercises.single.sets, hasLength(1)); // untouched empty sets dropped
      expect(c2.read(activeWorkoutProvider).value, isNull);
      expect(await db.getDoc(Col.meta, Meta.activeSessionId), isNull);
      c2.dispose();
    });

    test('copy previous values, reorder, replace and left/right tracking', () async {
      final c = await makeContainer(db: db);
      await c.read(activeWorkoutProvider.future);
      final ctrl = c.read(activeWorkoutProvider.notifier);
      await ctrl.start(name: 'Test');
      await ctrl.addExercise(bench, sets: 1);
      await ctrl.addExercise(curl, sets: 1);
      await ctrl.copyPrevious(0, const [
        WorkoutSet(id: 'p1', position: 0, weightKg: 40, reps: 10, completed: true),
        WorkoutSet(id: 'p2', position: 1, weightKg: 40, reps: 9, completed: true),
      ]);
      var s = c.read(activeWorkoutProvider).value!;
      expect(s.exercises[0].sets.map((x) => (x.weightKg, x.reps, x.completed)), [(40.0, 10, false), (40.0, 9, false)]);
      await ctrl.reorderExercise(1, 0);
      s = c.read(activeWorkoutProvider).value!;
      expect(s.exercises.map((e) => e.exerciseRef), ['dumbbell-curl', 'barbell-bench-press']);
      await ctrl.toggleUnilateral(0);
      expect(c.read(activeWorkoutProvider).value!.exercises[0].sets.map((x) => x.side), ['left', 'right']);
      await ctrl.addSet(0);
      expect(c.read(activeWorkoutProvider).value!.exercises[0].sets, hasLength(4));
      await ctrl.replaceExercise(1, curl);
      expect(c.read(activeWorkoutProvider).value!.exercises[1].exerciseName, 'Dumbbell Curl');
      c.dispose();
    });

    test('client timestamps are strictly increasing (last-write-wins safety)', () async {
      final c = await makeContainer(db: db);
      await c.read(activeWorkoutProvider.future);
      final ctrl = c.read(activeWorkoutProvider.notifier);
      await ctrl.start(name: 'T');
      var last = c.read(activeWorkoutProvider).value!.clientUpdatedAt;
      for (var i = 0; i < 20; i++) {
        await ctrl.setNotes('n$i');
        final now = c.read(activeWorkoutProvider).value!.clientUpdatedAt;
        expect(now.isAfter(last), isTrue);
        last = now;
      }
      c.dispose();
    });

    test('rest timer persists and schedules/cancels the alert notification', () async {
      final n = FakeNotifications();
      final c = await makeContainer(db: db, notifications: n);
      final t = c.read(restTimerProvider.notifier);
      await t.start(90);
      expect(c.read(restTimerProvider).active, isTrue);
      expect(c.read(restTimerProvider).remainingS(), inInclusiveRange(89, 90));
      await t.togglePause();
      expect(c.read(restTimerProvider).paused, isTrue);
      await t.skip();
      expect(c.read(restTimerProvider).active, isFalse);
      expect(n.restScheduled, 1);
      expect(n.restCancelled, greaterThanOrEqualTo(2));
      c.dispose();
    });
  });

  group('Sync service', () {
    Future<ProviderContainer> account(FakeBackend be, FakeNetwork net) async {
      final c = await makeContainer(db: db, account: true, backend: be, network: net);
      c.listen(syncServiceProvider, (_, _) {});
      await settle();
      return c;
    }

    test('offline writes stay queued and upload exactly once when connectivity returns', () async {
      final be = FakeBackend()..online = false;
      final net = FakeNetwork()..online = false;
      be.handler = (o) => o.path.startsWith('/v1/sessions/')
          ? FakeBackend.json(jsonEncode({'id': o.path.split('/').last, 'applied': true, 'server_updated_at': 'x',
              'xp_from_session': 55, 'new_achievements': [], 'personal_records': []}))
          : FakeBackend.json('{}');
      final c = await account(be, net);
      await c.read(activeWorkoutProvider.future);
      final ctrl = c.read(activeWorkoutProvider.notifier);
      await ctrl.start(name: 'Push');
      await ctrl.addExercise(bench, sets: 1);
      final id = c.read(activeWorkoutProvider).value!.id;
      await c.read(syncServiceProvider.notifier).syncNow();
      expect(be.requests, isEmpty);
      final queued = await db.pendingOps();
      expect(queued, hasLength(1)); // many edits coalesced into one snapshot
      expect(queued.single.attempts, greaterThanOrEqualTo(1));
      expect(await db.getDoc(Col.sessions, id), isNotNull); // never lost locally

      be.online = true;
      net.set(true);
      await c.read(syncServiceProvider.notifier).syncNow();
      final puts = be.requests.where((r) => r.method == 'PUT' && r.path == '/v1/sessions/$id');
      expect(puts, hasLength(1));
      expect(await db.pendingOps(), isEmpty);
      expect((await db.getDoc(Col.sessionSync, id))!['xp_from_session'], 55);
      final body = puts.single.data as Map;
      expect(body.containsKey('paused_total_s'), isFalse);
      expect(puts.single.headers['Authorization'], 'Bearer test-token');
      c.dispose();
    });

    test('server rejections are kept for review; transient errors retry; 404 deletes are done', () async {
      final be = FakeBackend();
      be.handler = (o) {
        if (o.path == '/v1/goals/bad') return FakeBackend.json('{"error":{"code":"validation_error","message":"bad"}}', 422);
        if (o.path == '/v1/weights/flaky') return FakeBackend.json('{"error":{"code":"internal_error","message":"x"}}', 503);
        if (o.method == 'DELETE') return FakeBackend.json('{"error":{"code":"not_found","message":"gone"}}', 404);
        return FakeBackend.json('{}');
      };
      final c = await account(be, FakeNetwork());
      final w = c.read(dataWriterProvider);
      await w.enqueue('DELETE', '/v1/meals/old', null);
      await w.enqueue('PUT', '/v1/goals/bad', {'x': 1});
      await w.enqueue('PUT', '/v1/weights/flaky', {'x': 1});
      await w.enqueue('PUT', '/v1/goals/after', {'x': 1});
      await c.read(syncServiceProvider.notifier).syncNow();
      final all = await db.pendingOps(includeFailed: true);
      expect(all.map((o) => (o.path, o.failedPermanently)), [('/v1/goals/bad', true), ('/v1/weights/flaky', false), ('/v1/goals/after', false)]);
      expect(be.requests.any((r) => r.path == '/v1/goals/after'), isFalse); // order preserved behind the transient failure
      c.dispose();
    });

    test('device-only mode never queues network operations', () async {
      final c = await makeContainer(db: db);
      await c.read(dataWriterProvider).save(Col.goals, 'g', {'id': 'g'}, path: '/v1/goals/g');
      expect(await db.pendingOps(), isEmpty);
      expect(await db.getDoc(Col.goals, 'g'), isNotNull);
      c.dispose();
    });
  });

  group('Checklist', () {
    test('toggling is idempotent and feeds nutrition only with real values', () async {
      final c = await makeContainer(db: db);
      final repo = c.read(checklistRepositoryProvider);
      const shake = ChecklistItem(id: 'i1', name: 'Protein shake', category: 'supplement', proteinG: 24, calories: 120);
      const water = ChecklistItem(id: 'i2', name: 'Water', category: 'habit');
      await repo.saveItem(shake);
      await repo.saveItem(water);
      for (final v in [true, true, false, true]) {
        await repo.setCompleted(shake, '2026-10-25', v);
      }
      await repo.setCompleted(water, '2026-10-25', true);
      expect(await db.listDocs(Col.checklistCompletions), hasLength(2));
      final meals = [for (final d in await db.listDocs(Col.meals)) Meal.fromJson(d)];
      expect(meals, hasLength(1));
      expect(meals.single.entries.single.proteinG, 24);
      await repo.setCompleted(shake, '2026-10-25', false);
      expect(await db.listDocs(Col.meals), isEmpty);
      c.dispose();
    });
  });

  group('Router redirect', () {
    const signedOut = AuthState.signedOut();
    const signedIn = AuthState(status: AuthStatus.signedIn, userId: 'u');
    final done = Profile.empty.copyWith({'onboarding_completed': true});

    test('auth, onboarding and home routing', () {
      expect(resolveRedirect(location: '/home', auth: signedOut, bootstrap: const AsyncData(false), profileLoaded: true, profile: null), '/sign-in');
      expect(resolveRedirect(location: '/sign-up', auth: signedOut, bootstrap: const AsyncData(false), profileLoaded: true, profile: null), isNull);
      expect(resolveRedirect(location: '/home', auth: signedIn, bootstrap: const AsyncLoading(), profileLoaded: true, profile: null), '/splash');
      expect(resolveRedirect(location: '/splash', auth: signedIn, bootstrap: const AsyncData(true), profileLoaded: true, profile: null), '/onboarding');
      expect(resolveRedirect(location: '/onboarding/split', auth: signedIn, bootstrap: const AsyncData(true), profileLoaded: true, profile: Profile.empty), isNull);
      expect(resolveRedirect(location: '/splash', auth: signedIn, bootstrap: const AsyncData(true), profileLoaded: true, profile: done), '/home');
      expect(resolveRedirect(location: '/workout/active', auth: signedIn, bootstrap: const AsyncData(true), profileLoaded: true, profile: done), isNull);
      expect(
          resolveRedirect(
              location: '/home',
              auth: const AuthState(status: AuthStatus.signedIn, userId: 'u', recovering: true),
              bootstrap: const AsyncData(true),
              profileLoaded: true,
              profile: done),
          '/new-password');
    });
  });
}
