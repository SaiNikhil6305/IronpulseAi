import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_screens.dart';
import '../../notifications/data/reminder_sync.dart';
import '../../profile/domain/profile.dart';
import '../data/workout_repository.dart';
import '../domain/split.dart';
import '../domain/workout_models.dart';

/// Saves a split; during onboarding also creates a starter schedule and completes onboarding.
Future<void> applySplit(WidgetRef ref, WorkoutSplit split, {required bool onboarding}) async {
  final repo = ref.read(workoutRepositoryProvider);
  await repo.saveSplit(split);
  final profile = ref.read(profileProvider) ?? Profile.empty;
  final hasSchedule = await ref.read(localDbProvider).getDoc(Col.meta, Meta.schedule) != null;
  if (!hasSchedule) {
    final time = profile.preferredGymTime;
    await repo.saveSchedule([
      for (var wd = 1; wd <= 7; wd++)
        () {
          final day = split.days.where((d) => d.weekdays.contains(wd)).firstOrNull;
          return ScheduleDay(weekday: wd, isRestDay: day == null, timeLocal: day == null ? null : time,
              workoutDayName: day?.name);
        }()
    ]);
  }
  if (onboarding) {
    final writer = ref.read(dataWriterProvider);
    for (final c in ['privacy_policy', 'terms']) {
      await writer.enqueue('POST', '/v1/consents', {'consent_type': c, 'version': '2026-10-draft', 'granted': true});
    }
    await ref.read(localDbProvider).deleteDoc(Col.meta, Meta.onboardingDraft);
    await ref.read(profileRepositoryProvider).completeOnboarding(profile);
  }
  await ref.read(reminderSyncProvider).resyncAll();
}

class SplitSelectScreen extends ConsumerWidget {
  const SplitSelectScreen({super.key, this.onboarding = false});
  final bool onboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(activeSplitProvider);
    return Scaffold(
      appBar: AppBar(title: Text(onboarding ? 'Choose your split' : 'Workout split')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
          Text(
            onboarding
                ? 'Pick a starting point. Every day, exercise and rest day can be edited later.'
                : 'Changing your split never deletes past workouts.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (current != null && !onboarding) ...[
            const SectionHeader('Current'),
            AppCard(
              borderColor: AppColors.accent,
              onTap: () => context.push('/split/edit', extra: current),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(current.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(current.days.map((d) => d.name).join(' · '), style: const TextStyle(color: AppColors.textMuted)),
                  ]),
                ),
                const Icon(Icons.edit_outlined, color: AppColors.accent),
              ]),
            ),
            const SectionHeader('Switch to'),
          ] else
            const SizedBox(height: Gaps.lg),
          for (final p in splitPresets) ...[
            _PresetCard(preset: p, onboarding: onboarding),
            const SizedBox(height: Gaps.md),
          ],
        ]),
      ),
    );
  }
}

class _PresetCard extends ConsumerWidget {
  const _PresetCard({required this.preset, required this.onboarding});
  final SplitPreset preset;
  final bool onboarding;

  IconData get _icon => switch (preset.type) {
        'ppl' => Icons.view_week_rounded,
        'bro' => Icons.calendar_view_day_rounded,
        'upper_lower' => Icons.swap_vert_rounded,
        'full_body' => Icons.accessibility_new_rounded,
        _ => Icons.tune_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => _preview(context, ref),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: AppColors.accentMuted, borderRadius: BorderRadius.circular(14)),
          child: Icon(_icon, color: AppColors.accent),
        ),
        const SizedBox(width: Gaps.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(preset.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(preset.subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            if (preset.type != 'custom') ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final d in preset.days) Pill(d.name)]),
            ],
          ]),
        ),
        const Icon(Icons.chevron_right, color: AppColors.textMuted),
      ]),
    );
  }

  WorkoutSplit _build(WidgetRef ref) {
    final profile = ref.read(profileProvider);
    return WorkoutSplit(
      id: newId(),
      name: preset.title,
      splitType: preset.type,
      days: assignWeekdays(preset.days, profile?.trainingDays ?? const []),
    );
  }

  void _preview(BuildContext context, WidgetRef ref) {
    final split = _build(ref);
    if (preset.type == 'custom') {
      context.push(onboarding ? '/onboarding/split-edit' : '/split/edit', extra: split);
      return;
    }
    final index = ref.read(exerciseIndexProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(Gaps.lg), children: [
          Text(preset.title, style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: Gaps.sm),
          Text(preset.subtitle, style: const TextStyle(color: AppColors.textMuted)),
          for (final d in split.days) ...[
            SectionHeader(d.name,
                subtitle: '${d.muscleGroups.map(muscleLabel).join(', ')} · '
                    '${d.weekdays.isEmpty ? 'rotation' : d.weekdays.map((w) => Dates.weekdayName(w, short: true)).join(', ')}'),
            for (final t in d.exercises)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.circle, size: 6, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(index[t.exerciseRef]?.name ?? t.exerciseRef)),
                  Text('${t.targetSets} × ${t.targetReps ?? '—'}', style: const TextStyle(color: AppColors.textMuted)),
                ]),
              ),
          ],
          const SizedBox(height: Gaps.xl),
          FilledButton(
            onPressed: () async {
              await applySplit(ref, split, onboarding: onboarding);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!onboarding && context.mounted) {
                showSnack(context, '${split.name} is now your active split.');
                context.pop();
              }
            },
            child: const Text('Use this split'),
          ),
          const SizedBox(height: Gaps.sm),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push(onboarding ? '/onboarding/split-edit' : '/split/edit', extra: split);
            },
            child: const Text('Customise first'),
          ),
        ]),
      ),
    );
  }
}

class SplitEditorScreen extends ConsumerStatefulWidget {
  const SplitEditorScreen({super.key, this.initial, this.onboarding = false});
  final WorkoutSplit? initial;
  final bool onboarding;

  @override
  ConsumerState<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends ConsumerState<SplitEditorScreen> {
  late WorkoutSplit _split;
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _split = widget.initial ??
        ref.read(activeSplitProvider) ??
        WorkoutSplit(id: newId(), name: 'My split', splitType: 'custom', days: const [SplitDay(name: 'Day 1')]);
    _name = TextEditingController(text: _split.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setDay(int i, SplitDay d) => setState(() => _split = _split.copyWith(days: [..._split.days]..[i] = d));

  Future<void> _renameDay(int i) async {
    final c = TextEditingController(text: _split.days[i].name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Day name'),
        content: TextField(controller: c, autofocus: true, maxLength: 60, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) _setDay(i, _split.days[i].copyWith(name: name));
  }

  Future<void> _save() async {
    if (_split.days.isEmpty) return showSnack(context, 'Add at least one workout day.', error: true);
    final names = _split.days.map((d) => d.name.trim().toLowerCase()).toSet();
    if (names.length != _split.days.length) return showSnack(context, 'Each day needs a unique name.', error: true);
    setState(() => _saving = true);
    final split = _split.copyWith(name: _name.text.trim().isEmpty ? 'My split' : _name.text.trim());
    await applySplit(ref, split, onboarding: widget.onboarding);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!widget.onboarding) {
      showSnack(context, 'Split saved.');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(exerciseIndexProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit split'), actions: [
        TextButton(onPressed: _saving ? null : _save, child: const Text('SAVE')),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _split.days.length >= 7
            ? null
            : () => setState(() => _split = _split.copyWith(days: [..._split.days, SplitDay(name: 'Day ${_split.days.length + 1}')])),
        icon: const Icon(Icons.add),
        label: const Text('Add day'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, 96), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Split name'), maxLength: 60),
          for (var i = 0; i < _split.days.length; i++) ...[
            const SizedBox(height: Gaps.md),
            _dayCard(i, index),
          ],
        ]),
      ),
    );
  }

  Widget _dayCard(int i, Map<String, Exercise> index) {
    final d = _split.days[i];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(d.name, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Rename', onPressed: () => _renameDay(i)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove day',
            onPressed: () => setState(() => _split = _split.copyWith(days: [..._split.days]..removeAt(i))),
          ),
        ]),
        const Text('Training days', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var wd = 1; wd <= 7; wd++)
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(Dates.weekdayName(wd, short: true)),
              selected: d.weekdays.contains(wd),
              onSelected: (on) {
                // A weekday belongs to at most one split day; unselected weekdays are rest days.
                final days = [
                  for (var j = 0; j < _split.days.length; j++)
                    j == i
                        ? d.copyWith(weekdays: on ? ([...d.weekdays, wd]..sort()) : (d.weekdays.where((x) => x != wd).toList()))
                        : _split.days[j].copyWith(weekdays: _split.days[j].weekdays.where((x) => !(on && x == wd)).toList()),
                ];
                setState(() => _split = _split.copyWith(days: days));
              },
            ),
        ]),
        const SizedBox(height: Gaps.md),
        const Text('Muscle groups', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final m in muscleLabels.keys.where((m) => m != 'other'))
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(muscleLabel(m)),
              selected: d.muscleGroups.contains(m),
              onSelected: (on) => _setDay(i, d.copyWith(
                  muscleGroups: on ? [...d.muscleGroups, m] : d.muscleGroups.where((x) => x != m).toList())),
            ),
        ]),
        const SizedBox(height: Gaps.md),
        const Text('Exercises', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final list = [...d.exercises];
            final item = list.removeAt(a);
            list.insert(b, item);
            _setDay(i, d.copyWith(exercises: list));
          },
          children: [
            for (var j = 0; j < d.exercises.length; j++)
              ListTile(
                key: ValueKey('${d.name}-$j-${d.exercises[j].exerciseRef}'),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(index: j, child: const Icon(Icons.drag_indicator)),
                title: Text(index[d.exercises[j].exerciseRef]?.name ?? d.exercises[j].exerciseRef),
                subtitle: Text('${d.exercises[j].targetSets} sets · ${d.exercises[j].targetReps ?? 'any reps'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Fewer sets',
                    onPressed: d.exercises[j].targetSets <= 1
                        ? null
                        : () => _setDay(i, d.copyWith(exercises: [...d.exercises]..[j] = TemplateExercise(
                              exerciseRef: d.exercises[j].exerciseRef,
                              targetSets: d.exercises[j].targetSets - 1,
                              targetReps: d.exercises[j].targetReps))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'More sets',
                    onPressed: d.exercises[j].targetSets >= 12
                        ? null
                        : () => _setDay(i, d.copyWith(exercises: [...d.exercises]..[j] = TemplateExercise(
                              exerciseRef: d.exercises[j].exerciseRef,
                              targetSets: d.exercises[j].targetSets + 1,
                              targetReps: d.exercises[j].targetReps))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove',
                    onPressed: () => _setDay(i, d.copyWith(exercises: [...d.exercises]..removeAt(j))),
                  ),
                ]),
              ),
          ],
        ),
        TextButton.icon(
          onPressed: d.exercises.length >= 20
              ? null
              : () async {
                  final ex = await showExercisePicker(context, muscleHint: d.muscleGroups.firstOrNull);
                  if (ex != null) {
                    _setDay(i, d.copyWith(exercises: [...d.exercises, TemplateExercise(exerciseRef: ex.id, targetReps: '8-12')]));
                  }
                },
          icon: const Icon(Icons.add),
          label: const Text('Add exercise'),
        ),
      ]),
    );
  }
}
