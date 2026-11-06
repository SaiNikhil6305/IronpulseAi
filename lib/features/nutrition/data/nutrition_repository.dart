import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/units.dart';
import '../../workouts/domain/workout_models.dart';

double? _d(Object? v) => (v as num?)?.toDouble();

class FoodEntry {
  const FoodEntry({required this.id, required this.foodName, this.servingSize, this.quantity = 1, this.calories,
      this.proteinG, this.carbsG, this.fatG, this.isEstimate = false, this.notes});
  final String id;
  final String foodName;
  final String? servingSize;
  final double quantity;
  final double? calories; // per serving
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final bool isEstimate;
  final String? notes;

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
        id: j['id'] as String,
        foodName: j['food_name'] as String,
        servingSize: j['serving_size'] as String?,
        quantity: _d(j['quantity']) ?? 1,
        calories: _d(j['calories']),
        proteinG: _d(j['protein_g']),
        carbsG: _d(j['carbs_g']),
        fatG: _d(j['fat_g']),
        isEstimate: j['is_estimate'] == true,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'food_name': foodName,
        'serving_size': servingSize,
        'quantity': quantity,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'is_estimate': isEstimate,
        'notes': notes,
      };

  FoodEntry copyWith({String? id, double? quantity}) => FoodEntry(
      id: id ?? this.id, foodName: foodName, servingSize: servingSize, quantity: quantity ?? this.quantity,
      calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, isEstimate: isEstimate, notes: notes);

  double get totalCalories => (calories ?? 0) * quantity;
  double get totalProtein => (proteinG ?? 0) * quantity;
  double get totalCarbs => (carbsG ?? 0) * quantity;
  double get totalFat => (fatG ?? 0) * quantity;
  bool get hasMissingValues => calories == null || proteinG == null;
}

class Meal {
  const Meal({required this.id, required this.day, required this.category, this.name, this.isSavedTemplate = false,
      this.entries = const []});
  final String id;
  final String day; // yyyy-MM-dd
  final String category; // morning | afternoon | night | snack | custom
  final String? name;
  final bool isSavedTemplate;
  final List<FoodEntry> entries;

  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
        id: j['id'] as String,
        day: j['day'] as String,
        category: j['category'] as String,
        name: j['name'] as String?,
        isSavedTemplate: j['is_saved_template'] == true,
        entries: [for (final e in (j['entries'] as List? ?? const [])) FoodEntry.fromJson(Map<String, dynamic>.from(e))],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'category': category,
        'name': name,
        'is_saved_template': isSavedTemplate,
        'entries': [for (final e in entries) e.toJson()],
      };

  Meal copyWith({List<FoodEntry>? entries, String? name, bool? isSavedTemplate, String? day, String? id,
          String? category}) =>
      Meal(
          id: id ?? this.id,
          day: day ?? this.day,
          category: category ?? this.category,
          name: name ?? this.name,
          isSavedTemplate: isSavedTemplate ?? this.isSavedTemplate,
          entries: entries ?? this.entries);
}

class NutritionTotals {
  const NutritionTotals({this.calories = 0, this.protein = 0, this.carbs = 0, this.fat = 0, this.mealsLogged = 0,
      this.missing = 0, this.estimates = false});
  final double calories, protein, carbs, fat;
  final int mealsLogged;
  final int missing;
  final bool estimates;

  static NutritionTotals of(Iterable<Meal> meals) {
    double c = 0, p = 0, cb = 0, f = 0;
    var logged = 0, missing = 0;
    var est = false;
    for (final m in meals) {
      if (m.entries.isNotEmpty) logged++;
      for (final e in m.entries) {
        c += e.totalCalories;
        p += e.totalProtein;
        cb += e.totalCarbs;
        f += e.totalFat;
        if (e.hasMissingValues) missing++;
        est |= e.isEstimate;
      }
    }
    return NutritionTotals(calories: c, protein: p, carbs: cb, fat: f, mealsLogged: logged, missing: missing,
        estimates: est);
  }
}

class NutritionTargets {
  const NutritionTargets({this.enabled = false, this.calories, this.proteinG, this.carbsG, this.fatG});
  final bool enabled;
  final double? calories, proteinG, carbsG, fatG;

  factory NutritionTargets.fromJson(Map<String, dynamic>? j) => j == null
      ? const NutritionTargets()
      : NutritionTargets(
          enabled: j['enabled'] != false,
          calories: _d(j['calories']),
          proteinG: _d(j['protein_g']),
          carbsG: _d(j['carbs_g']),
          fatG: _d(j['fat_g']));

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'calories': calories, 'protein_g': proteinG, 'carbs_g': carbsG, 'fat_g': fatG};
}

const mealCategories = ['morning', 'afternoon', 'night', 'snack'];
const mealCategoryLabels = {'morning': 'Morning', 'afternoon': 'Afternoon', 'night': 'Night', 'snack': 'Snacks',
  'checklist': 'From checklist'};

final allMealsProvider = Provider<List<Meal>>((ref) {
  final docs = ref.watch(docsProvider(Col.meals)).value ?? const [];
  return [for (final d in docs) Meal.fromJson(d)];
});

final mealsForDayProvider = Provider.family<List<Meal>, String>((ref, day) =>
    ref.watch(allMealsProvider).where((m) => m.day == day && !m.isSavedTemplate).toList());

final savedMealsProvider =
    Provider<List<Meal>>((ref) => ref.watch(allMealsProvider).where((m) => m.isSavedTemplate).toList());

final nutritionTargetsProvider = Provider<NutritionTargets>(
    (ref) => NutritionTargets.fromJson(ref.watch(docProvider((Col.meta, Meta.nutritionTargets))).value));

/// Distinct recent foods (newest first) for quick re-adding.
final recentFoodsProvider = Provider<List<FoodEntry>>((ref) {
  final meals = ref.watch(allMealsProvider).where((m) => !m.isSavedTemplate && m.category != 'checklist').toList()
    ..sort((a, b) => b.day.compareTo(a.day));
  final seen = <String>{};
  final out = <FoodEntry>[];
  for (final m in meals) {
    for (final e in m.entries.reversed) {
      if (seen.add(e.foodName.toLowerCase())) out.add(e);
      if (out.length >= 30) return out;
    }
  }
  return out;
});

class DailyNutrition {
  const DailyNutrition(this.day, this.totals);
  final String day;
  final NutritionTotals totals;
}

/// Per-day totals for the last [days] days (only days with logged meals).
List<DailyNutrition> nutritionHistory(List<Meal> meals, int days, DateTime today) {
  final start = Dates.dayOnly(today).subtract(Duration(days: days - 1));
  final byDay = <String, List<Meal>>{};
  for (final m in meals) {
    if (m.isSavedTemplate) continue;
    final d = DateTime.parse(m.day);
    if (d.isBefore(start)) continue;
    byDay.putIfAbsent(m.day, () => []).add(m);
  }
  final out = [
    for (final e in byDay.entries)
      if (NutritionTotals.of(e.value).mealsLogged > 0) DailyNutrition(e.key, NutritionTotals.of(e.value))
  ]..sort((a, b) => a.day.compareTo(b.day));
  return out;
}

class NutritionRepository {
  NutritionRepository(this.ref);
  final Ref ref;
  static const _uuid = Uuid();

  DataWriter get _w => ref.read(dataWriterProvider);

  Future<void> saveMeal(Meal m) => _w.save(Col.meals, m.id, m.toJson(), path: '/v1/meals/${m.id}');

  Future<void> deleteMeal(String id) => _w.remove(Col.meals, id, path: '/v1/meals/$id');

  /// Add an entry to the day's meal in [category], creating the meal if needed.
  Future<void> addEntry(String day, String category, FoodEntry entry) async {
    final existing = ref.read(mealsForDayProvider(day)).where((m) => m.category == category).firstOrNull;
    final meal = existing ?? Meal(id: newId(), day: day, category: category);
    await saveMeal(meal.copyWith(entries: [...meal.entries, entry]));
  }

  Future<void> updateEntry(Meal meal, FoodEntry entry) =>
      saveMeal(meal.copyWith(entries: [for (final e in meal.entries) e.id == entry.id ? entry : e]));

  Future<void> removeEntry(Meal meal, String entryId) async {
    final rest = meal.entries.where((e) => e.id != entryId).toList();
    if (rest.isEmpty && !meal.isSavedTemplate) {
      await deleteMeal(meal.id);
    } else {
      await saveMeal(meal.copyWith(entries: rest));
    }
  }

  /// Copy a meal (saved meal or a previous day's) into [day]/[category] with fresh ids.
  Future<void> duplicateInto(Meal source, String day, String category) async {
    for (final e in source.entries) {
      await addEntry(day, category, e.copyWith(id: newId()));
    }
  }

  Future<void> saveAsTemplate(Meal source, String name) => saveMeal(Meal(
        id: newId(),
        day: source.day,
        category: source.category,
        name: name,
        isSavedTemplate: true,
        entries: [for (final e in source.entries) e.copyWith(id: newId())],
      ));

  Future<void> saveTargets(NutritionTargets t) =>
      _w.save(Col.meta, Meta.nutritionTargets, t.toJson(), path: '/v1/nutrition/targets');

  /// Deterministic ids keep checklist-driven entries idempotent under toggling.
  String checklistEntryId(String itemId, String day) => _uuid.v5(Namespace.url.value, 'ironpulse:checklist:$itemId:$day');
  String checklistMealId(String day) => _uuid.v5(Namespace.url.value, 'ironpulse:checklist-meal:$day');

  Future<void> setChecklistEntry(String day, String itemId, FoodEntry? entry) async {
    final mealId = checklistMealId(day);
    final entryId = checklistEntryId(itemId, day);
    final doc = await ref.read(localDbProvider).getDoc(Col.meals, mealId);
    final meal = doc == null ? Meal(id: mealId, day: day, category: 'checklist') : Meal.fromJson(doc);
    final rest = meal.entries.where((e) => e.id != entryId).toList();
    final entries = entry == null ? rest : [...rest, entry.copyWith(id: entryId)];
    if (entries.isEmpty) {
      if (doc != null) await deleteMeal(mealId);
    } else {
      await saveMeal(meal.copyWith(entries: entries));
    }
  }
}

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) => NutritionRepository(ref));
