import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/core/utils/units.dart';
import 'package:ironpulse/core/utils/validators.dart';
import 'package:ironpulse/features/gamification/domain/xp_rules.dart';
import 'package:ironpulse/features/notifications/domain/reminder_planner.dart';
import 'package:ironpulse/features/nutrition/data/nutrition_repository.dart';
import 'package:ironpulse/features/settings/presentation/settings_screens.dart';
import 'package:ironpulse/features/workouts/domain/split.dart';
import 'package:ironpulse/features/workouts/domain/workout_models.dart';

WorkoutSession session({
  required DateTime start,
  String status = 'completed',
  String name = 'Push',
  List<SessionExercise>? exercises,
}) =>
    WorkoutSession(
      id: newId(),
      name: name,
      workoutDayName: name,
      status: status,
      startedAt: start.toUtc(),
      endedAt: status == 'completed' ? start.toUtc().add(const Duration(minutes: 50)) : null,
      clientUpdatedAt: start.toUtc(),
      exercises: exercises ??
          [
            SessionExercise(id: newId(), exerciseRef: 'barbell-bench-press', exerciseName: 'Bench Press', position: 0, sets: [
              for (var i = 0; i < 3; i++)
                WorkoutSet(id: newId(), position: i, weightKg: 40, reps: 10 - i, completed: true),
            ]),
          ],
    );

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('bad@'), isNotNull);
      expect(Validators.email(' lifter@example.com '), isNull);
    });
    test('password strength', () {
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('onlyletters'), isNotNull);
      expect(Validators.password('strong123'), isNull);
    });
    test('numbers accept commas and ranges', () {
      final v = Validators.number(min: 25, max: 400);
      expect(v(''), isNull);
      expect(v('72,5'), isNull);
      expect(v('10'), isNotNull);
      expect(v('abc'), isNotNull);
      expect(Validators.parseNum('72,5'), 72.5);
      expect(Validators.number(optional: false)(''), isNotNull);
    });
    test('confirm password', () {
      expect(Validators.confirm(() => 'abc12345')('abc12345'), isNull);
      expect(Validators.confirm(() => 'abc12345')('x'), isNotNull);
    });
  });

  group('Units & dates', () {
    test('kg/lb round trip and gym rounding', () {
      expect(Units.toKg(100, 'imperial'), closeTo(45.359, 0.001));
      expect(Units.weight(40, 'metric'), '40 kg');
      expect(Units.weight(7.5, 'metric'), '7.5 kg');
      expect(Units.weight(20, 'imperial'), '44 lb');
    });
    test('ISO week keys match the backend', () {
      expect(Dates.weekKey(DateTime(2026, 10, 25)), '2026-W43'); // Sunday
      expect(Dates.weekKey(DateTime(2026, 10, 26)), '2026-W44'); // Monday
      expect(Dates.weekKey(DateTime(2024, 12, 31)), '2025-W01');
      expect(Dates.weekKey(DateTime(2021, 1, 3)), '2020-W53');
    });
  });

  group('Set validity & XP (mirrors backend tests)', () {
    test('only completed plausible sets are valid', () {
      expect(const WorkoutSet(id: 'a', position: 0, weightKg: 40, reps: 8, completed: true).isValid, isTrue);
      expect(const WorkoutSet(id: 'a', position: 0, weightKg: 40, reps: 8).isValid, isFalse);
      expect(const WorkoutSet(id: 'a', position: 0, weightKg: 40, reps: 0, completed: true).isValid, isFalse);
      expect(const WorkoutSet(id: 'a', position: 0, weightKg: 900, reps: 5, completed: true).isValid, isFalse);
      expect(const WorkoutSet(id: 'a', position: 0, durationS: 45, completed: true).isValid, isTrue);
    });

    test('session XP = 10/set + 25 bonus', () {
      expect(sessionXp(session(start: DateTime(2026, 10, 20, 18))), 55);
      expect(sessionXp(session(start: DateTime(2026, 10, 20, 18), status: 'in_progress')), 0);
    });

    test('workout bonus capped at two per day', () {
      final day = DateTime(2026, 10, 20, 8);
      final r = computeLocalXp(
        sessions: [for (var i = 0; i < 3; i++) session(start: day.add(Duration(hours: i * 3)))],
        checklistCompletions: 2,
        weighInDays: [DateTime(2026, 10, 19), DateTime(2026, 10, 20)],
        weeklyTarget: 3,
      );
      expect(r.breakdown['sets'], 90);
      expect(r.breakdown['workouts'], 50);
      expect(r.breakdown['checklist'], 10);
      expect(r.breakdown['weigh_ins'], 15); // same ISO week counts once
      expect(r.breakdown['weekly_targets'], 30);
      expect(r.unlocked, containsAll(['first_workout', 'three_sessions', 'weekly_consistency']));
    });

    test('levels', () {
      expect(LevelInfo.fromXp(0).name, 'Rookie');
      final l = LevelInfo.fromXp(300);
      expect(l.name, 'Gym Beginner');
      expect(l.xpToNext, 450);
      expect(LevelInfo.fromXp(99999).nextXp, isNull);
    });

    test('streaks count weeks, ignore rest days, unfinished week does not break', () {
      final today = DateTime(2026, 10, 25);
      final mon = today.subtract(Duration(days: today.weekday - 1));
      final dates = [
        for (var w = 0; w < 3; w++) ...[
          mon.subtract(Duration(days: 7 * w)),
          mon.subtract(Duration(days: 7 * w - 2)),
          mon.subtract(Duration(days: 7 * w - 4)),
        ]
      ];
      final s = computeStreaks(dates, 3, today);
      expect(s.current, 3);
      expect(s.longest, 3);
      final wed = DateTime(2026, 10, 21);
      final lastWeek = wed.subtract(const Duration(days: 7));
      expect(computeStreaks([lastWeek, lastWeek.add(const Duration(days: 1))], 2, wed).current, 1);
      final old = computeStreaks([today.subtract(const Duration(days: 21)), today.subtract(const Duration(days: 28))], 1, today);
      expect(old.current, 0);
      expect(old.longest, 2);
    });

    test('personal records need a heavier estimated 1RM than earlier sessions', () {
      final a = session(start: DateTime(2026, 10, 1));
      final b = session(start: DateTime(2026, 10, 8), exercises: [
        SessionExercise(id: newId(), exerciseRef: 'barbell-bench-press', exerciseName: 'Bench Press', position: 0, sets: [
          WorkoutSet(id: newId(), position: 0, weightKg: 45, reps: 10, completed: true),
        ]),
      ]);
      final prs = personalRecords([b, a]);
      expect(prs, hasLength(1));
      expect(prs.single.weightKg, 45);
      expect(prs.single.sessionId, b.id);
    });
  });

  group('Splits & today\'s plan', () {
    final ppl = WorkoutSplit(id: 's', name: 'PPL', splitType: 'ppl', days: assignWeekdays(splitPresets.first.days, [1, 3, 5]));

    test('assigns training days in order', () {
      expect(ppl.days.map((d) => d.weekdays).toList(), [
        [1],
        [3],
        [5]
      ]);
      expect(assignWeekdays(splitPresets.first.days, [1, 2, 3, 4, 5, 6]).first.weekdays, [1, 4]);
    });

    test('weekday plan and rest days', () {
      expect(planForToday(split: ppl, history: const [], schedule: const [], now: DateTime(2026, 10, 26)).day?.name, 'Push');
      expect(planForToday(split: ppl, history: const [], schedule: const [], now: DateTime(2026, 10, 27)).isRestDay, isTrue);
    });

    test('schedule overrides split', () {
      final plan = planForToday(
        split: ppl,
        history: const [],
        schedule: const [ScheduleDay(weekday: 1, isRestDay: true)],
        now: DateTime(2026, 10, 26),
      );
      expect(plan.isRestDay, isTrue);
      final named = planForToday(
        split: ppl,
        history: const [],
        schedule: const [ScheduleDay(weekday: 2, timeLocal: '07:00', workoutDayName: 'Legs')],
        now: DateTime(2026, 10, 27),
      );
      expect(named.day?.name, 'Legs');
      expect(named.time, '07:00');
    });

    test('rotation continues after the last completed day', () {
      final rot = WorkoutSplit(id: 'r', name: 'R', splitType: 'ppl', days: splitPresets.first.days);
      final hist = [session(start: DateTime(2026, 10, 20), name: 'Pull')];
      expect(planForToday(split: rot, history: hist, schedule: const [], now: DateTime(2026, 10, 21)).day?.name, 'Legs');
    });
  });

  group('Reminders', () {
    test('deterministic ids, offsets and day wrap', () {
      final specs = planGymReminders(
        schedule: const [
          ScheduleDay(weekday: 1, timeLocal: '18:00', workoutDayName: 'Push'),
          ScheduleDay(weekday: 3, isRestDay: true),
          ScheduleDay(weekday: 2, timeLocal: '00:10', workoutDayName: 'Pull'),
        ],
        offsetsMinutes: [20, 30, 20],
        history: [session(start: DateTime(2026, 10, 19), name: 'Push')],
      );
      expect(specs, hasLength(4));
      expect(specs.map((s) => s.id).toSet(), hasLength(4));
      final push20 = specs.firstWhere((s) => s.id == ReminderIds.gym(1, 20));
      expect((push20.weekday, push20.hour, push20.minute), (1, 17, 40));
      expect(push20.body, contains('Your Push Day starts in 20 minutes'));
      expect(push20.body, contains('Bench Press'));
      final pull30 = specs.firstWhere((s) => s.id == ReminderIds.gym(2, 30));
      expect((pull30.weekday, pull30.hour, pull30.minute), (1, 23, 40));
      final again = planGymReminders(schedule: const [ScheduleDay(weekday: 1, timeLocal: '18:00')], offsetsMinutes: [20], history: const []);
      expect(again.single.id, push20.id); // re-scheduling replaces, never duplicates
      for (final s in specs) {
        expect(s.id, inInclusiveRange(ReminderIds.gymRange.$1, ReminderIds.gymRange.$2));
      }
    });
  });

  group('Nutrition', () {
    test('totals multiply by quantity and flag missing values', () {
      final t = NutritionTotals.of([
        const Meal(id: 'm', day: '2026-10-25', category: 'morning', entries: [
          FoodEntry(id: 'a', foodName: 'Eggs', quantity: 3, calories: 70, proteinG: 6),
          FoodEntry(id: 'b', foodName: 'Oats', quantity: 1),
          FoodEntry(id: 'c', foodName: 'Milk', quantity: 1, calories: 120, proteinG: 8, isEstimate: true),
        ]),
      ]);
      expect(t.calories, 330);
      expect(t.protein, 26);
      expect(t.missing, 1);
      expect(t.estimates, isTrue);
      expect(t.mealsLogged, 1);
    });
  });

  group('Exercise catalogue', () {
    final asset = jsonDecode(File('assets/data/exercises.json').readAsStringSync()) as Map<String, dynamic>;
    final ids = {for (final e in asset['exercises'] as List) e['id'] as String};

    test('app asset matches backend catalogue', () {
      expect(File('assets/data/exercises.json').readAsStringSync(), File('backend/app/data/exercises.json').readAsStringSync());
    });
    test('every exercise has a bundled demo video', () {
      for (final e in asset['exercises'] as List) {
        final url = e['media_url'] as String;
        expect(url, startsWith('asset:videos/'));
        expect(File('assets/${url.substring(6)}').existsSync(), isTrue, reason: e['id'] as String);
      }
    });
    test('every preset and alternative references a real exercise', () {
      for (final p in splitPresets) {
        for (final d in p.days) {
          for (final t in d.exercises) {
            expect(ids, contains(t.exerciseRef), reason: '${p.type}/${d.name}');
          }
        }
      }
      for (final e in asset['exercises'] as List) {
        for (final a in e['alternatives'] as List) {
          expect(ids, contains(a), reason: 'alternative of ${e['id']}');
        }
        expect((e['instructions'] as List), isNotEmpty);
      }
      for (final refs in extraGroupExercises.values) {
        for (final r in refs) {
          expect(ids, contains(r));
        }
      }
    });
  });

  group('Export', () {
    test('CSV escapes values and lists every set', () {
      final s = session(start: DateTime.utc(2026, 10, 20, 18), name: 'Push, heavy');
      final csv = workoutSetsCsv([s]).trim().split('\n');
      expect(csv.first, startsWith('date,workout,exercise'));
      expect(csv, hasLength(4));
      expect(csv[1], contains('"Push, heavy"'));
    });
  });

  group('Session JSON', () {
    test('round trip and API payload excludes local-only fields', () {
      final s = session(start: DateTime(2026, 10, 20)).copyWith(pausedTotalS: 60);
      final back = WorkoutSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.exercises.single.sets, hasLength(3));
      expect(back.pausedTotalS, 60);
      expect(s.toApi().containsKey('paused_total_s'), isFalse);
      expect(s.toApi().containsKey('id'), isFalse);
      expect(back.elapsed().inMinutes, 49);
    });
  });
}
