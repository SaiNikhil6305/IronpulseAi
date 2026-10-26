import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/notifications.dart';
import '../data/repo.dart';
import '../data/seed.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'summary.dart';
import 'workout_flow.dart';

/// Every change is written to SQLite immediately, so closing the app never loses a set.
class LoggerScreen extends StatefulWidget {
  final String sessionId;
  const LoggerScreen({super.key, required this.sessionId});
  @override
  State<LoggerScreen> createState() => _LoggerScreenState();
}

class _LoggerScreenState extends State<LoggerScreen> {
  Session? _session;
  List<SessionExercise> _items = [];
  final Map<String, List<PrevSet>> _prev = {};
  final Map<String, (TextEditingController, TextEditingController)> _ctrl = {};
  Timer? _ticker;
  int _restTotal = 90;
  int? _restLeft;
  bool _restPaused = false;
  bool _vibrate = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _ctrl.values) {
      c.$1.dispose();
      c.$2.dispose();
    }
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      if (_restLeft != null && !_restPaused) {
        _restLeft = _restLeft! - 1;
        if (_restLeft! <= 0) {
          _restLeft = null;
          if (_vibrate) HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        }
      }
    });
  }

  Future<void> _load() async {
    final s = await Repo.session(widget.sessionId);
    final items = await Repo.loadSession(widget.sessionId);
    final profile = await Repo.profile();
    for (final e in items) {
      _prev[e.exercise.id] ??= await Repo.previousSets(e.exercise.id);
      for (final set in e.sets) {
        _ctrl.putIfAbsent(
            set.id,
            () => (
                  TextEditingController(text: set.weight == null ? '' : fmtW(set.weight)),
                  TextEditingController(text: set.reps?.toString() ?? ''),
                ));
      }
    }
    if (!mounted) return;
    setState(() {
      _session = s;
      _items = items;
      _restTotal = (profile?['rest_seconds'] as int?) ?? 90;
    });
  }

  Future<void> _save(WSet set) async {
    final c = _ctrl[set.id]!;
    set.weight = double.tryParse(c.$1.text.replaceAll(',', '.'));
    set.reps = int.tryParse(c.$2.text);
    await Repo.updateSet(set.id, set.weight, set.reps);
  }

  Future<void> _toggle(WSet set) async {
    await _save(set);
    if (!mounted) return;
    if (!set.done && (set.reps ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter reps before completing the set')));
      return;
    }
    final done = !set.done;
    await Repo.setDone(set.id, done);
    setState(() {
      set.done = done;
      if (done) {
        _restLeft = _restTotal;
        _restPaused = false;
      }
    });
    if (done && _vibrate) HapticFeedback.mediumImpact();
  }

  Future<void> _addSet(SessionExercise e) async {
    final s = await Repo.addSet(e.id);
    _ctrl[s.id] = (
      TextEditingController(text: s.weight == null ? '' : fmtW(s.weight)),
      TextEditingController(text: s.reps?.toString() ?? ''),
    );
    setState(() => e.sets.add(s));
  }

  Future<void> _removeSet(SessionExercise e, WSet s) async {
    await Repo.removeSet(s.id);
    setState(() => e.sets.remove(s));
  }

  /// One tap fills the last session's numbers into empty, unfinished sets. Values stay editable.
  Future<void> _copyPrevious(SessionExercise e) async {
    final prev = _prev[e.exercise.id] ?? [];
    while (e.sets.length < prev.length) {
      await _addSet(e);
    }
    for (var i = 0; i < prev.length; i++) {
      final s = e.sets[i];
      if (s.done) continue;
      final c = _ctrl[s.id]!;
      c.$1.text = prev[i].weight == null ? '' : fmtW(prev[i].weight);
      c.$2.text = prev[i].reps?.toString() ?? '';
      await _save(s);
    }
    setState(() {});
  }

  Future<void> _exerciseMenu(SessionExercise e, String action) async {
    if (action == 'replace') {
      final id = await pickExercise(context, muscle: e.exercise.muscle);
      if (id == null) return;
      await Repo.replaceExercise(e.id, id);
      final ex = (await Repo.exercises()).firstWhere((x) => x.id == id);
      _prev[id] ??= await Repo.previousSets(id);
      setState(() => e.exercise = ex);
    } else if (action == 'remove') {
      await Repo.removeExercise(e.id);
      setState(() => _items.remove(e));
    } else if (action == 'info') {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.exercise.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Muted('${muscleLabel(e.exercise.muscle)} · ${e.exercise.equipment}'),
            const SizedBox(height: 12),
            Text(e.exercise.instructions),
            const SizedBox(height: 20),
          ]),
        ),
      );
    }
  }

  Future<void> _addExercise() async {
    final id = await pickExercise(context);
    if (id == null) return;
    await Repo.addExerciseToSession(widget.sessionId, id);
    await _load();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final notes = TextEditingController();
    final completed = _items.expand((e) => e.sets).where((s) => s.done).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish workout?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(completed == 0
              ? 'No sets are completed yet, so this workout will be discarded.'
              : '$completed sets completed. Unchecked sets will not be saved.'),
          const SizedBox(height: 12),
          if (completed > 0)
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(hintText: 'Notes (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep training')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(completed == 0 ? 'Discard' : 'Finish')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _finishing = true);
    for (final e in _items) {
      for (final s in e.sets) {
        await _save(s);
      }
    }
    final summary = await Repo.finishSession(widget.sessionId, notes.text.trim().isEmpty ? null : notes.text.trim());
    notifyDataChanged();
    Notifs.reschedule().catchError((_) => 0); // next reminder names the next day in the rotation
    if (!mounted) return;
    if (summary == null) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SummaryScreen(summary: summary)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s?.dayName ?? 'Workout'),
          if (s != null)
            Text(fmtDuration(s.duration), style: const TextStyle(fontSize: 13, color: IP.muted, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            tooltip: _vibrate ? 'Vibration on' : 'Vibration off',
            onPressed: () => setState(() => _vibrate = !_vibrate),
            icon: Icon(_vibrate ? Icons.vibration : Icons.mobile_off),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _finishing ? null : _finish,
              child: const Text('Finish'),
            ),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 140),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  for (final e in _items) ...[_exerciseCard(e), const SizedBox(height: 12)],
                  OutlinedButton.icon(onPressed: _addExercise, icon: const Icon(Icons.add), label: const Text('Add exercise')),
                ],
              ),
            ),
      bottomSheet: _restLeft == null ? null : _restBar(),
    );
  }

  Widget _exerciseCard(SessionExercise e) {
    final prev = _prev[e.exercise.id] ?? [];
    return IPCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.exercise.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                prev.isEmpty
                    ? 'First time logging this exercise'
                    : 'Last session: ${prev.map((p) => '${fmtW(p.weight)} kg × ${p.reps ?? '-'}').join(', ')}',
                style: const TextStyle(color: IP.muted, fontSize: 12.5),
              ),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (a) => _exerciseMenu(e, a),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'info', child: Text('How to do it')),
              PopupMenuItem(value: 'replace', child: Text('Replace exercise')),
              PopupMenuItem(value: 'remove', child: Text('Remove from workout')),
            ],
          ),
        ]),
        if (prev.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () => _copyPrevious(e),
              icon: const Icon(Icons.content_copy, size: 16),
              label: const Text('Copy last session'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4, right: 8),
          child: Row(children: [
            SizedBox(width: 36, child: Muted('SET', size: 11)),
            Expanded(child: Muted('KG', size: 11)),
            SizedBox(width: 8),
            Expanded(child: Muted('REPS', size: 11)),
            SizedBox(width: 96),
          ]),
        ),
        for (var i = 0; i < e.sets.length; i++) _setRow(e, e.sets[i], i, prev.length > i ? prev[i] : null),
        TextButton.icon(onPressed: () => _addSet(e), icon: const Icon(Icons.add, size: 18), label: const Text('Add set')),
      ]),
    );
  }

  Widget _setRow(SessionExercise e, WSet set, int i, PrevSet? prev) {
    final c = _ctrl[set.id]!;
    final done = set.done;
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          fillColor: done ? IP.success.withOpacity(0.12) : IP.surface2,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 36,
            child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: done ? IP.success : IP.text))),
        Expanded(
          child: TextField(
            controller: c.$1,
            enabled: !done,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: deco(prev?.weight == null ? 'kg' : fmtW(prev!.weight)),
            onChanged: (_) => _save(set),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: c.$2,
            enabled: !done,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: deco(prev?.reps?.toString() ?? 'reps'),
            onChanged: (_) => _save(set),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            tooltip: done ? 'Edit set' : 'Complete set',
            onPressed: () => _toggle(set),
            style: IconButton.styleFrom(backgroundColor: done ? IP.success : IP.surface2),
            icon: Icon(Icons.check, color: done ? Colors.black : IP.muted),
          ),
        ),
        SizedBox(
          width: 44,
          child: IconButton(
            tooltip: 'Remove set',
            onPressed: e.sets.length > 1 ? () => _removeSet(e, set) : null,
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
      ]),
    );
  }

  Widget _restBar() {
    final left = _restLeft!;
    return Material(
      color: IP.surface2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ProgressBar(left / _restTotal),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.timer_outlined, color: IP.accent),
              const SizedBox(width: 8),
              Text('Rest ${fmtDuration(Duration(seconds: left))}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: _restPaused ? 'Resume' : 'Pause',
                onPressed: () => setState(() => _restPaused = !_restPaused),
                icon: Icon(_restPaused ? Icons.play_arrow : Icons.pause),
              ),
              TextButton(onPressed: () => setState(() => _restLeft = left + 30), child: const Text('+30s')),
              TextButton(onPressed: () => setState(() => _restLeft = null), child: const Text('Skip')),
            ]),
          ]),
        ),
      ),
    );
  }
}
