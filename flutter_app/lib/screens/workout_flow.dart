import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../data/seed.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'logger.dart';

const extraMuscles = ['traps', 'forearms', 'core', 'calves', 'biceps', 'triceps', 'shoulders'];

/// Starts (or resumes) a workout. [repeatSessionId] copies the exercises of a past session.
Future<void> startWorkout(BuildContext context, {String? repeatSessionId}) async {
  final nav = Navigator.of(context);
  final active = await Repo.activeSession();
  if (active != null) {
    if (!context.mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workout in progress'),
        content: Text('You have an unfinished ${active.dayName} from ${fmtTime(active.startedAt)}. Resume it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resume')),
        ],
      ),
    );
    if (resume == null) return;
    if (resume) {
      await nav.push(MaterialPageRoute(builder: (_) => LoggerScreen(sessionId: active.id)));
      notifyDataChanged();
      return;
    }
    await Repo.discardSession(active.id);
  }

  String sid;
  if (repeatSessionId != null) {
    final prev = await Repo.session(repeatSessionId);
    final exs = await Repo.loadSession(repeatSessionId);
    sid = await Repo.startSession(
        dayIndex: prev.dayIndex, dayName: prev.dayName, exerciseIds: exs.map((e) => e.exercise.id).toList());
  } else {
    final next = await Repo.nextDay();
    if (next == null || !context.mounted) return;
    final (index, day) = next;
    final extras = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExtraMusclesSheet(dayName: day.name, exclude: day.muscles),
    );
    if (extras == null) return; // dismissed
    final ids = [
      ...await Repo.defaultExerciseIds(day.muscles),
      ...await Repo.defaultExerciseIds(extras, perMuscle: 1),
    ];
    sid = await Repo.startSession(dayIndex: index, dayName: day.name, exerciseIds: ids);
  }
  notifyDataChanged();
  await nav.push(MaterialPageRoute(builder: (_) => LoggerScreen(sessionId: sid)));
  notifyDataChanged();
}

String fmtTime(DateTime d) =>
    '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Want to train anything extra today?" - one-session only, never changes the saved split.
class ExtraMusclesSheet extends StatefulWidget {
  final String dayName;
  final List<String> exclude;
  const ExtraMusclesSheet({super.key, required this.dayName, required this.exclude});
  @override
  State<ExtraMusclesSheet> createState() => _ExtraMusclesSheetState();
}

class _ExtraMusclesSheetState extends State<ExtraMusclesSheet> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final options = extraMuscles.where((m) => !widget.exclude.contains(m)).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.dayName.toUpperCase(),
              style: const TextStyle(color: IP.accent, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 6),
          const Text('Want to train anything extra today?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Muted('Adds one exercise per group to this session only. Your split stays the same.'),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in options)
              FilterChip(
                label: Text(muscleLabel(m)),
                selected: _picked.contains(m),
                onSelected: (on) => setState(() => on ? _picked.add(m) : _picked.remove(m)),
              ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, <String>[]), child: const Text('Skip'))),
            const SizedBox(width: 12),
            Expanded(
                flex: 2,
                child: FilledButton(
                    onPressed: () => Navigator.pop(context, _picked.toList()),
                    child: Text(_picked.isEmpty ? 'Start workout' : 'Start with ${_picked.length} extra'))),
          ]),
        ]),
      ),
    );
  }
}

/// Searchable exercise picker. Returns the chosen exercise id.
Future<String?> pickExercise(BuildContext context, {String? muscle}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _ExercisePicker(muscle: muscle)),
    );

class _ExercisePicker extends StatefulWidget {
  final String? muscle;
  const _ExercisePicker({this.muscle});
  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  String _q = '';
  late String? _muscle = widget.muscle;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          autofocus: false,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search exercises'),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(label: const Text('All'), selected: _muscle == null, onSelected: (_) => setState(() => _muscle = null)),
          ),
          for (final m in muscleLabels.keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                  label: Text(muscleLabel(m)), selected: _muscle == m, onSelected: (_) => setState(() => _muscle = m)),
            ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<Exercise>>(
          future: Repo.exercises(query: _q, muscle: _muscle),
          builder: (context, snap) {
            final list = snap.data ?? [];
            if (snap.hasData && list.isEmpty) {
              return const EmptyState(icon: Icons.search_off, title: 'No matches', body: 'Try another name or filter.');
            }
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${muscleLabel(list[i].muscle)} · ${list[i].equipment}'),
                onTap: () => Navigator.pop(context, list[i].id),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
