import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/data/db.dart';
import 'package:ironpulse/data/health_repo.dart';
import 'package:ironpulse/data/repo.dart';
import 'package:ironpulse/logic/health_summary.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 10, d, h, m);

void main() {
  test('steps come from platform totals, heart rate is aggregated per day', () {
    final s = summarize([
      RawSample(Sample.heartRate, t(24, 9), t(24, 9), 60),
      RawSample(Sample.heartRate, t(24, 18), t(24, 18), 140),
      RawSample(Sample.heartRate, t(24, 20), t(24, 20), 400), // sensor glitch, ignored
      RawSample(Sample.restingHeartRate, t(24, 7), t(24, 7), 58),
    ], {'2026-10-24': 9500});
    final d = s['2026-10-24']!;
    expect(d.steps, 9500);
    expect(d.hrAvg, 100);
    expect((d.hrMin, d.hrMax), (60.0, 140.0));
    expect(d.restingHr, 58);
  });

  test('sleep counts toward the morning it ends, overlaps are not double counted', () {
    final s = summarize([
      RawSample(Sample.sleep, t(24, 23), t(25, 7), 0), // phone: 8h
      RawSample(Sample.sleep, t(25, 0), t(25, 7, 30), 0), // watch overlaps, extends 30 min
      RawSample(Sample.sleep, t(25, 14), t(25, 14, 20), 0), // nap
    ], {});
    expect(s['2026-10-25']!.sleepMinutes, 8 * 60 + 30 + 20);
    expect(s.containsKey('2026-10-24'), isFalse);
  });

  test('days with nothing produce no rows and formatting is readable', () {
    expect(summarize([], {}), isEmpty);
    expect(fmtSleep(455), '7h 35m');
    expect(fmtSleep(null), '-');
  });

  group('storage', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setUp(() async {
      await AppDb.resetForTests();
      await Repo.createProfile({'name': 'T', 'weekly_target': 3});
    });

    test('re-syncing a day replaces it instead of duplicating', () async {
      final today = healthDayKey(DateTime.now());
      await HealthRepo.saveSummaries([DailyHealth(today)..steps = 1000]);
      await HealthRepo.saveSummaries([DailyHealth(today)..steps = 5200]);
      final r = await HealthRepo.recent();
      expect(r.length, 1);
      expect(r.single.steps, 5200);
    });
  });
}
