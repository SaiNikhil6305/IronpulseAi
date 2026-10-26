import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/data/db.dart';
import 'package:ironpulse/data/repo.dart';
import 'package:ironpulse/data/splits.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _session() async {
  final next = (await Repo.nextDay())!;
  final ids = await Repo.defaultExerciseIds(next.$2.muscles);
  return Repo.startSession(dayIndex: next.$1, dayName: next.$2.name, exerciseIds: ids);
}

Future<WSet> _logSet(String sid, {double w = 40, int r = 10}) async {
  final s = (await Repo.loadSession(sid)).first.sets.firstWhere((x) => !x.done);
  await Repo.updateSet(s.id, w, r);
  await Repo.setDone(s.id, true);
  return s;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await AppDb.resetForTests();
    await Repo.createProfile({'name': 'Test', 'weekly_target': 3});
    await Repo.saveSplit('ppl', splitTemplates().first.days);
  });

  test('re-checking a set never awards XP twice', () async {
    final sid = await _session();
    final s = await _logSet(sid);
    await Repo.setDone(s.id, true);
    await Repo.setDone(s.id, false);
    await Repo.setDone(s.id, true);
    expect(await Repo.xpTotal(), XpRules.set);
  });

  test('add-complete-remove loop cannot farm XP', () async {
    final sid = await _session();
    final se = (await Repo.loadSession(sid)).first;
    for (var i = 0; i < 5; i++) {
      final s = await Repo.addSet(se.id);
      await Repo.updateSet(s.id, 20, 8);
      await Repo.setDone(s.id, true);
      await Repo.removeSet(s.id);
    }
    expect(await Repo.xpTotal(), 0);
  });

  test('finishing twice gives workout XP once and rotation advances', () async {
    final sid = await _session();
    await _logSet(sid);
    final a = await Repo.finishSession(sid, null);
    final b = await Repo.finishSession(sid, null);
    expect(a!.xp, XpRules.set + XpRules.workout);
    expect(b!.xp, XpRules.set);
    expect(await Repo.xpTotal(), XpRules.set + XpRules.workout);
    expect((await Repo.nextDay())!.$2.name, 'Pull Day');
  });

  test('empty workouts are discarded with no XP', () async {
    final sid = await _session();
    expect(await Repo.finishSession(sid, null), isNull);
    expect(await Repo.activeSession(), isNull);
    expect(await Repo.xpTotal(), 0);
  });

  test('unfinished workout can be resumed, discard removes its XP', () async {
    final sid = await _session();
    await _logSet(sid);
    expect((await Repo.activeSession())!.id, sid);
    await Repo.discardSession(sid);
    expect(await Repo.xpTotal(), 0);
  });

  test('previous performance and personal records use real history', () async {
    var sid = await _session();
    await _logSet(sid, w: 40, r: 10);
    await Repo.finishSession(sid, null);
    final ex = (await Repo.loadSession(sid)).first.exercise.id;
    expect((await Repo.previousSets(ex)).first.weight, 40);

    sid = await Repo.startSession(dayIndex: 0, dayName: 'Push Day', exerciseIds: [ex]);
    final fresh = (await Repo.loadSession(sid)).first.sets.first;
    expect(fresh.weight, isNull, reason: 'previous weights are hints, never pre-filled');
    await _logSet(sid, w: 42.5, r: 8);
    final sum = await Repo.finishSession(sid, null);
    expect(sum!.prs.length, 1);
    expect(await Repo.prCount(), 1);
  });

  test('changing the split keeps history', () async {
    final sid = await _session();
    await _logSet(sid);
    await Repo.finishSession(sid, null);
    await Repo.saveSplit('ul', splitTemplates()[2].days);
    final h = await Repo.doneSessions();
    expect(h.single.dayName, 'Push Day');
  });
}
