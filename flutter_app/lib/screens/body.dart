import 'package:flutter/material.dart';

import '../data/nutrition_repo.dart';
import '../data/repo.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showWeightDialog(BuildContext context) async {
  final last = await NutritionRepo.weights();
  if (!context.mounted) return;
  final w = TextEditingController(text: last.isEmpty ? '' : fmtW(last.last.kg));
  final notes = TextEditingController();
  var day = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Record weight'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: w,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Weight (kg)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(fmtDate(day)),
            onPressed: () async {
              final p = await showDatePicker(
                  context: ctx, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (p != null) setD(() => day = p);
            },
          ),
          const SizedBox(height: 10),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          const SizedBox(height: 8),
          const Muted('Tip: weigh at the same time each week, e.g. morning before eating.', size: 12),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  final kg = double.tryParse(w.text.trim().replaceAll(',', '.'));
  if (ok != true || kg == null || kg <= 0 || kg > 400) return;
  final xp = await NutritionRepo.logWeight(day, kg, notes.text.trim().isEmpty ? null : notes.text.trim());
  notifyDataChanged();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(xp ? 'Weight saved · +${XpRules2.weighIn} XP weekly weigh-in' : 'Weight saved')));
  }
}

class WeightSection extends StatelessWidget {
  const WeightSection({super.key});

  @override
  Widget build(BuildContext context) => Reloading<List<WeightEntry>>(
        load: NutritionRepo.weights,
        builder: (context, list) => IPCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(list.isEmpty ? 'No weigh-ins yet' : '${fmtW(list.last.kg)} kg',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              FilledButton.tonal(onPressed: () => showWeightDialog(context), child: const Text('Log weight')),
            ]),
            if (list.isNotEmpty) Muted('Last: ${fmtDate(parseDay(list.last.day))}', size: 12),
            if (list.length >= 2) ...[
              const SizedBox(height: 14),
              SizedBox(height: 120, width: double.infinity, child: CustomPaint(painter: _LinePainter(list.map((e) => e.kg).toList()))),
              const SizedBox(height: 8),
              Muted(_trendText(list), size: 12.5),
            ],
          ]),
        ),
      );

  String _trendText(List<WeightEntry> l) {
    final diff = l.last.kg - l.first.kg;
    final span = parseDay(l.last.day).difference(parseDay(l.first.day)).inDays;
    final dir = diff.abs() < 0.05 ? 'no change' : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg';
    return 'Recorded change over $span days: $dir. Weight moves day to day with water and food, so short-term '
        'changes do not show muscle gain or fat loss on their own.';
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  _LinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b) - 0.5;
    final maxV = values.reduce((a, b) => a > b ? a : b) + 0.5;
    Offset pt(int i) => Offset(
          values.length == 1 ? size.width / 2 : i * size.width / (values.length - 1),
          size.height - (values[i] - minV) / (maxV - minV) * size.height,
        );
    final grid = Paint()
      ..color = IP.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = IP.accent
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    final dot = Paint()..color = IP.accent;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(pt(i), 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}

class GoalsSection extends StatelessWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context) => Reloading<List<(Goal, (double?, String))>>(
        load: () async => [for (final g in await NutritionRepo.goals()) (g, await NutritionRepo.goalProgress(g))],
        builder: (context, list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (g, (p, label)) in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IPCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(g.title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: g.status == 'active' ? IP.text : IP.muted)),
                    ),
                    if (g.status != 'active')
                      Text(g.status.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: g.status == 'completed' ? IP.success : IP.muted)),
                    PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'delete') {
                          await NutritionRepo.deleteGoal(g.id);
                        } else {
                          await NutritionRepo.setGoalStatus(g.id, a);
                        }
                        notifyDataChanged();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'completed', child: Text('Mark completed')),
                        PopupMenuItem(value: 'active', child: Text('Mark active')),
                        PopupMenuItem(value: 'abandoned', child: Text('Stop this goal')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ]),
                  Muted('${goalTypes[g.type]} · ${fmtDate(parseDay(g.startDay))} → ${fmtDate(parseDay(g.targetDay))}', size: 12),
                  if (p != null) ...[const SizedBox(height: 10), ProgressBar(p, color: p >= 1 ? IP.success : IP.accent)],
                  const SizedBox(height: 6),
                  Muted(label, size: 12.5),
                  if (g.notes != null) ...[const SizedBox(height: 4), Text(g.notes!, style: const TextStyle(fontSize: 13))],
                ]),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => showGoalDialog(context),
            icon: const Icon(Icons.add),
            label: Text(list.isEmpty ? 'Set your first goal' : 'Add goal'),
          ),
        ]),
      );
}

Future<void> showGoalDialog(BuildContext context) async {
  var type = 'weight';
  var months = 3;
  final value = TextEditingController();
  final notes = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final needsValue = type == 'weight' || type == 'workouts' || type == 'consistency';
      return AlertDialog(
        title: const Text('New goal'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(
              value: type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Goal'),
              items: [for (final e in goalTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setD(() => type = v ?? type),
            ),
            const SizedBox(height: 12),
            const Muted('Duration', size: 12),
            Wrap(spacing: 8, children: [
              for (final m in [2, 3, 6, 12])
                ChoiceChip(label: Text('$m months'), selected: months == m, onSelected: (_) => setD(() => months = m)),
            ]),
            if (needsValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: type == 'weight' ? 'Target weight (kg)' : 'Number of workouts'),
              ),
            ],
            const SizedBox(height: 12),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes / milestones (optional)')),
            const SizedBox(height: 8),
            const Muted('Results vary from person to person. Aim for steady, sustainable progress.', size: 12),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      );
    }),
  );
  if (ok != true) return;
  final now = DateTime.now();
  await NutritionRepo.addGoal(
    type: type,
    title: goalTypes[type]!,
    target: DateTime(now.year, now.month + months, now.day),
    targetValue: double.tryParse(value.text.trim().replaceAll(',', '.')),
    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
  );
  notifyDataChanged();
}
