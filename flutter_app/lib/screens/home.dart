import 'package:flutter/material.dart';

import '../data/nutrition_repo.dart';
import '../data/repo.dart';
import '../data/seed.dart';
import '../data/splits.dart';
import '../logic/progress.dart';
import '../logic/schedule.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'body.dart';
import 'schedule.dart';
import 'settings.dart';
import 'wearables.dart';
import 'workout_flow.dart';

class HomeData {
  final Map<String, Object?> profile;
  final (int, SplitDay)? today;
  final Session? active;
  final Session? last;
  final List<SessionExercise> lastExercises;
  final LevelInfo level;
  final StreakInfo streak;
  final List<ChecklistItem> checklist;
  final Set<String> checked;
  final Totals food;
  final Targets targets;
  final Map<int, int?> schedule;
  HomeData(this.profile, this.today, this.active, this.last, this.lastExercises, this.level, this.streak,
      this.checklist, this.checked, this.food, this.targets, this.schedule);
}

Future<HomeData> loadHome() async {
  final profile = (await Repo.profile())!;
  final last = (await Repo.doneSessions(limit: 1)).firstOrNull;
  return HomeData(
    profile,
    await Repo.nextDay(),
    await Repo.activeSession(),
    last,
    last == null ? [] : await Repo.loadSession(last.id),
    levelFor(await Repo.xpTotal()),
    streaks(await Repo.sessionDates(), profile['weekly_target'] as int),
    await NutritionRepo.items(includePaused: false),
    await NutritionRepo.doneOn(dayKey(DateTime.now())),
    Totals.of(await NutritionRepo.entries(dayKey(DateTime.now()))),
    await NutritionRepo.targets(),
    await ScheduleRepo.schedule(),
  );
}

class HomeScreen extends StatefulWidget {
  final void Function(int tab) onNavigate;
  const HomeScreen({super.key, required this.onNavigate});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool _popupShown = false;

  void _maybeShowPopup(HomeData d) {
    if (_popupShown || d.active != null) return;
    _popupShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _PreviousWorkoutSheet(data: d));
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Reloading<HomeData>(
          load: loadHome,
          builder: (context, d) {
            _maybeShowPopup(d);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('IRONPULSE',
                        style: TextStyle(color: IP.accent, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${_greeting()}, ${d.profile['name']}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Profile & settings',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  icon: const Icon(Icons.person_outline),
                ),
                IconButton(
                  tooltip: 'Wearables',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WearablesScreen())),
                  icon: const Icon(Icons.watch_outlined),
                ),
                IconButton(
                  tooltip: 'Gym schedule & reminders',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduleScreen())),
                  icon: const Icon(Icons.notifications_none),
                ),
              ]),
              const SizedBox(height: 16),
              _todayCard(context, d),
              const SectionTitle('Progress'),
              _progressCard(d),
              const SectionTitle('Today'),
              _todayNutrition(d),
              const SectionTitle('Previous workout'),
              _previousCard(context, d),
              const SectionTitle('Quick actions'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(
                    avatar: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start workout'),
                    onPressed: () => startWorkout(context)),
                ActionChip(
                    avatar: const Icon(Icons.restaurant, size: 18),
                    label: const Text('Log meal'),
                    onPressed: () => widget.onNavigate(3)),
                ActionChip(
                    avatar: const Icon(Icons.checklist, size: 18),
                    label: const Text('Checklist'),
                    onPressed: () => widget.onNavigate(3)),
                ActionChip(
                    avatar: const Icon(Icons.monitor_weight_outlined, size: 18),
                    label: const Text('Record weight'),
                    onPressed: () => showWeightDialog(context)),
                ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Ask IronPulse AI'),
                    onPressed: () => widget.onNavigate(4)),
                ActionChip(
                    avatar: const Icon(Icons.insights, size: 18),
                    label: const Text('View progress'),
                    onPressed: () => widget.onNavigate(2)),
              ]),
            ]);
          },
        ),
      ),
    );
  }

  Widget _todayCard(BuildContext context, HomeData d) {
    if (d.active != null) {
      return IPCard(
        highlight: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('WORKOUT IN PROGRESS',
              style: TextStyle(color: IP.accent, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 6),
          Text(d.active!.dayName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          Muted('Started ${fmtDuration(d.active!.duration)} ago · progress saved'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: () => startWorkout(context), icon: const Icon(Icons.play_arrow), label: const Text('Resume workout')),
          ),
        ]),
      );
    }
    final t = d.today;
    if (t == null) return const SizedBox.shrink();
    final day = t.$2;
    return IPCard(
      highlight: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("TODAY'S WORKOUT",
            style: TextStyle(color: IP.accent, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
        const SizedBox(height: 6),
        Text(day.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Muted(day.muscles.map(muscleLabel).join(' · ')),
        if (d.schedule.values.any((v) => v != null)) ...[
          const SizedBox(height: 4),
          Text(
            d.schedule[DateTime.now().weekday] == null
                ? 'Scheduled rest day - train anyway if you feel like it'
                : 'Scheduled for ${fmtClock(d.schedule[DateTime.now().weekday]!)}',
            style: const TextStyle(color: IP.accent, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            flex: 2,
            child: FilledButton.icon(
                onPressed: () => startWorkout(context), icon: const Icon(Icons.play_arrow), label: const Text('Start workout')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final ids = await Repo.defaultExerciseIds(day.muscles);
                final all = await Repo.exercises();
                if (!context.mounted) return;
                showModalBottomSheet(
                  context: context,
                  builder: (_) => ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
                    Text(day.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final id in ids)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(all.firstWhere((e) => e.id == id).name),
                        subtitle: Text(muscleLabel(all.firstWhere((e) => e.id == id).muscle)),
                      ),
                  ]),
                );
              },
              child: const Text('Exercises'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _progressCard(HomeData d) {
    final l = d.level;
    final s = d.streak;
    return IPCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.current.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          Text('${l.xp} XP', style: const TextStyle(fontWeight: FontWeight.w800, color: IP.accent)),
        ]),
        const SizedBox(height: 10),
        ProgressBar(l.progress),
        const SizedBox(height: 6),
        Muted(l.next == null ? 'Max level reached' : '${l.xpToNext} XP to ${l.next!.name}', size: 12),
        const Divider(height: 28),
        Row(children: [
          Expanded(child: _mini(Icons.local_fire_department, '${s.current} wk', 'Streak')),
          Expanded(child: _mini(Icons.flag_outlined, '${s.thisWeek}/${s.target}', 'This week')),
          Expanded(child: _mini(Icons.emoji_events_outlined, '${s.longest} wk', 'Best streak')),
        ]),
      ]),
    );
  }

  Widget _todayNutrition(HomeData d) {
    final done = d.checklist.where((i) => d.checked.contains(i.id)).length;
    final pt = d.targets.enabled ? d.targets.protein : null;
    return IPCard(
      onTap: () => widget.onNavigate(3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d.food.protein.round()}${pt != null ? ' / ${pt.round()}' : ''} g',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const Muted('Protein', size: 12),
            if (pt != null && pt > 0) ...[const SizedBox(height: 6), ProgressBar(d.food.protein / pt)],
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.food.entries == 0 ? '-' : '${d.food.calories.round()}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Muted('kcal · ${d.food.entries} logged', size: 12),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.checklist.isEmpty ? '-' : '$done/${d.checklist.length}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const Muted('Checklist', size: 12),
            if (d.checklist.isNotEmpty) ...[
              const SizedBox(height: 6),
              ProgressBar(done / d.checklist.length, color: IP.success),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _mini(IconData icon, String value, String label) => Column(children: [
        Icon(icon, color: IP.muted, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Muted(label, size: 12),
      ]);

  Widget _previousCard(BuildContext context, HomeData d) {
    if (d.last == null) {
      return const IPCard(
        child: Row(children: [
          Icon(Icons.fitness_center, color: IP.accent),
          SizedBox(width: 12),
          Expanded(
              child: Text('Your first workout is waiting. Tap Start, log each set, and your history will show up here.')),
        ]),
      );
    }
    final last = d.last!;
    return IPCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(last.dayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          Muted(fmtDate(last.startedAt), size: 12),
        ]),
        const SizedBox(height: 8),
        for (final e in d.lastExercises.take(4)) _bestLine(e),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => startWorkout(context, repeatSessionId: last.id),
          icon: const Icon(Icons.replay),
          label: const Text('Repeat this workout'),
        ),
      ]),
    );
  }
}

Widget _bestLine(SessionExercise e) {
  final done = e.sets.where((s) => s.done).toList();
  if (done.isEmpty) return const SizedBox.shrink();
  final top = done.reduce((a, b) => (a.weight ?? 0) >= (b.weight ?? 0) ? a : b);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(e.exercise.name)),
      Text('${fmtW(top.weight)} kg × ${top.reps}  ·  ${done.length} sets', style: const TextStyle(color: IP.muted)),
    ]),
  );
}

/// Shown once per app launch: last session vs today's split, clearly separated.
class _PreviousWorkoutSheet extends StatefulWidget {
  final HomeData data;
  const _PreviousWorkoutSheet({required this.data});
  @override
  State<_PreviousWorkoutSheet> createState() => _PreviousWorkoutSheetState();
}

class _PreviousWorkoutSheetState extends State<_PreviousWorkoutSheet> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final last = d.last;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (last == null) ...[
            const Text('Ready for your first session?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Muted('Today: ${d.today?.$2.name ?? ''}. Log weight and reps for each set and tap ✓ to complete it. '
                'A rest timer starts automatically, and everything saves as you go.'),
          ] else ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Previous workout')),
                ButtonSegment(value: 1, label: Text("Today's split")),
              ],
              selected: {_view},
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
            const SizedBox(height: 16),
            if (_view == 0) ...[
              const Muted('Your last gym session', size: 12),
              Text(last.dayName.toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Muted('${fmtDate(last.startedAt)} · ${fmtDuration(last.duration)}'),
              const SizedBox(height: 10),
              for (final e in d.lastExercises) _bestLine(e),
              if (last.notes != null) ...[const SizedBox(height: 8), Muted('Notes: ${last.notes}')],
            ] else ...[
              const Muted('Planned for today', size: 12),
              Text((d.today?.$2.name ?? '').toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Muted(d.today?.$2.muscles.map(muscleLabel).join(' · ') ?? ''),
            ],
          ],
          const SizedBox(height: 20),
          if (last != null) ...[
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                startWorkout(context, repeatSessionId: last.id);
              },
              child: const Text('Repeat previous workout'),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              startWorkout(context);
            },
            child: const Text("Start today's planned workout"),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
        ]),
      ),
    );
  }
}
