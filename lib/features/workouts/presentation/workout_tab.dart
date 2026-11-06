import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../exercises/domain/exercise.dart';
import '../../profile/domain/profile.dart';
import '../data/active_workout_controller.dart';
import '../data/workout_repository.dart';
import '../domain/split.dart';
import '../domain/workout_models.dart';

/// "Want to train anything extra today?" — affects only this session.
Future<List<String>?> askExtraGroups(BuildContext context) {
  final selected = <String>{};
  const groups = {'traps': 'Traps', 'forearms': 'Forearms', 'core': 'Abs', 'calves': 'Calves'};
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Want to train anything extra today?', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                  'Adds a matching exercise to this session only — your split stays the same.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: Gaps.lg),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in groups.entries)
                      FilterChip(
                        label: Text(g.value),
                        selected: selected.contains(g.key),
                        onSelected: (v) => set(() => v ? selected.add(g.key) : selected.remove(g.key)),
                      ),
                  ],
                ),
                const SizedBox(height: Gaps.sm),
                const Text(
                  'Need something else? Add any exercise from the workout screen.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: Gaps.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: () => Navigator.pop(ctx, <String>[]), child: const Text('Skip')),
                    ),
                    const SizedBox(width: Gaps.md),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, selected.toList()),
                        child: Text(selected.isEmpty ? 'Start workout' : 'Start with ${selected.length} extra'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> startPlannedWorkout(BuildContext context, WidgetRef ref, SplitDay day) async {
  if (ref.read(activeWorkoutProvider).value != null) {
    context.push('/workout/active');
    return;
  }
  final extras = await askExtraGroups(context);
  if (extras == null || !context.mounted) return;
  await ref
      .read(activeWorkoutProvider.notifier)
      .startFromDay(day, ref.read(exerciseIndexProvider), extraGroups: extras);
  if (context.mounted) context.push('/workout/active');
}

Future<void> repeatWorkout(BuildContext context, WidgetRef ref, WorkoutSession previous) async {
  if (ref.read(activeWorkoutProvider).value != null) {
    context.push('/workout/active');
    return;
  }
  await ref.read(activeWorkoutProvider.notifier).repeat(previous);
  if (context.mounted) context.push('/workout/active');
}

Future<void> startEmptyWorkout(BuildContext context, WidgetRef ref) async {
  if (ref.read(activeWorkoutProvider).value != null) {
    context.push('/workout/active');
    return;
  }
  await ref.read(activeWorkoutProvider.notifier).start(name: 'Quick workout');
  if (context.mounted) context.push('/workout/active');
}

class WorkoutTab extends ConsumerWidget {
  const WorkoutTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(activeSplitProvider);
    final plan = ref.watch(todayPlanProvider);
    final active = ref.watch(activeWorkoutProvider).value;
    final history = ref.watch(completedSessionsProvider);
    final units = ref.watch(unitsProvider);
    final index = ref.watch(exerciseIndexProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
        actions: [
          IconButton(
            tooltip: 'Exercise library',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => context.push('/exercises'),
          ),
          IconButton(
            tooltip: 'Edit split',
            icon: const Icon(Icons.view_week_outlined),
            onPressed: () => context.push('/split'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gaps.lg),
        children: [
          if (active != null)
            AppCard(
              borderColor: AppColors.accent,
              onTap: () => context.push('/workout/active'),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill, color: AppColors.accent, size: 36),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Resume ${active.name}', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${active.completedSets.length} sets logged · started ${Dates.friendly(active.startedAt)}',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (split == null)
            EmptyState(
              icon: Icons.view_week_outlined,
              title: 'No split selected',
              message: 'Choose a split to get a planned workout each day.',
              action: 'Choose split',
              onAction: () => context.push('/split'),
            )
          else ...[
            const SectionHeader('Today'),
            if (plan.day != null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.day!.name.toUpperCase(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.day!.muscleGroups.map(muscleLabel).join(' · '),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: Gaps.md),
                    for (final t in plan.day!.exercises)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(child: Text(index[t.exerciseRef]?.name ?? t.exerciseRef)),
                            Text(
                              '${t.targetSets} × ${t.targetReps ?? '—'}',
                              style: const TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Gaps.lg),
                    LoadingButton(
                      label: active != null ? 'Resume workout' : 'Start ${plan.day!.name}',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () => startPlannedWorkout(context, ref, plan.day!),
                    ),
                  ],
                ),
              )
            else
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rest day', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text(
                      'Recovery is part of training. Feel like moving anyway? Pick any day below.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            SectionHeader(
              'Your split · ${split.name}',
              action: 'Edit',
              onAction: () => context.push('/split/edit', extra: split),
            ),
            for (final d in split.days)
              Padding(
                padding: const EdgeInsets.only(bottom: Gaps.sm),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md),
                  onTap: () => startPlannedWorkout(context, ref, d),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              '${d.exercises.length} exercises · '
                              '${d.weekdays.isEmpty ? 'rotation' : d.weekdays.map((w) => Dates.weekdayName(w, short: true)).join(', ')}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_arrow_rounded, color: AppColors.accent),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: Gaps.sm),
          OutlinedButton.icon(
            onPressed: () => startEmptyWorkout(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Start an empty workout'),
          ),
          SectionHeader(
            'History',
            action: history.isEmpty ? null : 'See all',
            onAction: () => context.push('/workout/history'),
          ),
          if (history.isEmpty)
            const Text('Completed workouts will appear here.', style: TextStyle(color: AppColors.textMuted))
          else
            for (final s in history.take(5)) SessionTile(session: s, units: units),
        ],
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, required this.units});
  final WorkoutSession session;
  final String units;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: AppCard(
        padding: const EdgeInsets.all(Gaps.md),
        onTap: () => context.push('/workout/session/${session.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    '${Dates.friendly(session.startedAt)} · ${Units.durationWords(session.elapsed())} · '
                    '${session.completedSets.length} sets · ${Units.volume(session.volumeKg, units)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
