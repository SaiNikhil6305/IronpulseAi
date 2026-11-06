import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';

/// Tracking modes decide which inputs the logger shows for a set.
enum Tracking { weightReps, reps, duration, distance }

Tracking trackingFrom(String? s) => switch (s) {
      'reps' => Tracking.reps,
      'duration' => Tracking.duration,
      'distance' => Tracking.distance,
      _ => Tracking.weightReps,
    };

String trackingName(Tracking t) => switch (t) {
      Tracking.reps => 'reps',
      Tracking.duration => 'duration',
      Tracking.distance => 'distance',
      Tracking.weightReps => 'weight_reps',
    };

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.primaryMuscle,
    this.secondaryMuscles = const [],
    this.equipment = 'other',
    this.difficulty = 'beginner',
    this.instructions = const [],
    this.safety = const [],
    this.alternatives = const [],
    this.unilateral = false,
    this.tracking = Tracking.weightReps,
    this.mediaUrl,
    this.mediaLicense,
    this.isCustom = false,
  });

  /// Library slug (e.g. `barbell-bench-press`) or `custom:UUID`.
  final String id;
  final String name;
  final String primaryMuscle;
  final List<String> secondaryMuscles;
  final String equipment;
  final String difficulty;
  final List<String> instructions;
  final List<String> safety;
  final List<String> alternatives;
  final bool unilateral;
  final Tracking tracking;
  final String? mediaUrl;
  final String? mediaLicense;
  final bool isCustom;

  factory Exercise.fromCatalog(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        primaryMuscle: j['primary_muscle'] as String,
        secondaryMuscles: [for (final m in (j['secondary_muscles'] as List? ?? const [])) '$m'],
        equipment: (j['equipment'] as String?) ?? 'other',
        difficulty: (j['difficulty'] as String?) ?? 'beginner',
        instructions: [for (final m in (j['instructions'] as List? ?? const [])) '$m'],
        safety: [for (final m in (j['safety'] as List? ?? const [])) '$m'],
        alternatives: [for (final m in (j['alternatives'] as List? ?? const [])) '$m'],
        unilateral: j['unilateral'] == true,
        tracking: trackingFrom(j['tracking'] as String?),
        mediaUrl: j['media_url'] as String?,
        mediaLicense: j['media_license'] as String?,
      );

  /// From a user_exercises document that defines a custom exercise.
  factory Exercise.custom(Map<String, dynamic> j) => Exercise(
        id: 'custom:${j['id']}',
        name: (j['name'] as String?) ?? 'Custom exercise',
        primaryMuscle: (j['primary_muscle'] as String?) ?? 'other',
        equipment: (j['equipment'] as String?) ?? 'other',
        unilateral: j['unilateral'] == true,
        tracking: trackingFrom(j['tracking'] as String?),
        instructions: [if ((j['notes'] as String?)?.isNotEmpty == true) j['notes'] as String],
        isCustom: true,
      );
}

const muscleLabels = <String, String>{
  'chest': 'Chest',
  'shoulders': 'Shoulders',
  'rear_delts': 'Rear delts',
  'triceps': 'Triceps',
  'back': 'Back',
  'biceps': 'Biceps',
  'quads': 'Quads',
  'hamstrings': 'Hamstrings',
  'glutes': 'Glutes',
  'calves': 'Calves',
  'traps': 'Traps',
  'forearms': 'Forearms',
  'core': 'Abs & core',
  'other': 'Other',
};

String muscleLabel(String m) => muscleLabels[m] ?? (m.isEmpty ? m : m[0].toUpperCase() + m.substring(1));

String titleCase(String s) =>
    s.split(RegExp(r'[_\s-]+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

/// The bundled catalogue (assets/data/exercises.json — the same file the backend seeds from).
final exerciseCatalogProvider = FutureProvider<List<Exercise>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/exercises.json');
  final data = jsonDecode(raw) as Map<String, dynamic>;
  return [for (final e in data['exercises'] as List) Exercise.fromCatalog(Map<String, dynamic>.from(e))];
});

/// Library + the user's custom exercises, keyed by id.
final exerciseIndexProvider = Provider<Map<String, Exercise>>((ref) {
  final lib = ref.watch(exerciseCatalogProvider).value ?? const [];
  final user = ref.watch(docsProvider(Col.userExercises)).value ?? const [];
  return {
    for (final e in lib) e.id: e,
    for (final u in user)
      if ((u['name'] as String?)?.isNotEmpty == true && u['library_exercise_id'] == null)
        'custom:${u['id']}': Exercise.custom(u),
  };
});

final favoriteExerciseIdsProvider = Provider<Set<String>>((ref) {
  final user = ref.watch(docsProvider(Col.userExercises)).value ?? const [];
  return {
    for (final u in user)
      if (u['is_favorite'] == true) (u['library_exercise_id'] as String?) ?? 'custom:${u['id']}'
  };
});
