import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';

/// User profile, stored with the same snake_case keys as the API's ProfileIn.
class Profile {
  const Profile(this.json);
  final Map<String, dynamic> json;

  static const empty = Profile({
    'display_name': '',
    'goals': <String>[],
    'training_days': <int>[],
    'equipment': <String>[],
    'dietary_preferences': <String>[],
    'units': 'metric',
    'timezone': 'UTC',
    'weekly_target': 3,
    'ai_context_scopes': <String>[],
    'onboarding_completed': false,
  });

  String get displayName => (json['display_name'] as String?) ?? '';
  String? get ageRange => json['age_range'] as String?;
  double? get heightCm => (json['height_cm'] as num?)?.toDouble();
  double? get currentWeightKg => (json['current_weight_kg'] as num?)?.toDouble();
  double? get targetWeightKg => (json['target_weight_kg'] as num?)?.toDouble();
  String? get experience => json['experience'] as String?;
  List<String> get goals => _strings('goals');
  List<int> get trainingDays => [for (final d in (json['training_days'] as List? ?? const [])) (d as num).toInt()];
  String? get preferredGymTime => json['preferred_gym_time'] as String?;
  int? get workoutDurationMin => (json['workout_duration_min'] as num?)?.toInt();
  List<String> get equipment => _strings('equipment');
  List<String> get dietaryPreferences => _strings('dietary_preferences');
  String? get allergies => json['allergies'] as String?;
  String get units => (json['units'] as String?) ?? 'metric';
  String get timezone => (json['timezone'] as String?) ?? 'UTC';
  int get weeklyTarget => (json['weekly_target'] as num?)?.toInt() ?? 3;
  List<String> get aiContextScopes => _strings('ai_context_scopes');
  bool get onboardingCompleted => json['onboarding_completed'] == true;

  List<String> _strings(String k) => [for (final v in (json[k] as List? ?? const [])) '$v'];

  Profile copyWith(Map<String, dynamic> changes) => Profile({...json, ...changes});

  /// Body for PUT /v1/profile (server-managed fields excluded).
  Map<String, dynamic> toApi() => Map.of(json)..remove('onboarding_completed');
}

final profileProvider = Provider<Profile?>((ref) {
  final doc = ref.watch(docProvider((Col.meta, Meta.profile))).value;
  return doc == null ? null : Profile(doc);
});

/// Whether the profile document has been loaded from storage yet.
final profileLoadedProvider = Provider<bool>((ref) => ref.watch(docProvider((Col.meta, Meta.profile))).hasValue);

final unitsProvider = Provider<String>((ref) => ref.watch(profileProvider)?.units ?? 'metric');

class ProfileRepository {
  ProfileRepository(this.ref);
  final Ref ref;

  Future<void> save(Profile p) async {
    await ref.read(dataWriterProvider).save(Col.meta, Meta.profile, p.json, path: '/v1/profile', body: p.toApi());
  }

  Future<void> completeOnboarding(Profile p) async {
    final done = p.copyWith({'onboarding_completed': true});
    await save(done);
    await ref.read(dataWriterProvider).enqueue('POST', '/v1/profile/complete-onboarding', null);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref));
