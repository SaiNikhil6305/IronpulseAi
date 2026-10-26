import 'package:sqflite/sqflite.dart';

import '../logic/progress.dart';
import 'db.dart';
import 'repo.dart';

class XpRules2 {
  static const checklist = 5;
  static const weighIn = 15;
}

const meals = ['morning', 'afternoon', 'night', 'snack'];
const mealLabels = {'morning': 'Morning', 'afternoon': 'Afternoon', 'night': 'Night', 'snack': 'Snacks'};

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime parseDay(String s) => DateTime.parse(s);

String mealForNow([DateTime? t]) {
  final h = (t ?? DateTime.now()).hour;
  return h < 12 ? 'morning' : (h < 17 ? 'afternoon' : 'night');
}

class ChecklistItem {
  final String id, name, category;
  final String? quantity;
  final double? protein, calories;
  final bool active;
  ChecklistItem(this.id, this.name, this.category, this.quantity, this.protein, this.calories, this.active);
  factory ChecklistItem.fromMap(Map<String, Object?> m) => ChecklistItem(
        m['id'] as String,
        m['name'] as String,
        m['category'] as String,
        m['quantity'] as String?,
        (m['protein_g'] as num?)?.toDouble(),
        (m['calories'] as num?)?.toDouble(),
        (m['active'] as int) == 1,
      );
}

class FoodEntry {
  final String id, day, meal, name;
  final String? serving, notes, checklistItemId;
  final double? calories, protein, carbs, fat;
  FoodEntry(this.id, this.day, this.meal, this.name, this.serving, this.calories, this.protein, this.carbs, this.fat,
      this.notes, this.checklistItemId);
  factory FoodEntry.fromMap(Map<String, Object?> m) => FoodEntry(
        m['id'] as String,
        m['day'] as String,
        m['meal'] as String,
        m['name'] as String,
        m['serving'] as String?,
        (m['calories'] as num?)?.toDouble(),
        (m['protein'] as num?)?.toDouble(),
        (m['carbs'] as num?)?.toDouble(),
        (m['fat'] as num?)?.toDouble(),
        m['notes'] as String?,
        m['checklist_item_id'] as String?,
      );
}

class Totals {
  final double calories, protein, carbs, fat;
  final int entries;
  /// True if at least one entry is missing a value, so totals are partial.
  final bool incomplete;
  const Totals(this.calories, this.protein, this.carbs, this.fat, this.entries, this.incomplete);

  static Totals of(Iterable<FoodEntry> list) {
    double c = 0, p = 0, cb = 0, f = 0;
    var missing = false;
    for (final e in list) {
      if (e.calories == null || e.protein == null) missing = true;
      c += e.calories ?? 0;
      p += e.protein ?? 0;
      cb += e.carbs ?? 0;
      f += e.fat ?? 0;
    }
    return Totals(c, p, cb, f, list.length, missing);
  }
}

class Targets {
  final bool enabled;
  final double? calories, protein;
  const Targets(this.enabled, this.calories, this.protein);
}

class WeightEntry {
  final String id, day;
  final double kg;
  final String? notes;
  WeightEntry(this.id, this.day, this.kg, this.notes);
}

class Goal {
  final String id, type, title, startDay, targetDay, status;
  final double? startValue, targetValue;
  final String? notes;
  Goal(this.id, this.type, this.title, this.startDay, this.targetDay, this.startValue, this.targetValue, this.status,
      this.notes);
  factory Goal.fromMap(Map<String, Object?> m) => Goal(
        m['id'] as String,
        m['type'] as String,
        m['title'] as String,
        m['start_day'] as String,
        m['target_day'] as String,
        (m['start_value'] as num?)?.toDouble(),
        (m['target_value'] as num?)?.toDouble(),
        m['status'] as String,
        m['notes'] as String?,
      );
}

const goalTypes = {
  'muscle': 'Build muscle',
  'fat': 'Reduce body fat',
  'weight': 'Reach a target weight',
  'strength': 'Improve strength',
  'consistency': 'Improve workout consistency',
  'workouts': 'Complete a workout target',
};

class NutritionRepo {
  static Future<Database> get _db => AppDb.get();

  static Future<bool> _award(DatabaseExecutor e, String id, int amount, String reason) async {
    final exists = await e.query('xp_tx', columns: ['id'], where: 'id = ?', whereArgs: [id]);
    if (exists.isNotEmpty) return false;
    await e.insert('xp_tx', {'id': id, 'amount': amount, 'reason': reason, 'created_at': nowIso()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  // ---------- Checklist ----------
  static Future<List<ChecklistItem>> items({bool includePaused = true}) async {
    final r = await (await _db)
        .query('checklist_items', where: includePaused ? null : 'active = 1', orderBy: 'position, created_at');
    return r.map(ChecklistItem.fromMap).toList();
  }

  static Future<void> saveItem({
    String? id,
    required String name,
    required String category,
    String? quantity,
    double? protein,
    double? calories,
  }) async {
    final db = await _db;
    final data = {
      'name': name.trim(),
      'category': category,
      'quantity': (quantity ?? '').trim().isEmpty ? null : quantity!.trim(),
      'protein_g': protein,
      'calories': calories,
    };
    if (id == null) {
      final p = await db.rawQuery('SELECT COALESCE(MAX(position), -1) + 1 AS p FROM checklist_items');
      await db.insert('checklist_items',
          {...data, 'id': newId(), 'active': 1, 'position': p.first['p'] as int, 'created_at': nowIso()});
    } else {
      await db.update('checklist_items', data, where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> setItemActive(String id, bool active) async =>
      (await _db).update('checklist_items', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteItem(String id) async {
    final db = await _db;
    await db.delete('xp_tx', where: 'id LIKE ?', whereArgs: ['check:$id:%']);
    await db.delete('food_entries', where: 'checklist_item_id = ?', whereArgs: [id]);
    await db.delete('checklist_items', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Set<String>> doneOn(String day) async {
    final r = await (await _db).query('checklist_done', columns: ['item_id'], where: 'day = ?', whereArgs: [day]);
    return r.map((m) => m['item_id'] as String).toSet();
  }

  /// Completing awards XP once per item per day ("check:<item>:<day>"). Undo removes the XP and any
  /// nutrition entry it created, so toggling repeatedly never adds up.
  static Future<void> setChecked(ChecklistItem item, String day, bool done) async {
    final db = await _db;
    await db.transaction((t) async {
      if (done) {
        await t.insert('checklist_done', {'item_id': item.id, 'day': day, 'done_at': nowIso()},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await _award(t, 'check:${item.id}:$day', XpRules2.checklist, 'Checklist: ${item.name}');
        final hasValues = item.protein != null || item.calories != null;
        final existing =
            await t.query('food_entries', where: 'checklist_item_id = ? AND day = ?', whereArgs: [item.id, day]);
        if (hasValues && existing.isEmpty) {
          await t.insert('food_entries', {
            'id': newId(),
            'day': day,
            'meal': mealForNow(),
            'name': item.name,
            'serving': item.quantity,
            'calories': item.calories,
            'protein': item.protein,
            'checklist_item_id': item.id,
            'created_at': nowIso(),
          });
        }
      } else {
        await t.delete('checklist_done', where: 'item_id = ? AND day = ?', whereArgs: [item.id, day]);
        await t.delete('xp_tx', where: 'id = ?', whereArgs: ['check:${item.id}:$day']);
        await t.delete('food_entries', where: 'checklist_item_id = ? AND day = ?', whereArgs: [item.id, day]);
      }
    });
  }

  /// Completion count per day for the last [days] days.
  static Future<Map<String, int>> checklistHistory(int days) async {
    final since = dayKey(DateTime.now().subtract(Duration(days: days)));
    final r = await (await _db)
        .rawQuery('SELECT day, COUNT(*) AS c FROM checklist_done WHERE day >= ? GROUP BY day', [since]);
    return {for (final m in r) m['day'] as String: m['c'] as int};
  }

  // ---------- Food ----------
  static Future<List<FoodEntry>> entries(String day) async {
    final r = await (await _db).query('food_entries', where: 'day = ?', whereArgs: [day], orderBy: 'created_at');
    return r.map(FoodEntry.fromMap).toList();
  }

  static Future<void> saveEntry({
    String? id,
    required String day,
    required String meal,
    required String name,
    String? serving,
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    String? notes,
  }) async {
    final data = {
      'day': day,
      'meal': meal,
      'name': name.trim(),
      'serving': serving,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'notes': notes,
    };
    final db = await _db;
    if (id == null) {
      await db.insert('food_entries', {...data, 'id': newId(), 'created_at': nowIso()});
    } else {
      await db.update('food_entries', data, where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> deleteEntry(String id) async =>
      (await _db).delete('food_entries', where: 'id = ?', whereArgs: [id]);

  /// Recently logged foods (most recent version of each name) for quick-add.
  static Future<List<FoodEntry>> recentFoods({int limit = 15, String query = ''}) async {
    final r = await (await _db).rawQuery('''
      SELECT f.* FROM food_entries f
      JOIN (SELECT name, MAX(created_at) AS m FROM food_entries WHERE checklist_item_id IS NULL AND name LIKE ?
            GROUP BY LOWER(name)) x ON x.name = f.name AND x.m = f.created_at
      ORDER BY f.created_at DESC LIMIT ?''', ['%$query%', limit]);
    return r.map(FoodEntry.fromMap).toList();
  }

  /// Copies one meal from [fromDay] into [toDay]. Returns number of items copied.
  static Future<int> copyMeal(String fromDay, String toDay, String meal) async {
    final db = await _db;
    final src = await db.query('food_entries',
        where: 'day = ? AND meal = ? AND checklist_item_id IS NULL', whereArgs: [fromDay, meal]);
    for (final m in src) {
      await db.insert('food_entries', {...m, 'id': newId(), 'day': toDay, 'created_at': nowIso()});
    }
    return src.length;
  }

  /// Averages over days that have at least one entry (empty days are not counted as zero).
  static Future<(Totals, int)> weeklyAverage(DateTime end) async {
    final from = dayKey(end.subtract(const Duration(days: 6)));
    final r = await (await _db).query('food_entries', where: 'day >= ? AND day <= ?', whereArgs: [from, dayKey(end)]);
    final list = r.map(FoodEntry.fromMap).toList();
    final days = list.map((e) => e.day).toSet().length;
    if (days == 0) return (const Totals(0, 0, 0, 0, 0, false), 0);
    final t = Totals.of(list);
    return (Totals(t.calories / days, t.protein / days, t.carbs / days, t.fat / days, t.entries, t.incomplete), days);
  }

  static Future<Targets> targets() async {
    final p = await Repo.profile();
    return Targets((p?['targets_enabled'] as int? ?? 0) == 1, (p?['calorie_target'] as num?)?.toDouble(),
        (p?['protein_target'] as num?)?.toDouble());
  }

  static Future<void> saveTargets(Targets t) => Repo.updateProfile(
      {'targets_enabled': t.enabled ? 1 : 0, 'calorie_target': t.calories, 'protein_target': t.protein});

  // ---------- Weight ----------
  static Future<List<WeightEntry>> weights() async {
    final r = await (await _db).query('weights', orderBy: 'day');
    return r
        .map((m) => WeightEntry(
            m['id'] as String, m['day'] as String, (m['weight_kg'] as num).toDouble(), m['notes'] as String?))
        .toList();
  }

  /// One entry per day (re-logging the same day replaces it). Weigh-in XP once per week.
  static Future<bool> logWeight(DateTime day, double kg, String? notes) async {
    final db = await _db;
    final key = dayKey(day);
    var awarded = false;
    await db.transaction((t) async {
      final ex = await t.query('weights', where: 'day = ?', whereArgs: [key]);
      if (ex.isEmpty) {
        await t.insert('weights', {'id': newId(), 'day': key, 'weight_kg': kg, 'notes': notes, 'created_at': nowIso()});
      } else {
        await t.update('weights', {'weight_kg': kg, 'notes': notes}, where: 'day = ?', whereArgs: [key]);
      }
      await t.update('profile', {'weight_kg': kg}, where: 'id = 1');
      awarded = await _award(t, 'weigh:${weekKey(day)}', XpRules2.weighIn, 'Weekly weigh-in');
    });
    return awarded;
  }

  static Future<void> deleteWeight(String id) async => (await _db).delete('weights', where: 'id = ?', whereArgs: [id]);

  // ---------- Goals ----------
  static Future<List<Goal>> goals() async {
    final r = await (await _db).query('goals', orderBy: "status = 'active' DESC, target_day");
    return r.map(Goal.fromMap).toList();
  }

  static Future<void> addGoal(
      {required String type, required String title, required DateTime target, double? targetValue, String? notes}) async {
    double? start;
    if (type == 'weight') {
      final w = await weights();
      start = w.isEmpty ? ((await Repo.profile())?['weight_kg'] as num?)?.toDouble() : w.last.kg;
    }
    await (await _db).insert('goals', {
      'id': newId(),
      'type': type,
      'title': title,
      'start_day': dayKey(DateTime.now()),
      'target_day': dayKey(target),
      'start_value': start,
      'target_value': targetValue,
      'status': 'active',
      'notes': notes,
      'created_at': nowIso(),
    });
  }

  static Future<void> setGoalStatus(String id, String status) async =>
      (await _db).update('goals', {'status': status}, where: 'id = ?', whereArgs: [id]);

  static Future<void> deleteGoal(String id) async => (await _db).delete('goals', where: 'id = ?', whereArgs: [id]);

  /// Measurable progress (0..1) where the goal has a number to measure, otherwise null.
  static Future<(double?, String)> goalProgress(Goal g) async {
    if (g.type == 'weight' && g.targetValue != null) {
      final w = await weights();
      final current = w.isEmpty ? null : w.last.kg;
      if (current == null || g.startValue == null) return (null, 'Log your weight to track this goal');
      final total = g.targetValue! - g.startValue!;
      final done = current - g.startValue!;
      final p = total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
      return (p, 'Now ${fmtW(current)} kg · target ${fmtW(g.targetValue)} kg');
    }
    if ((g.type == 'workouts' || g.type == 'consistency') && g.targetValue != null) {
      final r = await (await _db).rawQuery(
          "SELECT COUNT(*) AS c FROM sessions WHERE status = 'done' AND started_at >= ?", [g.startDay]);
      final c = r.first['c'] as int;
      return ((c / g.targetValue!).clamp(0.0, 1.0), '$c of ${g.targetValue!.toInt()} workouts');
    }
    final start = parseDay(g.startDay), end = parseDay(g.targetDay);
    final total = end.difference(start).inDays;
    final gone = DateTime.now().difference(start).inDays;
    return (null, 'Day ${gone.clamp(0, total)} of $total');
  }
}
