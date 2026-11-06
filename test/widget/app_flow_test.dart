import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/app.dart';
import 'package:ironpulse/core/storage/local_db.dart';
import 'package:ironpulse/core/storage/providers.dart';
import 'package:ironpulse/core/sync/sync_service.dart';
import 'package:ironpulse/features/auth/data/auth_controller.dart';
import 'package:ironpulse/features/auth/presentation/auth_screens.dart';
import 'package:ironpulse/features/notifications/data/notification_service.dart';
import 'package:ironpulse/features/profile/domain/profile.dart';
import 'package:ironpulse/features/workouts/data/active_workout_controller.dart';
import 'package:ironpulse/features/workouts/domain/split.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_harness.dart';

/// Same-isolate SQLite so database futures complete inside the widget tester's fake async zone.
Future<LocalDb> _db() async {
  sqfliteFfiInit();
  return LocalDb.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
}

Future<(LocalDb, SharedPreferences)> _seed({bool onboarded = true}) async {
  SharedPreferences.setMockInitialValues({'auth.local_mode': true, 'intro.first_workout_shown': true, 'rest.auto_start': false});
  final prefs = await SharedPreferences.getInstance();
  final db = await _db();
  if (onboarded) {
    await db.putDoc(Col.meta, Meta.profile,
        Profile.empty.copyWith({'display_name': 'Arjun', 'onboarding_completed': true, 'weekly_target': 3}).json);
    final today = DateTime.now().weekday;
    final push = splitPresets.first.days.first.copyWith(weekdays: [today]);
    await db.putDoc(Col.meta, Meta.split,
        WorkoutSplit(id: 'split-1', name: 'PPL', splitType: 'ppl', days: [push, ...splitPresets.first.days.skip(1)]).toJson());
  }
  return (db, prefs);
}

Widget _app(LocalDb db, SharedPreferences prefs) => ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(db),
        prefsProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(FakeNotifications()),
        networkMonitorProvider.overrideWithValue(FakeNetwork()),
      ],
      child: const IronPulseApp(),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('unconfigured build explains what is missing and offers device-only mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await _db();
    final container = ProviderContainer(overrides: [
      localDbProvider.overrideWithValue(db),
      prefsProvider.overrideWithValue(prefs),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: SignInScreen())));
    expect(find.text('Account sign-in not configured'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing); // never a fake Google button
    await tester.tap(find.text('Use on this device only'));
    await tester.pump();
    expect(container.read(authControllerProvider).isLocal, isTrue);
    container.dispose();
  });

  testWidgets('new device-only user is sent to onboarding', (tester) async {
    final (db, prefs) = await _seed(onboarded: false);
    await tester.pumpWidget(_app(db, prefs));
    await _settle(tester);
    expect(find.textContaining('Welcome to IronPulse'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('home → start today\'s workout → log a set → it is saved', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final (db, prefs) = await _seed();
    await tester.pumpWidget(_app(db, prefs));
    await _settle(tester);

    expect(find.textContaining('Arjun'), findsOneWidget);
    expect(find.text('PUSH'), findsOneWidget); // today's planned split day
    expect(find.text('Start workout'), findsWidgets);

    // Bottom navigation works.
    await tester.tap(find.text('Progress').last);
    await _settle(tester);
    expect(find.text('Insights').evaluate().isEmpty, isTrue); // no fabricated insights without data
    await tester.tap(find.text('Home').last);
    await _settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Start workout'));
    await _settle(tester);
    expect(find.text('Want to train anything extra today?'), findsOneWidget);
    await tester.tap(find.text('Abs'));
    await tester.pump();
    await tester.tap(find.text('Start with 1 extra'));
    await _settle(tester);

    // Logger is open with today's exercises plus the extra.
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('First time logging this exercise.'), findsWidgets);

    final weight = find.byType(TextField).at(0);
    final reps = find.byType(TextField).at(1);
    await tester.enterText(weight, '40');
    await tester.enterText(reps, '10');
    await tester.tap(find.byTooltip('Mark set complete').first);
    await _settle(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final s = container.read(activeWorkoutProvider).value!;
    expect(s.extraMuscleGroups, ['core']);
    expect(s.exercises.any((e) => e.exerciseRef == 'cable-crunch'), isTrue);
    final first = s.exercises.first.sets.first;
    expect((first.weightKg, first.reps, first.completed), (40.0, 10, true));
    final stored = await db.getDoc(Col.sessions, s.id);
    expect(stored!['exercises'][0]['sets'][0]['completed'], isTrue); // persisted immediately
    expect(find.text('Saved on this device'), findsOneWidget);

    // Tear down so periodic timers (workout clock) are disposed with the providers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
