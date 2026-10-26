import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../data/seed.dart';
import '../data/splits.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'split_picker.dart';
import 'workout_flow.dart';

class WorkoutTab extends StatelessWidget {
  const WorkoutTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workout'),
          bottom: const TabBar(
            indicatorColor: IP.accent,
            labelColor: IP.text,
            unselectedLabelColor: IP.muted,
            tabs: [Tab(text: 'History'), Tab(text: 'Exercises'), Tab(text: 'My split')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: IP.accent,
          foregroundColor: Colors.black,
          onPressed: () => startWorkout(context),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: const TabBarView(children: [_History(), _Library(), _MySplit()]),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History();
  @override
  Widget build(BuildContext context) => Reloading<List<Session>>(
        load: () => Repo.doneSessions(),
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyState(
                icon: Icons.history, title: 'No workouts yet', body: 'Finished workouts appear here with every set.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = list[i];
              return IPCard(
                onTap: () => _showSession(context, s),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.dayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Muted('${fmtDate(s.startedAt)} · ${fmtDuration(s.duration)}', size: 12.5),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: IP.muted),
                ]),
              );
            },
          );
        },
      );

  Future<void> _showSession(BuildContext context, Session s) async {
    final items = await Repo.loadSession(s.id);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
          Text(s.dayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Muted('${fmtDate(s.startedAt)} · ${fmtDuration(s.duration)}'),
          if (s.notes != null) ...[const SizedBox(height: 8), Text(s.notes!)],
          const SizedBox(height: 12),
          for (final e in items) ...[
            Text(e.exercise.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            for (final set in e.sets)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Muted('Set ${set.index + 1}: ${fmtW(set.weight)} kg × ${set.reps ?? '-'}'),
              ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              startWorkout(context, repeatSessionId: s.id);
            },
            icon: const Icon(Icons.replay),
            label: const Text('Repeat this workout'),
          ),
        ]),
      ),
    );
  }
}

class _Library extends StatefulWidget {
  const _Library();
  @override
  State<_Library> createState() => _LibraryState();
}

class _LibraryState extends State<_Library> {
  String _q = '';

  Future<void> _addCustom() async {
    final name = TextEditingController();
    final equipment = TextEditingController();
    var muscle = 'chest';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Custom exercise'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: muscle,
              decoration: const InputDecoration(labelText: 'Muscle group'),
              items: [for (final m in muscleLabels.keys) DropdownMenuItem(value: m, child: Text(muscleLabel(m)))],
              onChanged: (v) => setD(() => muscle = v ?? muscle),
            ),
            const SizedBox(height: 10),
            TextField(controller: equipment, decoration: const InputDecoration(labelText: 'Equipment (optional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await Repo.addCustomExercise(name.text, muscle, equipment.text);
      notifyDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search exercises'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Add custom exercise', onPressed: _addCustom, icon: const Icon(Icons.add)),
        ]),
      ),
      Expanded(
        child: Reloading<List<Exercise>>(
          key: ValueKey(_q),
          load: () => Repo.exercises(query: _q),
          builder: (context, list) {
            if (list.isEmpty) {
              return const EmptyState(icon: Icons.search_off, title: 'No matches', body: 'Try another name, or add a custom exercise.');
            }
            String? lastMuscle;
            final children = <Widget>[];
            for (final e in list) {
              if (e.muscle != lastMuscle) {
                lastMuscle = e.muscle;
                children.add(SectionTitle(muscleLabel(e.muscle)));
              }
              children.add(ListTile(
                title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(e.equipment + (e.custom ? ' · custom' : '')),
                onTap: () => _showExercise(context, e),
              ));
            }
            return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 96), children: children);
          },
        ),
      ),
    ]);
  }

  Future<void> _showExercise(BuildContext context, Exercise e) async {
    final prev = await Repo.previousSets(e.id);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Muted('${muscleLabel(e.muscle)} · ${e.equipment}'),
          const SizedBox(height: 12),
          Text(e.instructions),
          const SizedBox(height: 16),
          const Muted('Your last session', size: 12),
          const SizedBox(height: 4),
          Text(prev.isEmpty ? 'Not logged yet' : prev.map((p) => '${fmtW(p.weight)} kg × ${p.reps}').join(', '),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Muted('No demo video yet - only properly licensed media will be added.', size: 12),
        ]),
      ),
    );
  }
}

class _MySplit extends StatelessWidget {
  const _MySplit();
  @override
  Widget build(BuildContext context) => Reloading<(List<SplitDay>, (int, SplitDay)?)>(
        load: () async => (await Repo.splitDays(), await Repo.nextDay()),
        builder: (context, data) {
          final (days, next) = data;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
            const Muted('IronPulse rotates through your days in order. After you finish a session, '
                'the next day becomes "today". Rest whenever you need - the rotation waits for you.'),
            const SizedBox(height: 12),
            for (var i = 0; i < days.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: IPCard(
                  highlight: next?.$1 == i,
                  child: Row(children: [
                    Text('${i + 1}', style: const TextStyle(color: IP.accent, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(days[i].name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Muted(days[i].muscles.map(muscleLabel).join(' · '), size: 12.5),
                      ]),
                    ),
                    if (next?.$1 == i) const Text('NEXT', style: TextStyle(color: IP.accent, fontWeight: FontWeight.w900, fontSize: 12)),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SplitEditorScreen(templateKey: 'custom', days: days))),
              icon: const Icon(Icons.edit),
              label: const Text('Edit current split'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SplitPickerScreen())),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Switch to a different split'),
            ),
          ]);
        },
      );
}
