import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/data/account_repo.dart';
import 'package:ironpulse/data/db.dart';
import 'package:ironpulse/data/nutrition_repo.dart';
import 'package:ironpulse/data/repo.dart';
import 'package:ironpulse/data/splits.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppDb.resetForTests();
  });

  test('backup -> wipe -> restore gives back the same data', () async {
    await Repo.createProfile({'name': 'Nikhil', 'weekly_target': 4});
    await Repo.saveSplit('ppl', splitTemplates().first.days);
    await Repo.addCustomExercise('Landmine Press', 'shoulders', 'Barbell');
    final custom = (await Repo.exercises(query: 'Landmine')).single.id;
    final sid = await Repo.startSession(dayIndex: 0, dayName: 'Push Day', exerciseIds: ['bench', custom]);
    final sets = (await Repo.loadSession(sid)).expand((e) => e.sets).toList();
    for (final s in sets.take(2)) {
      await Repo.updateSet(s.id, 50, 8);
      await Repo.setDone(s.id, true);
    }
    await Repo.finishSession(sid, 'felt strong');
    await NutritionRepo.saveEntry(day: '2026-10-26', meal: 'night', name: 'Paneer', protein: 18);
    await NutritionRepo.logWeight(DateTime(2026, 10, 26), 74.5, null);

    final backup = await AccountRepo.exportData();
    final xpBefore = await Repo.xpTotal();

    await AccountRepo.deleteAllLocalData();
    expect(await Repo.profile(), isNull);

    await AccountRepo.importData(Map<String, dynamic>.from(backup));
    expect((await Repo.profile())!['name'], 'Nikhil');
    expect(await Repo.xpTotal(), xpBefore);
    expect((await Repo.doneSessions()).single.notes, 'felt strong');
    expect((await Repo.exercises(query: 'Landmine')).single.id, custom, reason: 'custom exercises restored');
    final restoredSets = (await Repo.loadSession(sid)).expand((e) => e.sets).where((s) => s.done).length;
    expect(restoredSets, 2);
    expect((await NutritionRepo.entries('2026-10-26')).single.name, 'Paneer');
    expect((await NutritionRepo.weights()).single.kg, 74.5);
    expect((await Repo.nextDay())!.$2.name, 'Pull Day', reason: 'rotation continues after restore');
  });

  test('restore rejects files that are not IronPulse backups and keeps current data', () async {
    await Repo.createProfile({'name': 'Keep me', 'weekly_target': 3});
    expect(() => AccountRepo.importData({'app': 'Other'}), throwsFormatException);
    expect((await Repo.profile())!['name'], 'Keep me');
  });

  test('backups from a newer app version with unknown columns still restore', () async {
    await Repo.createProfile({'name': 'A', 'weekly_target': 3});
    final backup = Map<String, dynamic>.from(await AccountRepo.exportData());
    final p = Map<String, Object?>.from((backup['profile'] as List).first as Map)..['future_column'] = 'x';
    backup['profile'] = [p];
    await AccountRepo.importData(backup);
    expect((await Repo.profile())!['name'], 'A');
  });
}
