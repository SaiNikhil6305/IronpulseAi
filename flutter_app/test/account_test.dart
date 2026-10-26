import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/data/account_repo.dart';
import 'package:ironpulse/data/ai_repo.dart';
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
    await Repo.createProfile({'name': 'Nikhil', 'weekly_target': 3});
    await Repo.saveSplit('ppl', splitTemplates().first.days);
  });

  test('consent is recorded on every change, never duplicated, with policy version', () async {
    await AiRepo.saveSharing(true, false);
    await AiRepo.saveSharing(true, false); // no change -> no new record
    await AiRepo.saveSharing(false, false);
    await ScheduleRepo.saveReminderPrefs(true, [20]);
    final h = await AccountRepo.consentHistory();
    final training = h.where((c) => c.purpose == 'ai_share_training').toList();
    expect(training.map((c) => c.granted), [false, true]); // newest first
    expect(h.where((c) => c.purpose == 'ai_share_nutrition'), isEmpty, reason: 'never turned on');
    expect(h.every((c) => c.version == policyVersion), isTrue);
  });

  test('export contains the user data and no secrets', () async {
    await AiRepo.saveConfig('https://example.onrender.com', 'super-secret-token');
    await NutritionRepo.saveEntry(day: '2026-10-26', meal: 'morning', name: 'Eggs', protein: 12);
    final sid = await Repo.startSession(dayIndex: 0, dayName: 'Push Day', exerciseIds: ['bench']);
    final set = (await Repo.loadSession(sid)).first.sets.first;
    await Repo.updateSet(set.id, 40, 10);
    await Repo.setDone(set.id, true);
    await Repo.finishSession(sid, null);

    final data = await AccountRepo.exportData();
    expect((data['profile'] as List).single, containsPair('name', 'Nikhil'));
    expect((data['food_entries'] as List).single, containsPair('name', 'Eggs'));
    expect(data.toString(), isNot(contains('super-secret-token')));
    final csv = await AccountRepo.workoutsCsv();
    expect(csv.split('\r\n'), hasLength(2));
    expect(csv, contains('Barbell Bench Press,1,40.0,10'));
  });

  test('CSV escapes commas, quotes and spreadsheet formulas', () {
    final csv = AccountRepo.toCsv(['a', 'b', 'c'], [
      ['Dal, rice', 'He said "hi"', '=HYPERLINK("x")'],
      [-5, null, 'ok'],
    ]);
    final lines = csv.split('\r\n');
    expect(lines[1], '"Dal, rice","He said ""hi""","\'=HYPERLINK(""x"")"');
    expect(lines[2], '-5,,ok', reason: 'negative numbers are not treated as formulas');
  });

  test('delete all data erases database rows and stored tokens', () async {
    await AiRepo.saveConfig('https://example.onrender.com', 'tok');
    await NutritionRepo.logWeight(DateTime.now(), 75, null);
    await AccountRepo.deleteAllLocalData();
    expect(await Repo.profile(), isNull);
    expect(await NutritionRepo.weights(), isEmpty);
    expect((await AiRepo.config()).token, isEmpty);
    expect((await Repo.exercises()).length, greaterThan(30), reason: 'fresh database re-seeds the exercise library');
  });
}
