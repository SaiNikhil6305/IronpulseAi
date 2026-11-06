import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/units.dart';
import '../../workouts/data/workout_repository.dart';

class WeightEntry {
  const WeightEntry({required this.id, required this.day, required this.weightKg, this.notes});
  final String id;
  final String day;
  final double weightKg;
  final String? notes;

  factory WeightEntry.fromJson(Map<String, dynamic> j) => WeightEntry(
      id: j['id'] as String, day: j['day'] as String, weightKg: (j['weight_kg'] as num).toDouble(),
      notes: j['notes'] as String?);

  Map<String, dynamic> toJson() => {'id': id, 'day': day, 'weight_kg': weightKg, 'notes': notes};
}

const goalTypeLabels = {
  'build_muscle': 'Build muscle',
  'lose_fat': 'Reduce body fat',
  'target_weight': 'Reach a target weight',
  'strength': 'Improve strength',
  'consistency': 'Improve workout consistency',
  'workout_count': 'Complete a workout target',
};

class Goal {
  const Goal(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get type => json['goal_type'] as String;
  String get title => json['title'] as String;
  DateTime get startDate => DateTime.parse(json['start_date'] as String);
  DateTime get targetDate => DateTime.parse(json['target_date'] as String);
  double? get targetValue => (json['target_value'] as num?)?.toDouble();
  double? get startValue => (json['start_value'] as num?)?.toDouble();
  String get status => (json['status'] as String?) ?? 'active';
  String? get notes => json['notes'] as String?;
  List<Map<String, dynamic>> get milestones =>
      [for (final m in (json['milestones'] as List? ?? const [])) Map<String, dynamic>.from(m)];
  Goal copyWith(Map<String, dynamic> c) => Goal({...json, ...c});
}

class GoalProgress {
  const GoalProgress(this.goal, this.current, this.progress, this.daysRemaining);
  final Goal goal;
  final double? current;
  final double? progress; // 0..1 when measurable
  final int daysRemaining;
}

final weightsProvider = Provider<List<WeightEntry>>((ref) {
  final docs = ref.watch(docsProvider(Col.weights)).value ?? const [];
  return [for (final d in docs) WeightEntry.fromJson(d)]..sort((a, b) => a.day.compareTo(b.day));
});

final goalsProvider = Provider<List<GoalProgress>>((ref) {
  final docs = ref.watch(docsProvider(Col.goals)).value ?? const [];
  final weights = ref.watch(weightsProvider);
  final sessions = ref.watch(completedSessionsProvider);
  final today = Dates.dayOnly(DateTime.now());
  final latest = weights.isEmpty ? null : weights.last.weightKg;
  final out = <GoalProgress>[];
  for (final d in docs) {
    final g = Goal(d);
    double? current, progress;
    if (g.type == 'target_weight' && latest != null && g.targetValue != null) {
      current = latest;
      if (g.startValue != null && g.startValue != g.targetValue) {
        progress = (g.startValue! - latest) / (g.startValue! - g.targetValue!);
      }
    } else if (g.type == 'workout_count' && g.targetValue != null && g.targetValue! > 0) {
      current = sessions
          .where((s) {
            final day = Dates.dayOnly(s.startedAt.toLocal());
            return s.validSets.isNotEmpty && !day.isBefore(g.startDate) && !day.isAfter(g.targetDate);
          })
          .length
          .toDouble();
      progress = current / g.targetValue!;
    }
    out.add(GoalProgress(g, current, progress?.clamp(0.0, 1.0).toDouble(),
        g.targetDate.difference(today).inDays.clamp(0, 100000).toInt()));
  }
  out.sort((a, b) => a.goal.targetDate.compareTo(b.goal.targetDate));
  return out;
});

class GoalsRepository {
  GoalsRepository(this.ref);
  final Ref ref;
  DataWriter get _w => ref.read(dataWriterProvider);

  Future<void> saveGoal(Goal g) => _w.save(Col.goals, g.id, g.json, path: '/v1/goals/${g.id}');
  Future<void> deleteGoal(String id) => _w.remove(Col.goals, id, path: '/v1/goals/$id');
  Future<void> saveWeight(WeightEntry w) => _w.save(Col.weights, w.id, w.toJson(), path: '/v1/weights/${w.id}');
  Future<void> deleteWeight(String id) => _w.remove(Col.weights, id, path: '/v1/weights/$id');
}

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) => GoalsRepository(ref));
