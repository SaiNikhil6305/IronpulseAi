import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse/data/db.dart';
import 'package:ironpulse/data/nutrition_repo.dart';
import 'package:ironpulse/data/repo.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final today = dayKey(DateTime.now());

  setUp(() async {
    await AppDb.resetForTests();
    await Repo.createProfile({'name': 'Test', 'weekly_target': 3});
  });

  Future<ChecklistItem> item({double? protein}) async {
    await NutritionRepo.saveItem(name: 'Protein powder', category: 'supplement', quantity: '1 scoop', protein: protein);
    return (await NutritionRepo.items()).single;
  }

  test('checklist toggling awards XP once and undo removes it', () async {
    final it = await item();
    for (var i = 0; i < 4; i++) {
      await NutritionRepo.setChecked(it, today, true);
    }
    expect(await Repo.xpTotal(), XpRules2.checklist);
    await NutritionRepo.setChecked(it, today, false);
    await NutritionRepo.setChecked(it, today, true);
    expect(await Repo.xpTotal(), XpRules2.checklist);
    expect(await NutritionRepo.doneOn(today), {it.id});
  });

  test('checklist item with protein feeds nutrition once, undo removes it', () async {
    final it = await item(protein: 24);
    await NutritionRepo.setChecked(it, today, true);
    await NutritionRepo.setChecked(it, today, true);
    expect(Totals.of(await NutritionRepo.entries(today)).protein, 24);
    await NutritionRepo.setChecked(it, today, false);
    expect(await NutritionRepo.entries(today), isEmpty);
  });

  test('item without values does not create food entries', () async {
    final it = await item();
    await NutritionRepo.setChecked(it, today, true);
    expect(await NutritionRepo.entries(today), isEmpty);
  });

  test('totals use only recorded values and flag missing ones', () async {
    await NutritionRepo.saveEntry(day: today, meal: 'morning', name: 'Eggs', calories: 140, protein: 12);
    await NutritionRepo.saveEntry(day: today, meal: 'night', name: 'Dal');
    final t = Totals.of(await NutritionRepo.entries(today));
    expect(t.calories, 140);
    expect(t.protein, 12);
    expect(t.incomplete, isTrue);
  });

  test('edit, delete and copy a meal', () async {
    final y = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    await NutritionRepo.saveEntry(day: y, meal: 'morning', name: 'Oats', calories: 300, protein: 10);
    expect(await NutritionRepo.copyMeal(y, today, 'morning'), 1);
    final e = (await NutritionRepo.entries(today)).single;
    await NutritionRepo.saveEntry(id: e.id, day: today, meal: 'morning', name: 'Oats', calories: 350, protein: 12);
    expect((await NutritionRepo.entries(today)).single.calories, 350);
    await NutritionRepo.deleteEntry(e.id);
    expect(await NutritionRepo.entries(today), isEmpty);
    expect((await NutritionRepo.recentFoods()).single.name, 'Oats');
  });

  test('weekly average ignores days with nothing logged', () async {
    final y = dayKey(DateTime.now().subtract(const Duration(days: 3)));
    await NutritionRepo.saveEntry(day: today, meal: 'morning', name: 'A', calories: 2000, protein: 100);
    await NutritionRepo.saveEntry(day: y, meal: 'morning', name: 'B', calories: 1000, protein: 50);
    final (avg, days) = await NutritionRepo.weeklyAverage(DateTime.now());
    expect(days, 2);
    expect(avg.calories, 1500);
  });

  test('weigh-in XP once per week, same day replaces entry', () async {
    final now = DateTime.now();
    expect(await NutritionRepo.logWeight(now, 72.4, null), isTrue);
    expect(await NutritionRepo.logWeight(now, 72.0, null), isFalse);
    expect((await NutritionRepo.weights()).single.kg, 72.0);
    expect(await Repo.xpTotal(), XpRules2.weighIn);
  });

  test('target weight goal measures real progress', () async {
    await NutritionRepo.logWeight(DateTime.now().subtract(const Duration(days: 7)), 80, null);
    await NutritionRepo.addGoal(type: 'weight', title: 'Cut', target: DateTime.now().add(const Duration(days: 60)), targetValue: 76);
    await NutritionRepo.logWeight(DateTime.now(), 78, null);
    final (prog, _) = await NutritionRepo.goalProgress((await NutritionRepo.goals()).single);
    expect(prog, closeTo(0.5, 0.001));
  });

  test('a version 1 database upgrades without losing workouts', () async {
    await AppDb.resetForTests();
    final path = p.join(await getDatabasesPath(), 'ironpulse.db');
    final v1 = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE profile(id INTEGER PRIMARY KEY, name TEXT NOT NULL, weight_kg REAL, height_cm REAL, '
          'experience TEXT, goal TEXT, weekly_target INTEGER NOT NULL DEFAULT 3, rest_seconds INTEGER NOT NULL DEFAULT 90, '
          'split_key TEXT, created_at TEXT NOT NULL)');
      await db.execute("CREATE TABLE sessions(id TEXT PRIMARY KEY, day_index INTEGER, day_name TEXT NOT NULL, "
          "started_at TEXT NOT NULL, ended_at TEXT, status TEXT NOT NULL, notes TEXT)");
      await db.insert('profile', {'id': 1, 'name': 'Old', 'created_at': '2026-01-01'});
      await db.insert('sessions', {'id': 's1', 'day_name': 'Push Day', 'started_at': '2026-10-01T18:00:00', 'status': 'done'});
    });
    await v1.close();
    expect((await Repo.doneSessions()).single.dayName, 'Push Day');
    expect((await NutritionRepo.targets()).enabled, isFalse);
    await NutritionRepo.saveEntry(day: today, meal: 'morning', name: 'Eggs', protein: 12);
    expect((await NutritionRepo.entries(today)).length, 1);
  });
}
