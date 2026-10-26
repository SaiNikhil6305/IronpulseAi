import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../data/seed.dart';
import '../data/splits.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SplitPickerScreen extends StatelessWidget {
  final bool firstRun;
  const SplitPickerScreen({super.key, this.firstRun = false});

  @override
  Widget build(BuildContext context) {
    final templates = splitTemplates();
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your split'), automaticallyImplyLeading: !firstRun),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: templates.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return const Muted('Pick a starting point. You can rename days, change muscles and switch later - '
                'your workout history is always kept.');
          }
          final t = templates[i - 1];
          return IPCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SplitEditorScreen(templateKey: t.key, days: t.days, firstRun: firstRun))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Muted(t.description),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final d in t.days)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: IP.surface2, borderRadius: BorderRadius.circular(8)),
                        child: Text(d.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right, color: IP.muted),
            ]),
          );
        },
      ),
    );
  }
}

class SplitEditorScreen extends StatefulWidget {
  final String templateKey;
  final List<SplitDay> days;
  final bool firstRun;
  const SplitEditorScreen({super.key, required this.templateKey, required this.days, this.firstRun = false});
  @override
  State<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends State<SplitEditorScreen> {
  late final List<SplitDay> _days = widget.days.map((d) => d.copy()).toList();

  Future<void> _save() async {
    if (_days.isEmpty || _days.any((d) => d.name.trim().isEmpty || d.muscles.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Every day needs a name and at least one muscle group')));
      return;
    }
    await Repo.saveSplit(widget.templateKey, _days);
    notifyDataChanged();
    if (!mounted) return;
    if (widget.firstRun) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _rename(int i) async {
    final c = TextEditingController(text: _days[i].name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Day name'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) setState(() => _days[i].name = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customize days')),
      body: ReorderableListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        onReorder: (a, b) => setState(() {
          if (b > a) b--;
          _days.insert(b, _days.removeAt(a));
        }),
        footer: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _days.add(SplitDay('Day ${_days.length + 1}', []))),
            icon: const Icon(Icons.add),
            label: const Text('Add day'),
          ),
        ),
        children: [
          for (var i = 0; i < _days.length; i++)
            Padding(
              key: ObjectKey(_days[i]),
              padding: const EdgeInsets.only(bottom: 12),
              child: IPCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${i + 1}', style: const TextStyle(color: IP.accent, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _rename(i),
                        child: Row(children: [
                          Flexible(
                              child: Text(_days[i].name,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, size: 16, color: IP.muted),
                        ]),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove day',
                      onPressed: _days.length > 1 ? () => setState(() => _days.removeAt(i)) : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    const Icon(Icons.drag_handle, color: IP.muted),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in muscleLabels.keys)
                      FilterChip(
                        label: Text(muscleLabel(m)),
                        selected: _days[i].muscles.contains(m),
                        onSelected: (on) => setState(() => on ? _days[i].muscles.add(m) : _days[i].muscles.remove(m)),
                      ),
                  ]),
                ]),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: const Text('Save split')),
        ),
      ),
    );
  }
}
