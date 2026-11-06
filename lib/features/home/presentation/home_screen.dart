import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_controller.dart';
import '../../checklist/presentation/checklist_screens.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_screens.dart';
import '../../gamification/data/gamification_provider.dart';
import '../../goals/presentation/goals_screens.dart';
import '../../nutrition/data/nutrition_repository.dart';
import '../../profile/domain/profile.dart';
import '../../workouts/data/active_workout_controller.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/domain/split.dart';
import '../../workouts/domain/workout_models.dart';
import '../../workouts/presentation/workout_tab.dart';

/// Shown once per app launch.
bool _popupShownThisLaunch = false;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePopup());
  }

  Future<void> _maybePopup() async {
    if (_popupShownThisLaunch || !mounted) return;
    // Wait for local data so the popup reflects real history.
    await ref.read(docsProvider(Col.sessions).future);
    if (!mounted || ref.read(activeWorkoutProvider).value != null) return;
    _popupShownThisLaunch = true;
    final last = ref.read(lastCompletedSessionProvider);
    final prefs = ref.read(prefsProvider);
    if (last == null) {
      if (prefs.getBool('intro.first_workout_shown') == true) return;
      await prefs.setBool('intro.first_workout_shown', true);
      if (mounted) await showModalBottomSheet<void>(context: context, builder: (_) => const _FirstWorkoutIntro());
      return;
    }
    if (mounted) {
      await showModalBottomSheet<void>(
          context: context, isScrollControlled: true, builder: (_) => _PreviousWorkoutSheet(previous: last));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(todayPlanProvider);
    final last = ref.watch(lastCompletedSessionProvider);
    final active = ref.watch(activeWorkoutProvider).value;
    final units = ref.watch(unitsProvider);
    final auth = ref.watch(authControllerProvider);
    final sync = ref.watch(syncServiceProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (auth.canSync) await ref.read(syncServiceProvider.notifier).syncNow();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.lg, Gaps.xl), children: [
            Row(children: [
              const Brand(),
              const Spacer(),
              IconButton(tooltip: 'Reminders', icon: const Icon(Icons.notifications_none_rounded), onPressed: () => context.push('/schedule')),
              IconButton(tooltip: 'Profile & settings', icon: const Icon(Icons.account_circle_outlined), onPressed: () => context.push('/settings')),
            ]),
            const SizedBox(height: Gaps.md),
            Text('$greeting, ${profile?.displayName.isNotEmpty == true ? profile!.displayName : 'athlete'}',
                style: Theme.of(context).textTheme.headlineSmall),
            if (auth.isLocal)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Pill('Device-only mode · not backed up', color: AppColors.warning, icon: Icons.phone_android),
              )
            else if (sync.failed > 0)
              Padding(
                padding: const EdgeInsets.only(top: Gaps.sm),
                child: AppCard(
                  borderColor: AppColors.error,
                  padding: const EdgeInsets.all(Gaps.md),
                  onTap: () => context.push('/sync'),
                  child: Text('${sync.failed} change(s) could not be synced. Tap to review.',
                      style: const TextStyle(color: AppColors.error)),
                ),
              ),
            const SectionHeader('Today\'s workout'),
            _TodayCard(plan: plan, active: active),
            if (last != null) ...[
              const SectionHeader('Previous workout'),
              _PreviousCard(session: last, units: units, canRepeat: active == null),
            ],
            const SectionHeader('Progress'),
            const _ProgressRow(),
            SectionHeader('Daily checklist', action: 'Manage', onAction: () => context.push('/checklist')),
            const ChecklistCard(),
            SectionHeader('Nutrition today', action: 'Open', onAction: () => context.go('/nutrition')),
            const _NutritionCard(),
            const SectionHeader('Quick actions'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  avatar: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start workout'),
                  onPressed: () => plan.day != null ? startPlannedWorkout(context, ref, plan.day!) : startEmptyWorkout(context, ref)),
              ActionChip(avatar: const Icon(Icons.restaurant, size: 18), label: const Text('Log meal'), onPressed: () => context.go('/nutrition')),
              ActionChip(avatar: const Icon(Icons.checklist, size: 18), label: const Text('Checklist'), onPressed: () => context.push('/checklist')),
              ActionChip(avatar: const Icon(Icons.monitor_weight_outlined, size: 18), label: const Text('Record weight'), onPressed: () => showWeightSheet(context, ref)),
              ActionChip(avatar: const Icon(Icons.auto_awesome, size: 18), label: const Text('Ask IronPulse AI'), onPressed: () => context.go('/ai')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _TodayCard extends ConsumerStatefulWidget {
  const _TodayCard({required this.plan, required this.active});
  final TodayPlan plan;
  final WorkoutSession? active;
  @override
  ConsumerState<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends ConsumerState<_TodayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final index = ref.watch(exerciseIndexProvider);
    if (widget.active != null) {
      return AppCard(
        borderColor: AppColors.accent,
        onTap: () => context.push('/workout/active'),
        child: Row(children: [
          const Icon(Icons.play_circle_fill, color: AppColors.accent, size: 40),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Continue ${widget.active!.name}', style: Theme.of(context).textTheme.titleMedium),
              Text('${widget.active!.completedSets.length} sets logged so far', style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
        ]),
      );
    }
    if (plan.day == null) {
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(plan.isRestDay ? 'Rest day' : 'No workout planned', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(plan.isRestDay ? 'Recovery builds strength too.' : 'Choose a split to plan your week.',
              style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: Gaps.md),
          OutlinedButton(
            onPressed: () => plan.isRestDay ? context.go('/workout') : context.push('/split'),
            child: Text(plan.isRestDay ? 'Train anyway' : 'Choose split'),
          ),
        ]),
      );
    }
    final d = plan.day!;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(d.name.toUpperCase(),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.accent, letterSpacing: 0.5)),
          ),
          if (plan.time != null) Pill(Dates.timeLabel(plan.time), icon: Icons.schedule, color: AppColors.text),
        ]),
        const SizedBox(height: 4),
        Text(d.muscleGroups.map(muscleLabel).join(' · '), style: const TextStyle(color: AppColors.textMuted)),
        if (_expanded) ...[
          const SizedBox(height: Gaps.md),
          for (final t in d.exercises)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(index[t.exerciseRef]?.name ?? t.exerciseRef)),
                Text('${t.targetSets} × ${t.targetReps ?? '—'}', style: const TextStyle(color: AppColors.textMuted)),
              ]),
            ),
        ],
        const SizedBox(height: Gaps.lg),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Hide exercises' : 'View exercises'),
            ),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: FilledButton(onPressed: () => startPlannedWorkout(context, ref, d), child: const Text('Start workout')),
          ),
        ]),
      ]),
    );
  }
}

class _PreviousCard extends ConsumerWidget {
  const _PreviousCard({required this.session, required this.units, required this.canRepeat});
  final WorkoutSession session;
  final String units;
  final bool canRepeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = session.exercises.where((e) => e.completedSets.isNotEmpty).toList();
    return AppCard(
      onTap: () => context.push('/workout/session/${session.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(session.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          Text(Dates.friendly(session.startedAt), style: const TextStyle(color: AppColors.textMuted)),
        ]),
        const SizedBox(height: Gaps.sm),
        for (final e in ex.take(4))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(e.exerciseName)),
              Text(_top(e.completedSets, units), style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
        if (ex.length > 4) Text('+${ex.length - 4} more', style: const TextStyle(color: AppColors.textMuted)),
        if (canRepeat) ...[
          const SizedBox(height: Gaps.md),
          OutlinedButton.icon(
            onPressed: () => repeatWorkout(context, ref, session),
            icon: const Icon(Icons.replay),
            label: const Text('Repeat this workout'),
          ),
        ],
      ]),
    );
  }

  static String _top(List<WorkoutSet> sets, String units) {
    final best = sets.reduce((a, b) => ((a.weightKg ?? 0) >= (b.weightKg ?? 0)) ? a : b);
    return setLabel(best, units);
  }
}

class _ProgressRow extends ConsumerWidget {
  const _ProgressRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final lvl = g.level;
    return Column(children: [
      AppCard(
        onTap: () => context.push('/achievements'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bolt, color: AppColors.accent),
            const SizedBox(width: 6),
            Text('Level ${lvl.level} · ${lvl.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${lvl.totalXp} XP', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
          ]),
          const SizedBox(height: Gaps.sm),
          ProgressBar(value: lvl.progress),
          const SizedBox(height: 6),
          Text(
            lvl.nextXp == null ? 'Top level reached.' : '${lvl.xpToNext} XP to ${lvl.nextName}'
                '${g.serverConfirmed ? '' : ' · pending sync'}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ]),
      ),
      const SizedBox(height: Gaps.md),
      Row(children: [
        Expanded(
          child: StatTile(
            label: 'Streak',
            value: '${g.streak.current} wk',
            icon: Icons.local_fire_department_rounded,
            accent: g.streak.current > 0,
            caption: 'Best ${g.streak.longest} wk',
          ),
        ),
        const SizedBox(width: Gaps.md),
        Expanded(
          child: StatTile(
            label: 'This week',
            value: '${g.streak.thisWeek}/${g.streak.weeklyTarget}',
            icon: Icons.calendar_today_rounded,
            caption: g.streak.thisWeek >= g.streak.weeklyTarget ? 'Target hit 🎯' : 'workouts',
          ),
        ),
      ]),
    ]);
  }
}

class _NutritionCard extends ConsumerWidget {
  const _NutritionCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = Dates.iso(DateTime.now());
    final t = NutritionTotals.of(ref.watch(mealsForDayProvider(day)));
    final targets = ref.watch(nutritionTargetsProvider);
    Widget row(String label, double value, double? target, String unit) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(target != null && targets.enabled
                  ? '${value.round()} / ${target.round()} $unit'
                  : '${value.round()} $unit'),
            ]),
            if (target != null && targets.enabled && target > 0) ...[
              const SizedBox(height: 4),
              ProgressBar(value: value / target, height: 6),
            ],
          ]),
        );
    return AppCard(
      onTap: () => context.go('/nutrition'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('Protein', t.protein, targets.proteinG, 'g'),
        row('Calories', t.calories, targets.calories, 'kcal'),
        const SizedBox(height: 4),
        Text(
          '${t.mealsLogged} meal${t.mealsLogged == 1 ? '' : 's'} logged'
          '${t.estimates ? ' · includes estimates' : ''}${t.missing > 0 ? ' · ${t.missing} item(s) without values' : ''}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ]),
    );
  }
}

class _PreviousWorkoutSheet extends ConsumerStatefulWidget {
  const _PreviousWorkoutSheet({required this.previous});
  final WorkoutSession previous;
  @override
  ConsumerState<_PreviousWorkoutSheet> createState() => _PreviousWorkoutSheetState();
}

class _PreviousWorkoutSheetState extends ConsumerState<_PreviousWorkoutSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.previous;
    final units = ref.watch(unitsProvider);
    final plan = ref.watch(todayPlanProvider);
    final index = ref.watch(exerciseIndexProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Previous workout'), icon: Icon(Icons.history)),
              ButtonSegment(value: 1, label: Text('Today\'s split'), icon: Icon(Icons.today)),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: Gaps.lg),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            child: SingleChildScrollView(
              child: _tab == 0 ? _previous(s, units) : _today(plan, index),
            ),
          ),
          const SizedBox(height: Gaps.lg),
          FilledButton(
            onPressed: plan.day == null
                ? null
                : () {
                    Navigator.pop(context);
                    startPlannedWorkout(context, ref, plan.day!);
                  },
            child: Text(plan.day == null ? 'No workout planned today' : 'Start today\'s planned workout'),
          ),
          const SizedBox(height: Gaps.sm),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              repeatWorkout(context, ref, s);
            },
            child: const Text('Repeat previous workout'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Dismiss')),
        ]),
      ),
    );
  }

  Widget _previous(WorkoutSession s, String units) {
    final synced = ref.watch(sessionSyncProvider(s.id));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YOUR LAST GYM SESSION · HISTORY',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
      const SizedBox(height: 4),
      Text(s.name.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      Text(
        '${Dates.friendly(s.startedAt)} · ${Units.durationWords(s.elapsed())} · ${s.completedSets.length} sets'
        '${synced?['xp_from_session'] != null ? ' · +${synced!['xp_from_session']} XP' : ''}',
        style: const TextStyle(color: AppColors.textMuted),
      ),
      const SizedBox(height: Gaps.md),
      for (final e in s.exercises.where((e) => e.completedSets.isNotEmpty))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(e.exerciseName, style: const TextStyle(fontWeight: FontWeight.w700))),
            Flexible(
              child: Text(e.completedSets.map((x) => setLabel(x, units)).join(', '),
                  textAlign: TextAlign.right, style: const TextStyle(color: AppColors.textMuted)),
            ),
          ]),
        ),
      if (s.notes?.isNotEmpty == true) ...[const SizedBox(height: Gaps.sm), Text('Notes: ${s.notes}')],
    ]);
  }

  Widget _today(TodayPlan plan, Map<String, Exercise> index) {
    if (plan.day == null) {
      return Text(plan.isRestDay ? 'Today is a scheduled rest day.' : 'No split selected yet.',
          style: const TextStyle(color: AppColors.textMuted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TODAY · PLANNED',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accent, letterSpacing: 1)),
      const SizedBox(height: 4),
      Text(plan.day!.name.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      Text(plan.day!.muscleGroups.map(muscleLabel).join(' · '), style: const TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: Gaps.md),
      for (final t in plan.day!.exercises)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(index[t.exerciseRef]?.name ?? t.exerciseRef)),
            Text('${t.targetSets} × ${t.targetReps ?? '—'}', style: const TextStyle(color: AppColors.textMuted)),
          ]),
        ),
    ]);
  }
}

class _FirstWorkoutIntro extends ConsumerWidget {
  const _FirstWorkoutIntro();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(todayPlanProvider);
    Widget tip(IconData i, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Icon(i, color: AppColors.accent), const SizedBox(width: 12), Expanded(child: Text(t))]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Your first workout', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: Gaps.md),
          tip(Icons.edit_note, 'Type the weight and reps for each set.'),
          tip(Icons.check_circle_outline, 'Tap ✓ when a set is done — the rest timer starts automatically.'),
          tip(Icons.save_outlined, 'Everything saves instantly. Leave the app and come back any time.'),
          tip(Icons.health_and_safety_outlined, 'Start light and focus on technique. There\'s no rush.'),
          const SizedBox(height: Gaps.lg),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              plan.day != null ? startPlannedWorkout(context, ref, plan.day!) : context.go('/workout');
            },
            child: Text(plan.day != null ? 'Start ${plan.day!.name}' : 'Go to Workout'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
        ]),
      ),
    );
  }
}
