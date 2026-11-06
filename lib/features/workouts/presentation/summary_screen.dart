import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_controller.dart';
import '../../exercises/presentation/exercise_screens.dart';
import '../../gamification/domain/xp_rules.dart';
import '../../profile/domain/profile.dart';
import '../data/workout_repository.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionByIdProvider(sessionId));
    final units = ref.watch(unitsProvider);
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final sessions = ref.watch(sessionsProvider);
    final prs = personalRecords(sessions).where((p) => p.sessionId == s.id).toList();
    final synced = ref.watch(sessionSyncProvider(s.id));
    final canSync = ref.watch(authControllerProvider).canSync;
    final localXp = sessionXp(s);
    final xp = synced?['xp_from_session'] as int? ?? localXp;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Workout complete'),
        actions: [TextButton(onPressed: () => context.go('/home'), child: const Text('DONE'))],
      ),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        Center(
          child: Column(children: [
            const Icon(Icons.emoji_events_rounded, color: AppColors.accent, size: 56),
            const SizedBox(height: Gaps.sm),
            Text(s.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(Dates.friendly(s.startedAt), style: const TextStyle(color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(height: Gaps.xl),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Gaps.md,
          crossAxisSpacing: Gaps.md,
          childAspectRatio: 1.45,
          children: [
            StatTile(label: 'Duration', value: Units.durationWords(s.elapsed()), icon: Icons.timer_outlined),
            StatTile(label: 'Exercises', value: '${s.exercisesCompleted}', icon: Icons.fitness_center),
            StatTile(label: 'Sets', value: '${s.completedSets.length}', icon: Icons.check_circle_outline),
            StatTile(label: 'Reps', value: '${s.totalReps}', icon: Icons.repeat),
            StatTile(
                label: 'Training volume',
                value: Units.volume(s.volumeKg, units),
                caption: 'weight × reps (not calories)',
                icon: Icons.stacked_bar_chart),
            StatTile(
              label: 'XP earned',
              value: '+$xp',
              accent: true,
              icon: Icons.bolt,
              caption: !canSync ? 'calculated on device' : (synced == null ? 'confirming when synced' : 'confirmed by server'),
            ),
          ],
        ),
        if (prs.isNotEmpty) ...[
          const SectionHeader('Personal records'),
          for (final p in prs)
            AppCard(
              borderColor: AppColors.accent,
              padding: const EdgeInsets.all(Gaps.md),
              child: Row(children: [
                const Icon(Icons.military_tech_rounded, color: AppColors.accent),
                const SizedBox(width: Gaps.md),
                Expanded(
                  child: Text('${p.exerciseName}: ${Units.weight(p.weightKg, units)} × ${p.reps}\n'
                      'Est. 1RM ${Units.weight(p.e1rm, units)} (was ${Units.weight(p.previousE1rm, units)})'),
                ),
              ]),
            ),
        ],
        const SectionHeader('Exercises'),
        for (final e in s.exercises.where((e) => e.completedSets.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: Text(e.exerciseName, style: const TextStyle(fontWeight: FontWeight.w700))),
              Expanded(
                flex: 3,
                child: Text(e.completedSets.map((x) => setLabel(x, units)).join(', '),
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            ]),
          ),
        if (s.notes?.isNotEmpty == true) ...[
          const SectionHeader('Notes'),
          Text(s.notes!),
        ],
        const SizedBox(height: Gaps.xl),
        FilledButton(onPressed: () => context.go('/home'), child: const Text('Back to home')),
      ]),
    );
  }
}
