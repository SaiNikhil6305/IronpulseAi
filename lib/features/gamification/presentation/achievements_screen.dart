import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../data/gamification_provider.dart';
import '../domain/xp_rules.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gamificationProvider);
    final lvl = g.level;
    return Scaffold(
      appBar: AppBar(title: const Text('XP & achievements')),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Level ${lvl.level}', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            Text(lvl.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Gaps.md),
            ProgressBar(value: lvl.progress, height: 10),
            const SizedBox(height: Gaps.sm),
            Text(lvl.nextXp == null
                ? '${lvl.totalXp} XP · top level'
                : '${lvl.totalXp} XP · ${lvl.xpToNext} XP to ${lvl.nextName}'),
            const SizedBox(height: 4),
            Text(
              g.serverConfirmed
                  ? 'Confirmed by the IronPulse server.'
                  : 'Calculated on this device with the same rules the server uses. Synced totals are authoritative.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ]),
        ),
        const SectionHeader('How XP works'),
        AppCard(
          child: Column(children: [
            _rule('Complete a valid set', XpRules.set),
            _rule('Finish a workout (bonus, max 2 per day)', XpRules.workout),
            _rule('Tick a checklist item (once per item per day)', XpRules.checklist),
            _rule('Weekly weigh-in (once per week)', XpRules.weighIn),
            _rule('Reach your weekly training target', XpRules.weeklyTarget),
            const SizedBox(height: Gaps.sm),
            const Text(
              'Each event can only earn XP once — editing, re-ticking or re-syncing never adds more. XP rewards '
              'consistency, not lifting heavier than is safe for you.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ]),
        ),
        const SectionHeader('Levels'),
        AppCard(
          child: Column(children: [
            for (var i = 0; i < XpRules.levels.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(lvl.level > i ? Icons.check_circle : Icons.circle_outlined,
                    color: lvl.level > i ? AppColors.accent : AppColors.textMuted),
                title: Text(XpRules.levels[i].$2),
                trailing: Text('${XpRules.levels[i].$1} XP', style: const TextStyle(color: AppColors.textMuted)),
              ),
          ]),
        ),
        const SectionHeader('Achievements'),
        for (final a in XpRules.achievements.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.sm),
            child: AppCard(
              borderColor: g.unlocked.containsKey(a.key) ? AppColors.accent : null,
              padding: const EdgeInsets.all(Gaps.md),
              child: Row(children: [
                Icon(Icons.emoji_events_rounded,
                    size: 32, color: g.unlocked.containsKey(a.key) ? AppColors.accent : AppColors.surfaceHigh),
                const SizedBox(width: Gaps.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.value.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(a.value.$2, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ]),
                ),
                if (g.unlocked[a.key] != null)
                  Text(Dates.friendly(g.unlocked[a.key]!), style: const TextStyle(color: AppColors.textMuted, fontSize: 12))
                else if (g.unlocked.containsKey(a.key))
                  const Icon(Icons.check, color: AppColors.accent),
              ]),
            ),
          ),
        const SectionHeader('Streak'),
        AppCard(child: Text(g.streak.explanation)),
      ]),
    );
  }

  Widget _rule(String label, int xp) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('+$xp XP', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
        ]),
      );
}
