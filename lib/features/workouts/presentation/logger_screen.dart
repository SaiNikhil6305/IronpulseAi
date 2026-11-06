import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_controller.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_screens.dart';
import '../../exercises/presentation/exercise_video.dart';
import '../../profile/domain/profile.dart';
import '../data/active_workout_controller.dart';
import '../data/rest_timer.dart';
import '../data/workout_repository.dart';
import '../domain/workout_models.dart';

class LoggerScreen extends ConsumerWidget {
  const LoggerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeWorkoutProvider);
    final session = async.value;
    if (async.isLoading && session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.fitness_center,
          title: 'No workout in progress',
          message: 'Start one from the Workout tab.',
          action: 'Go to Workout',
          onAction: () => context.go('/workout'),
        ),
      );
    }
    final ctrl = ref.read(activeWorkoutProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.name, overflow: TextOverflow.ellipsis),
          const _ElapsedLabel(),
        ]),
        actions: [
          IconButton(
            tooltip: session.isPaused ? 'Resume workout timer' : 'Pause workout timer',
            icon: Icon(session.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            onPressed: ctrl.togglePause,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'notes') await _editNotes(context, ref, session.notes);
              if (v == 'discard' && context.mounted) {
                final ok = await confirmDialog(context,
                    title: 'Discard workout?',
                    message: 'This permanently deletes this in-progress workout and its sets.',
                    confirm: 'Discard',
                    destructive: true);
                if (ok) {
                  await ref.read(restTimerProvider.notifier).skip();
                  await ctrl.discard();
                  if (context.mounted) context.go('/workout');
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'notes', child: Text('Workout notes')),
              PopupMenuItem(value: 'discard', child: Text('Discard workout', style: TextStyle(color: AppColors.error))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          const _SaveStatus(),
          const _RestTimerBanner(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, Gaps.lg),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: session.exercises.length + 1,
              itemBuilder: (context, i) {
                if (i == session.exercises.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: Gaps.md),
                    child: Column(children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ex = await showExercisePicker(context);
                          if (ex != null) await ctrl.addExercise(ex);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add exercise'),
                      ),
                      const SizedBox(height: Gaps.md),
                      if (session.notes?.isNotEmpty == true)
                        AppCard(child: Text('Notes: ${session.notes}', style: const TextStyle(color: AppColors.textMuted))),
                    ]),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: Gaps.md),
                  child: _ExerciseCard(
                    key: ValueKey(session.exercises[i].id),
                    index: i,
                    exercise: session.exercises[i],
                    sessionId: session.id,
                    total: session.exercises.length,
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, Gaps.md),
            decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(
                child: Text('${session.completedSets.length} sets done',
                    style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              ),
              FilledButton.icon(
                onPressed: () => _finish(context, ref, session),
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Finish'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref, String? current) async {
    final c = TextEditingController(text: current);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workout notes'),
        content: TextField(controller: c, maxLines: 4, maxLength: 2000, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (res != null) await ref.read(activeWorkoutProvider.notifier).setNotes(res.trim().isEmpty ? null : res.trim());
  }

  Future<void> _finish(BuildContext context, WidgetRef ref, WorkoutSession s) async {
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let pending field edits commit
    final current = ref.read(activeWorkoutProvider).value ?? s;
    final open = current.allSets.where((x) => !x.completed && (x.reps != null || x.weightKg != null)).length;
    if (current.completedSets.isEmpty) {
      if (!context.mounted) return;
      final ok = await confirmDialog(context,
          title: 'No completed sets',
          message: 'Mark sets complete with the ✓ button. Finish anyway? An empty workout earns no XP.',
          confirm: 'Finish anyway');
      if (!ok) return;
    } else if (open > 0) {
      if (!context.mounted) return;
      final ok = await confirmDialog(context,
          title: 'Finish workout?',
          message: '$open set${open == 1 ? '' : 's'} with values ${open == 1 ? 'is' : 'are'} not marked complete and won\'t count.',
          confirm: 'Finish');
      if (!ok) return;
    }
    await ref.read(restTimerProvider.notifier).skip();
    final done = await ref.read(activeWorkoutProvider.notifier).finish();
    if (done != null && context.mounted) context.pushReplacement('/workout/summary/${done.id}');
  }
}

class _ElapsedLabel extends ConsumerWidget {
  const _ElapsedLabel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(secondTickerProvider);
    final s = ref.watch(activeWorkoutProvider).value;
    if (s == null) return const SizedBox.shrink();
    return Text(
      '${Units.duration(s.elapsed())}${s.isPaused ? ' · paused' : ''}',
      style: TextStyle(fontSize: 13, color: s.isPaused ? AppColors.warning : AppColors.accent, fontWeight: FontWeight.w700),
    );
  }
}

class _SaveStatus extends ConsumerWidget {
  const _SaveStatus();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final sync = ref.watch(syncServiceProvider);
    final (text, color, icon) = !auth.canSync
        ? ('Saved on this device', AppColors.textMuted, Icons.phone_android)
        : sync.pending > 0 || sync.syncing
            ? ('Saved on device · will sync when online', AppColors.warning, Icons.cloud_upload_outlined)
            : sync.failed > 0
                ? ('Some changes need attention — see Settings › Sync', AppColors.error, Icons.error_outline)
                : ('Saved and synced', AppColors.success, Icons.cloud_done_outlined);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }
}

class _RestTimerBanner extends ConsumerStatefulWidget {
  const _RestTimerBanner();
  @override
  ConsumerState<_RestTimerBanner> createState() => _RestTimerBannerState();
}

class _RestTimerBannerState extends ConsumerState<_RestTimerBanner> {
  DateTime? _alerted;

  @override
  Widget build(BuildContext context) {
    ref.watch(secondTickerProvider);
    final t = ref.watch(restTimerProvider);
    final ctrl = ref.read(restTimerProvider.notifier);
    if (!t.active) return const SizedBox.shrink();
    final remaining = t.remainingS();
    if (remaining == 0 && !t.paused && _alerted != t.endsAt) {
      _alerted = t.endsAt;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (ctrl.settings.vibrate) await HapticFeedback.heavyImpact();
        if (ctrl.settings.sound) await SystemSound.play(SystemSoundType.alert);
        await ctrl.skip();
      });
    }
    final progress = t.totalS == 0 ? 0.0 : 1 - remaining / t.totalS;
    return Container(
      margin: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, 0),
      padding: const EdgeInsets.all(Gaps.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Gaps.radius),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.timer_outlined, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(t.paused ? 'Rest paused' : 'Rest', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(Units.duration(Duration(seconds: remaining)),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: Gaps.sm),
        ProgressBar(value: progress, height: 6),
        const SizedBox(height: Gaps.sm),
        Row(children: [
          TextButton(onPressed: () => ctrl.addSeconds(-15), child: const Text('−15s')),
          TextButton(onPressed: () => ctrl.addSeconds(15), child: const Text('+15s')),
          const Spacer(),
          IconButton(
              tooltip: t.paused ? 'Resume' : 'Pause',
              onPressed: ctrl.togglePause,
              icon: Icon(t.paused ? Icons.play_arrow_rounded : Icons.pause_rounded)),
          TextButton(onPressed: ctrl.skip, child: const Text('SKIP')),
        ]),
      ]),
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({super.key, required this.index, required this.exercise, required this.sessionId, required this.total});
  final int index;
  final SessionExercise exercise;
  final String sessionId;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider);
    final ctrl = ref.read(activeWorkoutProvider.notifier);
    final info = ref.watch(exerciseIndexProvider)[exercise.exerciseRef];
    final tracking = info?.tracking ?? Tracking.weightReps;
    final prev = ref.watch(previousPerformanceProvider((exercise.exerciseRef, sessionId)));
    final paired = exercise.sets.any((s) => s.side != null);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.sm, Gaps.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => context.push('/exercises/${Uri.encodeComponent(exercise.exerciseRef)}'),
              child: Text(exercise.exerciseName,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.accent)),
            ),
          ),
          if (info != null && demoAssetPath(info) != null)
            IconButton(
              tooltip: 'Watch demo',
              icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.accent),
              onPressed: () => showExerciseDemo(context, info),
            ),
          PopupMenuButton<String>(
            tooltip: 'Exercise options',
            onSelected: (v) async {
              switch (v) {
                case 'up':
                  await ctrl.reorderExercise(index, index - 1);
                case 'down':
                  await ctrl.reorderExercise(index, index + 2);
                case 'replace':
                  final ex = await showExercisePicker(context, muscleHint: info?.primaryMuscle, title: 'Replace with');
                  if (ex != null) await ctrl.replaceExercise(index, ex);
                case 'lr':
                  await ctrl.toggleUnilateral(index);
                case 'notes':
                  final c = TextEditingController(text: exercise.notes);
                  if (!context.mounted) return;
                  final res = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Exercise notes'),
                      content: TextField(controller: c, maxLines: 3, maxLength: 1000, autofocus: true),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save'))],
                    ),
                  );
                  if (res != null) await ctrl.setExerciseNotes(index, res.trim());
                case 'remove':
                  if (!context.mounted) return;
                  final ok = await confirmDialog(context,
                      title: 'Remove ${exercise.exerciseName}?',
                      message: 'Its sets in this workout will be deleted.',
                      confirm: 'Remove',
                      destructive: true);
                  if (ok) await ctrl.removeExercise(index);
              }
            },
            itemBuilder: (_) => [
              if (index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
              if (index < total - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
              const PopupMenuItem(value: 'replace', child: Text('Replace exercise')),
              PopupMenuItem(value: 'lr', child: Text(paired ? 'Combine left/right' : 'Track left/right separately')),
              const PopupMenuItem(value: 'notes', child: Text('Notes')),
              const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: AppColors.error))),
            ],
          ),
        ]),
        if (prev != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  'Last session (${Dates.friendly(prev.session.startedAt)}): '
                  '${prev.sets.take(4).map((s) => setLabel(s, units)).join(', ')}${prev.sets.length > 4 ? '…' : ''}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  await ctrl.copyPrevious(index, prev.sets);
                  if (context.mounted) showSnack(context, 'Copied last session\'s values — adjust as needed.');
                },
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Copy'),
              ),
            ]),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('First time logging this exercise.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
        if (exercise.notes?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('📝 ${exercise.notes}', style: const TextStyle(fontSize: 13)),
          ),
        _HeaderRow(tracking: tracking, units: units),
        for (var j = 0; j < exercise.sets.length; j++)
          _SetRow(
            key: ValueKey(exercise.sets[j].id),
            exIndex: index,
            setIndex: j,
            set: exercise.sets[j],
            label: _label(exercise.sets, j),
            previous: prev != null && j < prev.sets.length ? prev.sets[j] : null,
            tracking: tracking,
            units: units,
          ),
        TextButton.icon(onPressed: () => ctrl.addSet(index), icon: const Icon(Icons.add), label: Text(paired ? 'Add L/R sets' : 'Add set')),
      ]),
    );
  }

  static String _label(List<WorkoutSet> sets, int j) {
    final s = sets[j];
    if (s.side == null) return '${sets.take(j + 1).where((x) => x.side == null).length}';
    final n = sets.take(j + 1).where((x) => x.side == s.side).length;
    return '$n${s.side == 'left' ? 'L' : 'R'}';
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.tracking, required this.units});
  final Tracking tracking;
  final String units;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.6);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(children: [
        const SizedBox(width: 36, child: Text('SET', style: style)),
        const Expanded(flex: 3, child: Text('PREVIOUS', style: style)),
        if (tracking == Tracking.weightReps || tracking == Tracking.distance)
          Expanded(flex: 3, child: Text(Units.weightLabel(units).toUpperCase(), style: style, textAlign: TextAlign.center)),
        Expanded(
          flex: 3,
          child: Text(
              switch (tracking) {
                Tracking.duration => 'SECONDS',
                Tracking.distance => 'METRES',
                _ => 'REPS',
              },
              style: style,
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 52),
      ]),
    );
  }
}

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({super.key, required this.exIndex, required this.setIndex, required this.set, required this.label,
      required this.previous, required this.tracking, required this.units});
  final int exIndex;
  final int setIndex;
  final WorkoutSet set;
  final String label;
  final WorkoutSet? previous;
  final Tracking tracking;
  final String units;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final TextEditingController _w;
  late final TextEditingController _r;
  Timer? _debounce;

  String _wText(WorkoutSet s) => s.weightKg == null ? '' : Units.weight(s.weightKg, widget.units, withUnit: false);
  String _rText(WorkoutSet s) => switch (widget.tracking) {
        Tracking.duration => s.durationS?.toString() ?? '',
        Tracking.distance => s.distanceM == null ? '' : Units.trimNum(s.distanceM!),
        _ => s.reps?.toString() ?? '',
      };

  @override
  void initState() {
    super.initState();
    _w = TextEditingController(text: _wText(widget.set));
    _r = TextEditingController(text: _rText(widget.set));
  }

  @override
  void didUpdateWidget(covariant _SetRow old) {
    super.didUpdateWidget(old);
    // External changes (copy previous, unit switch) update fields unless the user is mid-edit.
    if (_debounce?.isActive != true) {
      final w = _wText(widget.set), r = _rText(widget.set);
      if (_w.text != w && Validators.parseNum(_w.text) != Validators.parseNum(w)) _w.text = w;
      if (_r.text != r && Validators.parseNum(_r.text) != Validators.parseNum(r)) _r.text = r;
    }
  }

  @override
  void dispose() {
    if (_debounce?.isActive == true) {
      _debounce!.cancel();
      _commit();
    }
    _w.dispose();
    _r.dispose();
    super.dispose();
  }

  WorkoutSet _fromFields() {
    final w = Validators.parseNum(_w.text);
    final r = Validators.parseNum(_r.text);
    final kg = w == null ? null : Units.toKg(w, widget.units).clamp(0, 1000).toDouble();
    return switch (widget.tracking) {
      Tracking.duration => widget.set.copyWith(durationS: r?.round().clamp(0, 86400)),
      Tracking.distance => widget.set.copyWith(weightKg: kg, distanceM: r?.clamp(0, 100000).toDouble()),
      Tracking.reps => widget.set.copyWith(reps: r?.round().clamp(0, 1000)),
      Tracking.weightReps => widget.set.copyWith(weightKg: kg, reps: r?.round().clamp(0, 1000)),
    };
  }

  void _commit() {
    final next = _fromFields();
    final s = widget.set;
    if (next.weightKg != s.weightKg || next.reps != s.reps || next.durationS != s.durationS || next.distanceM != s.distanceM) {
      ref.read(activeWorkoutProvider.notifier).updateSet(widget.exIndex, widget.setIndex, next);
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _commit);
  }

  Future<void> _toggle() async {
    _debounce?.cancel();
    final next = _fromFields();
    final needs = switch (widget.tracking) {
      Tracking.duration => next.durationS == null || next.durationS == 0,
      Tracking.distance => next.distanceM == null || next.distanceM == 0,
      _ => next.reps == null || next.reps == 0,
    };
    if (!widget.set.completed && needs) {
      showSnack(context, widget.tracking == Tracking.duration ? 'Enter the time first.' : 'Enter your reps first.');
      return;
    }
    final ctrl = ref.read(activeWorkoutProvider.notifier);
    if (next.weightKg != widget.set.weightKg || next.reps != widget.set.reps || next.durationS != widget.set.durationS ||
        next.distanceM != widget.set.distanceM) {
      await ctrl.updateSet(widget.exIndex, widget.setIndex, next);
    }
    final done = await ctrl.toggleSetComplete(widget.exIndex, widget.setIndex);
    final timer = ref.read(restTimerProvider.notifier);
    if (done) {
      unawaited(HapticFeedback.mediumImpact());
      if (timer.settings.autoStart) await timer.start();
    }
  }

  Future<void> _menu() async {
    final ctrl = ref.read(activeWorkoutProvider.notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.speed), title: const Text('Set RPE (effort)'), onTap: () => Navigator.pop(ctx, 'rpe')),
          if (widget.tracking == Tracking.weightReps)
            ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Add duration'), onTap: () => Navigator.pop(ctx, 'dur')),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete set', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') await ctrl.removeSet(widget.exIndex, widget.setIndex);
    if (action == 'rpe' && mounted) {
      final rpe = await showModalBottomSheet<double>(
        context: context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(Gaps.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RPE — rate of perceived exertion', style: TextStyle(fontWeight: FontWeight.w800)),
            const Text('10 = no reps left · 8 = about 2 reps left', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: Gaps.md),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0])
                ChoiceChip(
                    label: Text(Units.trimNum(v)), selected: widget.set.rpe == v, onSelected: (_) => Navigator.pop(ctx, v)),
              ActionChip(label: const Text('Clear'), onPressed: () => Navigator.pop(ctx, -1)),
            ]),
          ]),
        ),
      );
      if (rpe != null) await ctrl.updateSet(widget.exIndex, widget.setIndex, widget.set.copyWith(rpe: rpe < 0 ? null : rpe));
    }
    if (action == 'dur' && mounted) {
      final c = TextEditingController(text: widget.set.durationS?.toString());
      final res = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Set duration (seconds)'),
          content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save'))],
        ),
      );
      if (res != null) {
        await ctrl.updateSet(widget.exIndex, widget.setIndex, widget.set.copyWith(durationS: int.tryParse(res.trim())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.set;
    final done = s.completed;
    final showWeight = widget.tracking == Tracking.weightReps || widget.tracking == Tracking.distance;
    final prev = widget.previous;
    InputDecoration deco(String hint) => InputDecoration(
          isDense: true,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          fillColor: done ? AppColors.success.withValues(alpha: 0.12) : AppColors.surfaceHigh,
        );
    return Dismissible(
      key: ValueKey('dismiss-${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error.withValues(alpha: 0.3),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => ref.read(activeWorkoutProvider.notifier).removeSet(widget.exIndex, widget.setIndex),
      child: GestureDetector(
        onLongPress: _menu,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.label,
                    style: TextStyle(fontWeight: FontWeight.w900, color: done ? AppColors.success : AppColors.text)),
                if (s.rpe != null)
                  Text('@${Units.trimNum(s.rpe!)}', style: const TextStyle(fontSize: 10, color: AppColors.accent)),
              ]),
            ),
            Expanded(
              flex: 3,
              child: Text(
                prev == null ? '—' : setLabel(prev, widget.units),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showWeight)
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: TextField(
                    controller: _w,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: deco(prev?.weightKg == null ? '0' : Units.weight(prev!.weightKg, widget.units, withUnit: false)),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    onChanged: _onChanged,
                    onSubmitted: (_) => _commit(),
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: TextField(
                  controller: _r,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.numberWithOptions(decimal: widget.tracking == Tracking.distance),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: deco(switch (widget.tracking) {
                    Tracking.duration => prev?.durationS?.toString() ?? '0',
                    Tracking.distance => prev?.distanceM == null ? '0' : Units.trimNum(prev!.distanceM!),
                    _ => prev?.reps?.toString() ?? '0',
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  onChanged: _onChanged,
                  onSubmitted: (_) => _commit(),
                  textInputAction: TextInputAction.done,
                ),
              ),
            ),
            SizedBox(
              width: 52,
              height: 48,
              child: IconButton(
                tooltip: done ? 'Mark not done' : 'Mark set complete',
                onPressed: _toggle,
                style: IconButton.styleFrom(
                  backgroundColor: done ? AppColors.success : AppColors.surfaceHigh,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(Icons.check_rounded, color: done ? Colors.black : AppColors.textMuted),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
