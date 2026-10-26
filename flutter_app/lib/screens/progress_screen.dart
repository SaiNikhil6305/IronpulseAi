import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'body.dart';
import 'wearables.dart';

class ProgressData {
  final Stats range;
  final Stats all;
  final LevelInfo level;
  final StreakInfo streak;
  final List<DateTime> dates;
  final List<(String, double)> bests;
  final List<Map<String, Object?>> xp;
  final List<Achievement> achievements;
  ProgressData(this.range, this.all, this.level, this.streak, this.dates, this.bests, this.xp, this.achievements);
}

const _ranges = {'7 days': 7, '30 days': 30, '3 months': 90, 'All time': 0};

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String _range = '30 days';

  Future<ProgressData> _load() async {
    final days = _ranges[_range]!;
    final since = days == 0 ? null : DateTime.now().subtract(Duration(days: days));
    final profile = (await Repo.profile())!;
    final dates = await Repo.sessionDates();
    final all = await Repo.stats();
    final streak = streaks(dates, profile['weekly_target'] as int);
    return ProgressData(
      await Repo.stats(since: since),
      all,
      levelFor(await Repo.xpTotal()),
      streak,
      dates,
      await Repo.personalBests(),
      await Repo.xpHistory(limit: 15),
      achievements(
        workouts: all.workouts,
        sets: all.sets,
        longestStreak: streak.longest,
        prs: await Repo.prCount(),
        firstWorkout: dates.isEmpty ? null : dates.reduce((a, b) => a.isBefore(b) ? a : b),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: Reloading<ProgressData>(
        key: ValueKey(_range),
        load: _load,
        builder: (context, d) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Wrap(spacing: 8, children: [
            for (final r in _ranges.keys)
              ChoiceChip(label: Text(r), selected: _range == r, onSelected: (_) => setState(() => _range = r)),
          ]),
          const SizedBox(height: 12),
          if (d.all.workouts == 0)
            const IPCard(
                child: Text('No finished workouts yet. Charts and insights appear once you have real data - '
                    'nothing here is estimated or made up.'))
          else ...[
            Row(children: [
              StatTile('Workouts', '${d.range.workouts}', icon: Icons.fitness_center),
              const SizedBox(width: 10),
              StatTile('Sets', '${d.range.sets}', icon: Icons.check_circle_outline),
              const SizedBox(width: 10),
              StatTile('Volume kg', fmtW(d.range.volume), icon: Icons.stacked_bar_chart),
            ]),
            if (_insight(d) != null) ...[const SizedBox(height: 10), IPCard(child: Text(_insight(d)!))],
            const SectionTitle('Workouts per week'),
            IPCard(child: _WeekBars(dates: d.dates, target: d.streak.target)),
          ],
          const SectionTitle('Activity & sleep (7 days)'),
          const HealthSummaryCard(),
          const SectionTitle('Body weight'),
          const WeightSection(),
          const SectionTitle('Goals'),
          const GoalsSection(),
          const SectionTitle('Level & streak'),
          IPCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d.level.current.name} · ${d.level.xp} XP', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ProgressBar(d.level.progress),
              const SizedBox(height: 12),
              Text('Current streak: ${d.streak.current} week(s) · Longest: ${d.streak.longest}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Muted('A streak counts weeks in a row where you hit your target of ${d.streak.target} workout(s). '
                  'Rest days never break it, and the current week only counts once you reach the target.', size: 12.5),
            ]),
          ),
          const SectionTitle('Personal bests'),
          if (d.bests.isEmpty)
            const Muted('Log weighted sets to see your best lifts.')
          else
            IPCard(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Column(children: [
                for (final b in d.bests)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(child: Text(b.$1)),
                      Text('${fmtW(b.$2)} kg', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
          const SectionTitle('Achievements'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in d.achievements)
              Tooltip(
                message: a.description,
                child: Chip(
                  avatar: Icon(a.unlocked ? Icons.emoji_events : Icons.lock_outline,
                      size: 18, color: a.unlocked ? IP.warning : IP.muted),
                  label: Text(a.title, style: TextStyle(color: a.unlocked ? IP.text : IP.muted)),
                ),
              ),
          ]),
          const SectionTitle('XP history'),
          if (d.xp.isEmpty)
            const Muted('Complete sets to earn XP: 10 per set, 25 per workout, 30 for hitting your weekly target.')
          else
            IPCard(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Column(children: [
                for (final x in d.xp)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(x['reason'] as String, style: const TextStyle(fontSize: 13.5))),
                      Text('+${x['amount']}', style: const TextStyle(color: IP.accent, fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  String? _insight(ProgressData d) {
    final s = d.streak;
    if (s.thisWeek >= s.target) return 'You completed ${s.thisWeek} workout(s) this week and hit your target. Nice work.';
    if (s.thisWeek > 0) return 'You completed ${s.thisWeek} of ${s.target} planned workout(s) this week.';
    return null;
  }
}

class _WeekBars extends StatelessWidget {
  final List<DateTime> dates;
  final int target;
  const _WeekBars({required this.dates, required this.target});

  @override
  Widget build(BuildContext context) {
    final thisWeek = weekStart(DateTime.now());
    final weeks = [for (var i = 7; i >= 0; i--) thisWeek.subtract(Duration(days: 7 * i))];
    final counts = [for (final w in weeks) dates.where((d) => weekKey(d) == weekKey(w)).length];
    final maxV = [...counts, target, 1].reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 140,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < weeks.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${counts[i]}', style: const TextStyle(fontSize: 11, color: IP.muted)),
                const SizedBox(height: 4),
                Container(
                  height: 90 * counts[i] / maxV + 2,
                  decoration: BoxDecoration(
                    color: counts[i] >= target ? IP.accent : IP.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${weeks[i].day}/${weeks[i].month}', style: const TextStyle(fontSize: 9.5, color: IP.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}
