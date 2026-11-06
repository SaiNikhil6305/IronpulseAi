import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../exercises/domain/exercise.dart';
import '../../gamification/data/gamification_provider.dart';
import '../../goals/data/goals_repository.dart';
import '../../nutrition/data/nutrition_repository.dart';
import '../../profile/domain/profile.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/domain/workout_models.dart';
import 'charts.dart';

enum RangeKind { d7, d30, m3, all, custom }

class ProgressRange {
  const ProgressRange(this.kind, {this.custom});
  final RangeKind kind;
  final DateTimeRange? custom;

  (DateTime?, DateTime) bounds(DateTime now) {
    final end = Dates.dayOnly(now).add(const Duration(days: 1));
    return switch (kind) {
      RangeKind.d7 => (end.subtract(const Duration(days: 7)), end),
      RangeKind.d30 => (end.subtract(const Duration(days: 30)), end),
      RangeKind.m3 => (DateTime(end.year, end.month - 3, end.day), end),
      RangeKind.all => (null, end),
      RangeKind.custom => (custom!.start, custom!.end.add(const Duration(days: 1))),
    };
  }

  bool contains(DateTime d, DateTime now) {
    final (s, e) = bounds(now);
    final local = d.toLocal();
    return (s == null || !local.isBefore(s)) && local.isBefore(e);
  }
}

/// Text insights generated only from recorded data, and only when there is enough of it.
List<String> buildInsights({
  required List<WorkoutSession> sessions,
  required List<DailyNutrition> nutritionWeek,
  required NutritionTargets targets,
  required DateTime now,
}) {
  final out = <String>[];
  final week = Dates.weekKey(now);
  final thisWeek = sessions.where((s) => s.isCompleted && Dates.weekKey(s.startedAt.toLocal()) == week).length;
  if (thisWeek > 0) out.add('You completed $thisWeek workout${thisWeek == 1 ? '' : 's'} this week.');

  // Exercise trend: most frequent exercise with at least 2 comparable sessions.
  final byEx = <String, List<(DateTime, double, String)>>{};
  for (final s in sessions.where((s) => s.isCompleted)) {
    for (final e in s.exercises) {
      double best = 0;
      for (final st in e.sets) {
        if (st.isValid && st.weightKg != null && st.weightKg! > 0 && st.reps != null && st.reps! <= 12) {
          final v = epley1rm(st.weightKg!, st.reps!);
          if (v > best) best = v;
        }
      }
      if (best > 0) byEx.putIfAbsent(e.exerciseRef, () => []).add((s.startedAt, best, e.exerciseName));
    }
  }
  final ranked = byEx.entries.where((e) => e.value.length >= 2).toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
  if (ranked.isNotEmpty) {
    final list = ranked.first.value..sort((a, b) => a.$1.compareTo(b.$1));
    final last = list.last, prev = list[list.length - 2];
    final diff = (last.$2 - prev.$2) / prev.$2 * 100;
    if (diff > 1) {
      out.add('Your recorded ${last.$3} performance improved compared with your previous comparable session '
          '(estimated 1RM +${diff.toStringAsFixed(1)}%).');
    } else if (diff < -5) {
      out.add('Your last ${last.$3} session was lighter than the one before. Normal variation — sleep, stress and '
          'recovery all play a part.');
    }
  }
  if (targets.enabled && targets.proteinG != null && nutritionWeek.length >= 3) {
    final below = nutritionWeek.where((d) => d.totals.protein < targets.proteinG!).length;
    if (below > 0) {
      out.add('Your recorded protein intake was below your selected target on $below of ${nutritionWeek.length} logged days in the last week.');
    } else {
      out.add('You met your protein target on every logged day in the last week.');
    }
  }
  return out;
}

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});
  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  ProgressRange _range = const ProgressRange(RangeKind.d30);
  String? _exercise;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final units = ref.watch(unitsProvider);
    final all = ref.watch(completedSessionsProvider);
    final sessions = all.where((s) => _range.contains(s.startedAt, now)).toList();
    final g = ref.watch(gamificationProvider);
    final weights = ref.watch(weightsProvider).where((w) => _range.contains(DateTime.parse(w.day), now)).toList();
    final meals = ref.watch(allMealsProvider);
    final targets = ref.watch(nutritionTargetsProvider);
    final goals = ref.watch(goalsProvider);
    final index = ref.watch(exerciseIndexProvider);
    final (start, _) = _range.bounds(now);
    final days = start == null
        ? (all.isEmpty ? 30 : Dates.dayOnly(now).difference(Dates.dayOnly(all.last.startedAt.toLocal())).inDays + 1)
        : Dates.dayOnly(now).difference(start).inDays + 1;
    final nutrition = nutritionHistory(meals, days, now);
    final insights = buildInsights(
        sessions: all, nutritionWeek: nutritionHistory(meals, 7, now), targets: targets, now: now);

    final sets = sessions.fold<int>(0, (a, s) => a + s.completedSets.length);
    final volume = sessions.fold<double>(0, (a, s) => a + s.volumeKg);
    final prs = g.records.where((p) => _range.contains(p.date, now)).toList().reversed.toList();

    // Exercise options = exercises with recorded weighted sets.
    final exerciseCounts = <String, int>{};
    for (final s in all) {
      for (final e in s.exercises) {
        if (e.completedSets.any((x) => (x.weightKg ?? 0) > 0)) exerciseCounts.update(e.exerciseRef, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final exOptions = exerciseCounts.keys.toList()..sort((a, b) => exerciseCounts[b]!.compareTo(exerciseCounts[a]!));
    final selected = _exercise ?? exOptions.firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress'), actions: [
        IconButton(tooltip: 'Goals', icon: const Icon(Icons.flag_outlined), onPressed: () => context.push('/goals')),
        IconButton(tooltip: 'Body weight', icon: const Icon(Icons.monitor_weight_outlined), onPressed: () => context.push('/weight')),
      ]),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final (k, label) in [
              (RangeKind.d7, '7 days'),
              (RangeKind.d30, '30 days'),
              (RangeKind.m3, '3 months'),
              (RangeKind.all, 'All time'),
            ]) ...[
              ChoiceChip(label: Text(label), selected: _range.kind == k, onSelected: (_) => setState(() => _range = ProgressRange(k))),
              const SizedBox(width: 6),
            ],
            ChoiceChip(
              label: Text(_range.kind == RangeKind.custom
                  ? '${DateFormat('d MMM').format(_range.custom!.start)}–${DateFormat('d MMM').format(_range.custom!.end)}'
                  : 'Custom'),
              selected: _range.kind == RangeKind.custom,
              onSelected: (_) async {
                final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (r != null) setState(() => _range = ProgressRange(RangeKind.custom, custom: r));
              },
            ),
          ]),
        ),
        if (insights.isNotEmpty) ...[
          const SectionHeader('Insights'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final i in insights)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i)),
                  ]),
                ),
            ]),
          ),
        ],
        const SectionHeader('Training'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: Gaps.sm,
          mainAxisSpacing: Gaps.sm,
          childAspectRatio: 0.95,
          children: [
            StatTile(label: 'Workouts', value: '${sessions.length}'),
            StatTile(label: 'Sets', value: '$sets'),
            StatTile(label: 'Volume', value: Units.volume(volume, units), caption: 'weight × reps'),
          ],
        ),
        const SizedBox(height: Gaps.md),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_range.kind == RangeKind.d7 ? 'Workouts per day' : 'Workouts per week',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: Gaps.md),
            LabeledBarChart(bars: _frequency(sessions, now, start), target: _range.kind == RangeKind.d7 ? null : g.streak.weeklyTarget.toDouble()),
          ]),
        ),
        const SizedBox(height: Gaps.md),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Training volume per workout', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: Gaps.md),
            DateLineChart(
              points: [for (final s in sessions) (s.startedAt.toLocal(), Units.fromKg(s.volumeKg, units))],
              unit: Units.weightLabel(units),
              decimals: 0,
            ),
          ]),
        ),
        const SectionHeader('Exercise performance'),
        AppCard(
          child: exOptions.isEmpty
              ? const Text('Log weighted sets to see exercise trends.', style: TextStyle(color: AppColors.textMuted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownButton<String>(
                    value: selected,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [for (final e in exOptions) DropdownMenuItem(value: e, child: Text(index[e]?.name ?? e))],
                    onChanged: (v) => setState(() => _exercise = v),
                  ),
                  DateLineChart(
                    points: _e1rmSeries(sessions, selected!, units),
                    unit: '${Units.weightLabel(units)} est. 1RM',
                  ),
                  const SizedBox(height: 4),
                  const Text('Estimated 1RM per session (Epley formula) — an estimate, not a tested max.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
        ),
        const SectionHeader('Personal records'),
        if (prs.isEmpty)
          const Text('No new records in this range.', style: TextStyle(color: AppColors.textMuted))
        else
          for (final p in prs.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.military_tech_rounded, color: AppColors.accent),
              title: Text('${p.exerciseName}: ${Units.weight(p.weightKg, units)} × ${p.reps}'),
              subtitle: Text('${Dates.friendly(p.date)} · est. 1RM ${Units.weight(p.e1rm, units)}'),
            ),
        SectionHeader('Body weight', action: 'Open', onAction: () => context.push('/weight')),
        AppCard(
          child: DateLineChart(
            points: [for (final w in weights) (DateTime.parse(w.day), Units.fromKg(w.weightKg, units))],
            unit: Units.weightLabel(units),
          ),
        ),
        SectionHeader('XP & streaks', action: 'Achievements', onAction: () => context.push('/achievements')),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Level ${g.level.level} · ${g.level.name} · ${g.level.totalXp} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: Gaps.sm),
            ProgressBar(value: g.level.progress),
            const SizedBox(height: Gaps.md),
            Text('Current streak ${g.streak.current} week(s) · longest ${g.streak.longest} · ${g.streak.total} workouts total'),
            const SizedBox(height: 4),
            Text(g.streak.explanation, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        const SectionHeader('Nutrition consistency'),
        AppCard(
          child: Builder(builder: (_) {
            final logged = nutrition.length;
            final hit = targets.enabled && targets.proteinG != null
                ? nutrition.where((d) => d.totals.protein >= targets.proteinG!).length
                : null;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Meals logged on $logged of $days day${days == 1 ? '' : 's'}'),
              if (hit != null) Text('Protein target met on $hit of $logged logged day${logged == 1 ? '' : 's'}'),
              const SizedBox(height: Gaps.md),
              DateLineChart(points: [for (final d in nutrition) (DateTime.parse(d.day), d.totals.protein)], unit: 'g protein', decimals: 0),
              const Text('Based on what you logged; entries without values aren\'t counted.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]);
          }),
        ),
        SectionHeader('Goals', action: 'Manage', onAction: () => context.push('/goals')),
        AppCard(
          onTap: () => context.push('/goals'),
          child: Text(goals.isEmpty
              ? 'No goals yet — set one to track progress.'
              : '${goals.where((x) => x.goal.status == 'active').length} active · '
                  '${goals.where((x) => x.goal.status == 'completed').length} completed'),
        ),
      ]),
    );
  }

  List<(String, double)> _frequency(List<WorkoutSession> sessions, DateTime now, DateTime? start) {
    if (_range.kind == RangeKind.d7) {
      return [
        for (var i = 6; i >= 0; i--)
          () {
            final d = Dates.dayOnly(now).subtract(Duration(days: i));
            return (DateFormat('E').format(d), sessions.where((s) => Dates.dayOnly(s.startedAt.toLocal()) == d).length.toDouble());
          }()
      ];
    }
    final first = start ?? (sessions.isEmpty ? now : sessions.last.startedAt.toLocal());
    var monday = Dates.dayOnly(first).subtract(Duration(days: first.weekday - 1));
    final out = <(String, double)>[];
    while (!monday.isAfter(now)) {
      final key = Dates.weekKey(monday);
      out.add((DateFormat('d/M').format(monday), sessions.where((s) => Dates.weekKey(s.startedAt.toLocal()) == key).length.toDouble()));
      monday = DateTime(monday.year, monday.month, monday.day + 7);
    }
    return out;
  }

  List<(DateTime, double)> _e1rmSeries(List<WorkoutSession> sessions, String ref, String units) {
    final out = <(DateTime, double)>[];
    for (final s in sessions) {
      double best = 0;
      for (final e in s.exercises.where((e) => e.exerciseRef == ref)) {
        for (final st in e.sets) {
          if (st.isValid && (st.weightKg ?? 0) > 0 && st.reps != null && st.reps! <= 12) {
            final v = epley1rm(st.weightKg!, st.reps!);
            if (v > best) best = v;
          }
        }
      }
      if (best > 0) out.add((s.startedAt.toLocal(), Units.fromKg(best, units)));
    }
    return out;
  }
}

