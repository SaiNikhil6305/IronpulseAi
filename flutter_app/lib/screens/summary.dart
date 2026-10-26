import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SummaryScreen extends StatelessWidget {
  final Summary summary;
  const SummaryScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout complete'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        IPCard(
          highlight: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.dayName.toUpperCase(),
                style: const TextStyle(color: IP.accent, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
            const SizedBox(height: 6),
            Text('+${s.xp} XP', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            Muted('Duration ${fmtDuration(s.duration)}'),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          StatTile('Exercises', '${s.exercises}'),
          const SizedBox(width: 10),
          StatTile('Sets', '${s.sets}'),
          const SizedBox(width: 10),
          StatTile('Reps', '${s.reps}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          StatTile('Est. volume (kg × reps)', fmtW(s.volume)),
        ]),
        const SizedBox(height: 6),
        const Muted('Volume is total weight lifted (weight × reps). It is not calories burned.', size: 12),
        if (s.prs.isNotEmpty) ...[
          const SectionTitle('Personal records'),
          for (final p in s.prs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: IPCard(
                child: Row(children: [
                  const Icon(Icons.emoji_events, color: IP.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
            ),
        ],
        if (s.notes != null) ...[
          const SectionTitle('Notes'),
          IPCard(child: Text(s.notes!)),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    );
  }
}
