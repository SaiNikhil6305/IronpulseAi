import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/data/db.dart';
import 'package:ironpulse/data/repo.dart';
import 'package:ironpulse/logic/schedule.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('rest days get no reminders, each offset once', () {
    final plan = planReminders({1: 18 * 60, 2: null, 3: 18 * 60 + 30}, [30, 10, 10]);
    expect(plan.length, 4);
    expect(plan.map((r) => r.id).toSet().length, 4, reason: 'ids must be unique');
    final mon30 = plan.firstWhere((r) => r.gymWeekday == 1 && r.offset == 30);
    expect((mon30.weekday, mon30.hour, mon30.minute), (1, 17, 30));
  });

  test('re-planning produces identical ids (no duplicates on reschedule)', () {
    final a = planReminders({4: 18 * 60 + 30}, [20, 0]).map((r) => r.id).toList();
    final b = planReminders({4: 18 * 60 + 30}, [0, 20]).map((r) => r.id).toList();
    expect(a, b);
  });

  test('reminder before midnight moves to the previous day', () {
    final mon = planReminders({1: 10}, [30]).single;
    expect((mon.weekday, mon.hour, mon.minute), (7, 23, 40));
  });

  test('nextWeekly picks the upcoming occurrence', () {
    final sun = DateTime(2026, 10, 25, 20, 0); // Sunday 8 PM
    expect(nextWeekly(sun, 1, 17, 30), DateTime(2026, 10, 26, 17, 30));
    expect(nextWeekly(sun, 7, 21, 0), DateTime(2026, 10, 25, 21, 0));
    expect(nextWeekly(sun, 7, 19, 0), DateTime(2026, 11, 1, 19, 0));
  });

  test('reminder text uses real history only', () {
    expect(reminderText('Push Day', 20, []), "Your Push Day starts in 20 minutes. Let's get moving.");
    expect(reminderText('Pull Day', 10, ['Lat Pulldown', 'Seated Cable Row', 'Curl']),
        contains('Last time: Lat Pulldown and Seated Cable Row'));
    expect(fmtClock(18 * 60 + 30), '6:30 PM');
    expect(fmtClock(0), '12:00 AM');
  });

  group('storage', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setUp(() async {
      await AppDb.resetForTests();
      await Repo.createProfile({'name': 'T', 'weekly_target': 3});
    });

    test('schedule and reminder prefs persist', () async {
      expect((await ScheduleRepo.schedule()).values.every((v) => v == null), isTrue);
      await ScheduleRepo.saveSchedule({1: 1080, 2: 1080, 3: null, 4: 1110, 5: 1080, 6: 480, 7: null});
      await ScheduleRepo.saveReminderPrefs(true, [30, 10]);
      final s = await ScheduleRepo.schedule();
      expect(s[4], 1110);
      expect(s[7], isNull);
      final (en, offs) = await ScheduleRepo.reminderPrefs();
      expect(en, isTrue);
      expect(offs, [30, 10]);
    });
  });
}
