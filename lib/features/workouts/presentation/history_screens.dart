import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../exercises/presentation/exercise_screens.dart';
import '../../profile/domain/profile.dart';
import '../data/active_workout_controller.dart';
import '../data/workout_repository.dart';
import 'workout_tab.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(completedSessionsProvider);
    final units = ref.watch(unitsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: sessions.isEmpty
          ? const EmptyState(icon: Icons.history, title: 'No workouts yet', message: 'Finish a workout to see it here.')
          : ListView.builder(
              padding: const EdgeInsets.all(Gaps.lg),
              itemCount: sessions.length,
              itemBuilder: (_, i) => SessionTile(session: sessions[i], units: units),
            ),
    );
  }
}

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionByIdProvider(sessionId));
    final units = ref.watch(unitsProvider);
    if (s == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.help_outline, title: 'Workout not found'));
    final active = ref.watch(activeWorkoutProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(s.name), actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              final ok = await confirmDialog(context,
                  title: 'Delete this workout?',
                  message: 'Its sets and the XP it earned will be removed. This cannot be undone.',
                  confirm: 'Delete',
                  destructive: true);
              if (ok) {
                await ref.read(workoutRepositoryProvider).deleteSession(s.id);
                if (context.mounted) context.pop();
              }
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete workout'))],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        Text(
          '${Dates.friendly(s.startedAt)} · ${Units.durationWords(s.elapsed())} · ${s.completedSets.length} sets · '
          '${Units.volume(s.volumeKg, units)} volume',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        if (s.extraMuscleGroups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Extras: ${s.extraMuscleGroups.join(', ')}', style: const TextStyle(color: AppColors.textMuted)),
          ),
        const SizedBox(height: Gaps.lg),
        for (final e in s.exercises) ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.exerciseName, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
              const SizedBox(height: 6),
              if (e.sets.isEmpty) const Text('No sets', style: TextStyle(color: AppColors.textMuted)),
              for (var i = 0; i < e.sets.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(color: AppColors.textMuted))),
                    Expanded(child: Text(setLabel(e.sets[i], units))),
                    if (e.sets[i].rpe != null) Text('RPE ${Units.trimNum(e.sets[i].rpe!)}  ', style: const TextStyle(color: AppColors.textMuted)),
                    Icon(e.sets[i].completed ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18, color: e.sets[i].completed ? AppColors.success : AppColors.textMuted),
                  ]),
                ),
              if (e.notes?.isNotEmpty == true) Text('📝 ${e.notes}', style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(height: Gaps.sm),
        ],
        if (s.notes?.isNotEmpty == true) ...[const SectionHeader('Notes'), Text(s.notes!)],
        const SizedBox(height: Gaps.lg),
        if (active == null)
          FilledButton.icon(
            onPressed: () => repeatWorkout(context, ref, s),
            icon: const Icon(Icons.replay),
            label: const Text('Repeat this workout'),
          ),
      ]),
    );
  }
}
