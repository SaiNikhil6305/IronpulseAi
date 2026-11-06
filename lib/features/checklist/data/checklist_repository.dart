import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/units.dart';
import '../../nutrition/data/nutrition_repository.dart';
import '../../workouts/domain/workout_models.dart';

class ChecklistItem {
  const ChecklistItem({required this.id, required this.name, required this.category, this.quantity, this.proteinG,
      this.calories, this.reminderTime, this.paused = false, this.position = 0});
  final String id;
  final String name;
  final String category; // food | supplement | habit
  final String? quantity;
  final double? proteinG;
  final double? calories;
  final String? reminderTime;
  final bool paused;
  final int position;

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        quantity: j['quantity'] as String?,
        proteinG: (j['protein_g'] as num?)?.toDouble(),
        calories: (j['calories'] as num?)?.toDouble(),
        reminderTime: j['reminder_time'] as String?,
        paused: j['paused'] == true,
        position: (j['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'quantity': quantity,
        'protein_g': proteinG,
        'calories': calories,
        'reminder_time': reminderTime,
        'paused': paused,
        'position': position,
      };

  ChecklistItem copyWith({bool? paused, int? position}) => ChecklistItem(
      id: id, name: name, category: category, quantity: quantity, proteinG: proteinG, calories: calories,
      reminderTime: reminderTime, paused: paused ?? this.paused, position: position ?? this.position);

  bool get hasNutrition => proteinG != null || calories != null;
}

/// Suggestions only — nothing is added (or implied to be required) until the user chooses it.
const checklistSuggestions = <(String, String)>[
  ('Protein powder', 'supplement'),
  ('Creatine', 'supplement'),
  ('Soya chunks', 'food'),
  ('Milk', 'food'),
  ('Eggs', 'food'),
  ('Drink 3 L water', 'habit'),
];

final checklistItemsProvider = Provider<List<ChecklistItem>>((ref) {
  final docs = ref.watch(docsProvider(Col.checklistItems)).value ?? const [];
  return [for (final d in docs) ChecklistItem.fromJson(d)]..sort((a, b) => a.position.compareTo(b.position));
});

final activeChecklistItemsProvider =
    Provider<List<ChecklistItem>>((ref) => ref.watch(checklistItemsProvider).where((i) => !i.paused).toList());

/// All completion docs (id: `itemId_day`).
final checklistCompletionsProvider =
    Provider<List<Map<String, dynamic>>>((ref) => ref.watch(docsProvider(Col.checklistCompletions)).value ?? const []);

final completedItemIdsProvider = Provider.family<Set<String>, String>((ref, day) => {
      for (final c in ref.watch(checklistCompletionsProvider))
        if (c['day'] == day) c['item_id'] as String
    });

class ChecklistRepository {
  ChecklistRepository(this.ref);
  final Ref ref;
  DataWriter get _w => ref.read(dataWriterProvider);

  Future<void> saveItem(ChecklistItem item) =>
      _w.save(Col.checklistItems, item.id, item.toJson(), path: '/v1/checklist/items/${item.id}');

  Future<void> deleteItem(String id) => _w.remove(Col.checklistItems, id, path: '/v1/checklist/items/$id');

  Future<void> reorder(List<ChecklistItem> items) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].position != i) await saveItem(items[i].copyWith(position: i));
    }
  }

  /// Toggle completion for a day. XP is awarded once per item per day by the
  /// server (and the local mirror); un-ticking removes it, so toggling can't farm XP.
  Future<void> setCompleted(ChecklistItem item, String day, bool completed) async {
    final docId = '${item.id}_$day';
    final db = ref.read(localDbProvider);
    final existing = await db.getDoc(Col.checklistCompletions, docId);
    final completionId = (existing?['id'] as String?) ?? newId();
    final at = DateTime.now().toUtc().toIso8601String();
    if (completed) {
      await db.putDoc(Col.checklistCompletions, docId,
          {'id': completionId, 'item_id': item.id, 'day': day, 'completed_at': existing?['completed_at'] ?? at});
    } else {
      await db.deleteDoc(Col.checklistCompletions, docId);
    }
    await _w.enqueue('PUT', '/v1/checklist/items/${item.id}/completion',
        {'day': day, 'completed': completed, 'completion_id': completionId, 'completed_at': at});
    // Only items with real nutrition values feed the nutrition log.
    if (item.hasNutrition) {
      await ref.read(nutritionRepositoryProvider).setChecklistEntry(
          day,
          item.id,
          completed
              ? FoodEntry(id: '', foodName: item.name, servingSize: item.quantity, quantity: 1,
                  calories: item.calories, proteinG: item.proteinG, notes: 'Logged from checklist')
              : null);
    }
  }

  /// Completion counts per day for the history view.
  static Map<String, int> history(List<Map<String, dynamic>> completions, int days) {
    final cutoff = Dates.iso(DateTime.now().subtract(Duration(days: days)));
    final out = <String, int>{};
    for (final c in completions) {
      final d = c['day'] as String;
      if (d.compareTo(cutoff) >= 0) out.update(d, (v) => v + 1, ifAbsent: () => 1);
    }
    return out;
  }
}

final checklistRepositoryProvider = Provider<ChecklistRepository>((ref) => ChecklistRepository(ref));
