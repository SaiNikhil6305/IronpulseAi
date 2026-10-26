import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/logic/progress.dart';

void main() {
  group('levels', () {
    test('starts as Rookie', () {
      final l = levelFor(0);
      expect(l.current.name, 'Rookie');
      expect(l.xpToNext, 250);
    });
    test('crosses thresholds exactly', () {
      expect(levelFor(249).current.name, 'Rookie');
      expect(levelFor(250).current.name, 'Gym Beginner');
      expect(levelFor(6000).current.name, 'Elite Grinder');
      expect(levelFor(6000).next, isNull);
    });
  });

  group('weekly streaks', () {
    final now = DateTime(2026, 10, 25); // Sunday
    DateTime d(int m, int day) => DateTime(2026, m, day, 18);

    test('rest days do not break a streak', () {
      final s = streaks([d(10, 6), d(10, 9), d(10, 13), d(10, 16), d(10, 20), d(10, 23)], 2, now: now);
      expect(s.current, 3);
      expect(s.longest, 3);
    });
    test('unfinished current week does not break the streak', () {
      final s = streaks([d(10, 13), d(10, 15), d(10, 20)], 2, now: now);
      expect(s.thisWeek, 1);
      expect(s.current, 1);
    });
    test('a missed week resets current but keeps longest', () {
      final s = streaks([d(9, 29), d(10, 1), d(10, 6), d(10, 8), d(10, 20), d(10, 22)], 2, now: now);
      expect(s.current, 1);
      expect(s.longest, 2);
    });
    test('empty history', () {
      final s = streaks([], 3, now: now);
      expect(s.current, 0);
      expect(s.longest, 0);
    });
  });

  test('week keys start on Monday', () {
    expect(weekKey(DateTime(2026, 10, 25)), '2026-10-19');
    expect(weekKey(DateTime(2026, 10, 19)), '2026-10-19');
  });
}
