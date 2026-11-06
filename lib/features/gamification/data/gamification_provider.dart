import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/units.dart';
import '../../auth/data/auth_controller.dart';
import '../../checklist/data/checklist_repository.dart';
import '../../goals/data/goals_repository.dart';
import '../../profile/domain/profile.dart';
import '../../workouts/data/workout_repository.dart';
import '../domain/xp_rules.dart';

class GamificationView {
  const GamificationView({required this.level, required this.streak, required this.unlocked,
      required this.records, required this.breakdown, required this.serverConfirmed});
  final LevelInfo level;
  final StreakInfo streak;
  final Map<String, DateTime?> unlocked; // achievement id -> unlocked at (if known)
  final List<PersonalRecord> records;
  final Map<String, int> breakdown;

  /// True when XP comes from the server ledger with nothing left to sync.
  final bool serverConfirmed;
}

final gamificationProvider = Provider<GamificationView>((ref) {
  final sessions = ref.watch(sessionsProvider);
  final profile = ref.watch(profileProvider);
  final weeklyTarget = profile?.weeklyTarget ?? 3;
  final completions = ref.watch(checklistCompletionsProvider);
  final weights = ref.watch(weightsProvider);
  final local = computeLocalXp(
    sessions: sessions,
    checklistCompletions: completions.length,
    weighInDays: [for (final w in weights) DateTime.parse(w.day)],
    weeklyTarget: weeklyTarget,
  );
  final workoutDays = [
    for (final s in sessions)
      if (s.isCompleted && s.validSets.isNotEmpty) Dates.dayOnly(s.startedAt.toLocal())
  ];
  final streak = computeStreaks(workoutDays, weeklyTarget, DateTime.now());

  final server = ref.watch(docProvider((Col.meta, Meta.gamification))).value;
  final sync = ref.watch(syncServiceProvider);
  final canSync = ref.watch(authControllerProvider).canSync;
  final useServer = canSync && server != null && sync.allSynced;

  final unlocked = <String, DateTime?>{for (final id in local.unlocked) id: null};
  if (server != null && canSync) {
    for (final a in (server['achievements'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(a);
      if (m['unlocked_at'] != null) unlocked[m['id'] as String] = DateTime.parse(m['unlocked_at'] as String);
    }
  }
  return GamificationView(
    level: useServer ? LevelInfo.fromServer(Map<String, dynamic>.from(server['level'] as Map)) : LevelInfo.fromXp(local.total),
    streak: streak,
    unlocked: unlocked,
    records: personalRecords(sessions),
    breakdown: local.breakdown,
    serverConfirmed: useServer,
  );
});
