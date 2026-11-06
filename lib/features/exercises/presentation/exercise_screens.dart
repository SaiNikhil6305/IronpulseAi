import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/domain/profile.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/domain/workout_models.dart';
import '../domain/exercise.dart';
import 'exercise_video.dart';

List<Exercise> filterExercises(Iterable<Exercise> all,
    {String query = '', String? muscle, String? equipment, String? difficulty, Set<String>? onlyIds}) {
  final q = query.trim().toLowerCase();
  final out = all.where((e) {
    if (onlyIds != null && !onlyIds.contains(e.id)) return false;
    if (muscle != null && e.primaryMuscle != muscle) return false;
    if (equipment != null && e.equipment != equipment) return false;
    if (difficulty != null && e.difficulty != difficulty) return false;
    if (q.isEmpty) return true;
    return e.name.toLowerCase().contains(q) ||
        muscleLabel(e.primaryMuscle).toLowerCase().contains(q) ||
        e.secondaryMuscles.any((m) => m.contains(q)) ||
        e.equipment.contains(q);
  }).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return out;
}

class _ExerciseBrowser extends ConsumerStatefulWidget {
  const _ExerciseBrowser({required this.onSelect, this.muscleHint, this.scroll, this.picker = false});
  final void Function(Exercise) onSelect;
  final String? muscleHint;
  final ScrollController? scroll;
  final bool picker;

  @override
  ConsumerState<_ExerciseBrowser> createState() => _ExerciseBrowserState();
}

class _ExerciseBrowserState extends ConsumerState<_ExerciseBrowser> {
  String _q = '';
  String? _muscle;
  String? _equipment;
  bool _favorites = false;

  @override
  void initState() {
    super.initState();
    _muscle = widget.muscleHint;
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(exerciseIndexProvider);
    final favs = ref.watch(favoriteExerciseIdsProvider);
    final equipment = {for (final e in index.values) e.equipment}.toList()..sort();
    final list = filterExercises(index.values,
        query: _q, muscle: _muscle, equipment: _equipment, onlyIds: _favorites ? favs : null);
    return CustomScrollView(controller: widget.scroll, slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.sm),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search exercises'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Gaps.lg), children: [
            FilterChip(
              avatar: const Icon(Icons.star_rounded, size: 16),
              label: const Text('Favorites'),
              selected: _favorites,
              onSelected: (v) => setState(() => _favorites = v),
            ),
            const SizedBox(width: 6),
            for (final m in muscleLabels.keys.where((m) => m != 'other')) ...[
              ChoiceChip(
                label: Text(muscleLabel(m)),
                selected: _muscle == m,
                onSelected: (v) => setState(() => _muscle = v ? m : null),
              ),
              const SizedBox(width: 6),
            ],
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Gaps.lg), children: [
            for (final eq in equipment) ...[
              ChoiceChip(
                label: Text(titleCase(eq)),
                selected: _equipment == eq,
                onSelected: (v) => setState(() => _equipment = v ? eq : null),
              ),
              const SizedBox(width: 6),
            ],
          ]),
        ),
      ),
      if (list.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.search_off,
            title: 'No exercises match',
            message: 'Try another filter or create your own exercise.',
            action: 'Create custom exercise',
            onAction: () => _createCustom(context),
          ),
        )
      else
        SliverList.builder(
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == list.length) {
              return Padding(
                padding: const EdgeInsets.all(Gaps.lg),
                child: OutlinedButton.icon(
                    onPressed: () => _createCustom(context), icon: const Icon(Icons.add), label: const Text('Create custom exercise')),
              );
            }
            final e = list[i];
            return ListTile(
              title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${muscleLabel(e.primaryMuscle)} · ${titleCase(e.equipment)} · ${titleCase(e.difficulty)}'),
              leading: CircleAvatar(
                backgroundColor: AppColors.surfaceHigh,
                child: Text(e.name.substring(0, 1), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900)),
              ),
              trailing: favs.contains(e.id)
                  ? const Icon(Icons.star_rounded, color: AppColors.accent)
                  : (e.isCustom ? const Pill('Custom') : null),
              onTap: () => widget.onSelect(e),
            );
          },
        ),
    ]);
  }

  Future<void> _createCustom(BuildContext context) async {
    final ex = await showModalBottomSheet<Exercise>(
        context: context, isScrollControlled: true, builder: (_) => _CustomExerciseSheet(initialName: _q, muscle: _muscle));
    if (ex != null && widget.picker) widget.onSelect(ex);
  }
}

class _CustomExerciseSheet extends ConsumerStatefulWidget {
  const _CustomExerciseSheet({this.initialName = '', this.muscle});
  final String initialName;
  final String? muscle;
  @override
  ConsumerState<_CustomExerciseSheet> createState() => _CustomExerciseSheetState();
}

class _CustomExerciseSheetState extends ConsumerState<_CustomExerciseSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _notes = TextEditingController();
  late String _muscle = widget.muscle ?? 'chest';
  String _equipment = 'other';
  Tracking _tracking = Tracking.weightReps;
  bool _unilateral = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(Gaps.lg), children: [
          Text('Custom exercise', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gaps.lg),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => Validators.required(v, field: 'Name') ?? Validators.maxLength(120)(v),
          ),
          const SizedBox(height: Gaps.md),
          DropdownButtonFormField<String>(
            initialValue: _muscle,
            decoration: const InputDecoration(labelText: 'Primary muscle'),
            items: [for (final m in muscleLabels.keys) DropdownMenuItem(value: m, child: Text(muscleLabel(m)))],
            onChanged: (v) => setState(() => _muscle = v ?? _muscle),
          ),
          const SizedBox(height: Gaps.md),
          DropdownButtonFormField<String>(
            initialValue: _equipment,
            decoration: const InputDecoration(labelText: 'Equipment'),
            items: [
              for (final e in ['barbell', 'dumbbell', 'machine', 'cable', 'bodyweight', 'kettlebell', 'bands', 'other'])
                DropdownMenuItem(value: e, child: Text(titleCase(e)))
            ],
            onChanged: (v) => setState(() => _equipment = v ?? _equipment),
          ),
          const SizedBox(height: Gaps.md),
          SegmentedButton<Tracking>(
            segments: const [
              ButtonSegment(value: Tracking.weightReps, label: Text('Weight×reps')),
              ButtonSegment(value: Tracking.reps, label: Text('Reps')),
              ButtonSegment(value: Tracking.duration, label: Text('Time')),
              ButtonSegment(value: Tracking.distance, label: Text('Distance')),
            ],
            selected: {_tracking},
            onSelectionChanged: (s) => setState(() => _tracking = s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track left and right separately'),
            value: _unilateral,
            onChanged: (v) => setState(() => _unilateral = v),
          ),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes / cues (optional)'), maxLines: 2),
          const SizedBox(height: Gaps.lg),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final id = newId();
              final doc = {
                'id': id,
                'library_exercise_id': null,
                'name': _name.text.trim(),
                'primary_muscle': _muscle,
                'equipment': _equipment,
                'tracking': trackingName(_tracking),
                'unilateral': _unilateral,
                'is_favorite': false,
                'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              };
              await ref.read(dataWriterProvider).save(Col.userExercises, id, doc, path: '/v1/user-exercises/$id');
              if (context.mounted) Navigator.pop(context, Exercise.custom(doc));
            },
            child: const Text('Save exercise'),
          ),
        ]),
      ),
    );
  }
}

Future<Exercise?> showExercisePicker(BuildContext context, {String? muscleHint, String title = 'Add exercise'}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.md),
          child: Align(alignment: Alignment.centerLeft, child: Text(title, style: Theme.of(ctx).textTheme.titleLarge)),
        ),
        Expanded(
          child: _ExerciseBrowser(
            scroll: scroll,
            muscleHint: muscleHint,
            picker: true,
            onSelect: (e) => Navigator.pop(ctx, e),
          ),
        ),
      ]),
    ),
  );
}

class ExerciseLibraryScreen extends ConsumerWidget {
  const ExerciseLibraryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(exerciseCatalogProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise library')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : _ExerciseBrowser(onSelect: (e) => context.push('/exercises/${Uri.encodeComponent(e.id)}')),
    );
  }
}

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(exerciseIndexProvider);
    final e = index[exerciseId];
    final units = ref.watch(unitsProvider);
    if (e == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.help_outline, title: 'Exercise not found'));
    }
    final favs = ref.watch(favoriteExerciseIdsProvider);
    final isFav = favs.contains(e.id);
    final sessions = ref.watch(completedSessionsProvider);
    final history = <(WorkoutSession, List<WorkoutSet>)>[
      for (final s in sessions)
        if (s.exercises.any((x) => x.exerciseRef == e.id))
          (s, [for (final x in s.exercises.where((x) => x.exerciseRef == e.id)) ...x.completedSets])
    ].where((h) => h.$2.isNotEmpty).toList();
    WorkoutSet? best;
    for (final h in history) {
      for (final s in h.$2) {
        if (s.weightKg != null && s.reps != null && s.reps! <= 12 &&
            (best == null || epley1rm(s.weightKg!, s.reps!) > epley1rm(best.weightKg!, best.reps!))) {
          best = s;
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(e.name), actions: [
        IconButton(
          tooltip: isFav ? 'Remove favorite' : 'Add to favorites',
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_outline_rounded, color: isFav ? AppColors.accent : null),
          onPressed: () => _toggleFavorite(ref, e, isFav),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(muscleLabel(e.primaryMuscle), color: AppColors.accent),
          for (final m in e.secondaryMuscles) Pill(muscleLabel(m)),
          Pill(titleCase(e.equipment)),
          Pill(titleCase(e.difficulty)),
          if (e.unilateral) const Pill('Unilateral'),
        ]),
        if (demoAssetPath(e) != null) ...[
          const SizedBox(height: Gaps.lg),
          ExerciseVideo(assetPath: demoAssetPath(e)!),
          const SizedBox(height: 6),
          Text(e.mediaLicense ?? '', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
        if (e.instructions.isNotEmpty) ...[
          const SectionHeader('How to'),
          for (var i = 0; i < e.instructions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}.', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Expanded(child: Text(e.instructions[i])),
              ]),
            ),
        ],
        if (e.safety.isNotEmpty) ...[
          const SectionHeader('Safety'),
          for (final s in e.safety)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.shield_outlined, size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(child: Text(s)),
              ]),
            ),
        ],
        if (e.alternatives.isNotEmpty) ...[
          const SectionHeader('Alternatives'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in e.alternatives)
              if (index[a] != null)
                ActionChip(label: Text(index[a]!.name), onPressed: () => context.push('/exercises/${Uri.encodeComponent(a)}')),
          ]),
        ],
        const SectionHeader('Your history'),
        if (history.isEmpty)
          const Text('No completed sets recorded yet.', style: TextStyle(color: AppColors.textMuted))
        else ...[
          if (best != null)
            StatTile(
              label: 'Best set (by estimated 1RM)',
              value: '${Units.weight(best.weightKg, units)} × ${best.reps}',
              caption: 'Estimated 1RM ${Units.weight(epley1rm(best.weightKg!, best.reps!), units)} (Epley formula, an estimate)',
              accent: true,
            ),
          const SizedBox(height: Gaps.md),
          for (final h in history.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(Dates.friendly(h.$1.startedAt)),
              subtitle: Text(h.$2.map((s) => _setLabel(s, units)).join('  ·  ')),
              onTap: () => context.push('/workout/session/${h.$1.id}'),
            ),
        ],
      ]),
    );
  }

  Future<void> _toggleFavorite(WidgetRef ref, Exercise e, bool isFav) async {
    final docs = ref.read(docsProvider(Col.userExercises)).value ?? const [];
    final w = ref.read(dataWriterProvider);
    if (e.isCustom) {
      final id = e.id.substring(7);
      final doc = docs.where((d) => d['id'] == id).firstOrNull;
      if (doc == null) return;
      final next = {...doc, 'is_favorite': !isFav};
      await w.save(Col.userExercises, id, next, path: '/v1/user-exercises/$id');
      return;
    }
    final existing = docs.where((d) => d['library_exercise_id'] == e.id).firstOrNull;
    if (isFav && existing != null) {
      await w.remove(Col.userExercises, existing['id'] as String, path: '/v1/user-exercises/${existing['id']}');
    } else if (!isFav) {
      final id = newId();
      await w.save(Col.userExercises, id,
          {'id': id, 'library_exercise_id': e.id, 'is_favorite': true, 'tracking': trackingName(e.tracking)},
          path: '/v1/user-exercises/$id');
    }
  }
}

String _setLabel(WorkoutSet s, String units) {
  final side = s.side == null ? '' : '${s.side![0].toUpperCase()} ';
  if (s.durationS != null && s.reps == null) return '$side${s.durationS}s';
  if (s.distanceM != null && s.reps == null) return '$side${Units.trimNum(s.distanceM!)} m';
  if (s.weightKg == null || s.weightKg == 0) return '$side${s.reps ?? 0} reps';
  return '$side${Units.weight(s.weightKg, units, withUnit: false)}×${s.reps ?? 0}';
}

String setLabel(WorkoutSet s, String units) => _setLabel(s, units);
