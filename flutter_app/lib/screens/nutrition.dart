import 'package:flutter/material.dart';

import '../data/nutrition_repo.dart';
import '../data/repo.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NutritionData {
  final List<ChecklistItem> items;
  final Set<String> done;
  final List<FoodEntry> entries;
  final Targets targets;
  final (Totals, int) week;
  NutritionData(this.items, this.done, this.entries, this.targets, this.week);
}

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  DateTime _day = DateTime.now();
  String get _key => dayKey(_day);
  bool get _isToday => dayKey(DateTime.now()) == _key;

  Future<NutritionData> _load() async => NutritionData(
        await NutritionRepo.items(includePaused: false),
        await NutritionRepo.doneOn(_key),
        await NutritionRepo.entries(_key),
        await NutritionRepo.targets(),
        await NutritionRepo.weeklyAverage(_day),
      );

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(DateTime.now())) return;
    setState(() => _day = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition'),
        actions: [
          IconButton(
              tooltip: 'Targets',
              icon: const Icon(Icons.tune),
              onPressed: () async {
                await showTargetsDialog(context);
                notifyDataChanged();
              }),
          IconButton(
              tooltip: 'Manage checklist',
              icon: const Icon(Icons.checklist),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChecklistManager()))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: IP.accent,
        foregroundColor: Colors.black,
        onPressed: () => showFoodSheet(context, day: _key, meal: _isToday ? mealForNow() : 'morning'),
        icon: const Icon(Icons.add),
        label: const Text('Log food', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Reloading<NutritionData>(
        key: ValueKey(_key),
        load: _load,
        builder: (context, d) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
          Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(_isToday ? 'Today' : fmtDate(_day),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            IconButton(onPressed: _isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ]),
          _totalsCard(d),
          SectionTitle('Daily checklist',
              trailing: d.items.isEmpty ? null : Muted('${d.done.intersection(d.items.map((e) => e.id).toSet()).length}/${d.items.length}', size: 12)),
          _checklist(context, d),
          for (final m in meals) ..._meal(context, d, m),
          const SectionTitle('Last 7 days'),
          IPCard(
            child: d.week.$2 == 0
                ? const Muted('No food logged in the last 7 days.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Average per logged day (${d.week.$2} day${d.week.$2 == 1 ? '' : 's'})',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Muted('${d.week.$1.calories.round()} kcal · ${d.week.$1.protein.round()} g protein · '
                        '${d.week.$1.carbs.round()} g carbs · ${d.week.$1.fat.round()} g fat'),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _totalsCard(NutritionData d) {
    final t = Totals.of(d.entries);
    final tg = d.targets;
    Widget macro(String label, double v, double? target, String unit) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${v.round()}${target != null && tg.enabled ? ' / ${target.round()}' : ''}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Muted('$label ($unit)', size: 12),
            if (target != null && tg.enabled && target > 0) ...[
              const SizedBox(height: 6),
              ProgressBar(v / target, color: v > target * 1.15 ? IP.warning : IP.accent),
            ],
          ]),
        );
    return IPCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          macro('Calories', t.calories, tg.calories, 'kcal'),
          const SizedBox(width: 16),
          macro('Protein', t.protein, tg.protein, 'g'),
        ]),
        const SizedBox(height: 12),
        Muted('Carbs ${t.carbs.round()} g · Fat ${t.fat.round()} g · ${t.entries} item${t.entries == 1 ? '' : 's'} logged', size: 12.5),
        const SizedBox(height: 4),
        Muted(
            t.incomplete
                ? 'Totals use only the values you entered - some items have no calories or protein.'
                : 'Totals are estimates from the values you entered.',
            size: 11.5),
      ]),
    );
  }

  Widget _checklist(BuildContext context, NutritionData d) {
    if (d.items.isEmpty) {
      return IPCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChecklistManager())),
        child: const Row(children: [
          Icon(Icons.add_task, color: IP.accent),
          SizedBox(width: 12),
          Expanded(child: Text('Add things you want to tick off daily - protein shake, eggs, creatine, water. Entirely optional.')),
        ]),
      );
    }
    return IPCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        for (final it in d.items)
          CheckboxListTile(
            value: d.done.contains(it.id),
            activeColor: IP.accent,
            checkColor: Colors.black,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if (it.quantity != null) it.quantity!,
              it.category == 'supplement' ? 'Supplement' : (it.category == 'food' ? 'Food' : 'Habit'),
              if (it.protein != null) '${fmtW(it.protein)} g protein',
            ].join(' · ')),
            onChanged: (v) async {
              await NutritionRepo.setChecked(it, _key, v ?? false);
              notifyDataChanged();
            },
          ),
      ]),
    );
  }

  List<Widget> _meal(BuildContext context, NutritionData d, String meal) {
    final list = d.entries.where((e) => e.meal == meal).toList();
    final t = Totals.of(list);
    return [
      SectionTitle(mealLabels[meal]!,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (list.isNotEmpty) Muted('${t.calories.round()} kcal · ${t.protein.round()} g P', size: 12),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz, size: 20, color: IP.muted),
              onSelected: (a) async {
                if (a == 'add') {
                  await showFoodSheet(context, day: _key, meal: meal);
                } else {
                  final y = dayKey(_day.subtract(const Duration(days: 1)));
                  final n = await NutritionRepo.copyMeal(y, _key, meal);
                  notifyDataChanged();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(n == 0 ? 'Nothing logged for this meal yesterday' : 'Copied $n item(s) from yesterday')));
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Add food')),
                PopupMenuItem(value: 'copy', child: Text("Copy yesterday's meal")),
              ],
            ),
          ])),
      if (list.isEmpty)
        InkWell(
          onTap: () => showFoodSheet(context, day: _key, meal: meal),
          child: const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: Muted('Nothing logged · tap to add', size: 13)),
        )
      else
        IPCard(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(children: [
            for (final e in list)
              ListTile(
                title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (e.serving != null && e.serving!.isNotEmpty) e.serving!,
                  e.calories == null ? 'kcal not set' : '${e.calories!.round()} kcal',
                  if (e.protein != null) '${fmtW(e.protein)} g P',
                  if (e.checklistItemId != null) 'from checklist',
                ].join(' · ')),
                onTap: e.checklistItemId != null ? null : () => showFoodSheet(context, day: _key, meal: meal, edit: e),
                trailing: e.checklistItemId != null
                    ? null
                    : IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          await NutritionRepo.deleteEntry(e.id);
                          notifyDataChanged();
                        }),
              ),
          ]),
        ),
    ];
  }
}

double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

/// Add or edit a food entry. Values are entered by the user; nothing is guessed.
Future<void> showFoodSheet(BuildContext context, {required String day, required String meal, FoodEntry? edit}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _FoodForm(day: day, meal: meal, edit: edit),
    ),
  );
  notifyDataChanged();
}

class _FoodForm extends StatefulWidget {
  final String day, meal;
  final FoodEntry? edit;
  const _FoodForm({required this.day, required this.meal, this.edit});
  @override
  State<_FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends State<_FoodForm> {
  late String _meal = widget.edit?.meal ?? widget.meal;
  late final _name = TextEditingController(text: widget.edit?.name);
  late final _serving = TextEditingController(text: widget.edit?.serving);
  late final _cal = TextEditingController(text: widget.edit?.calories == null ? '' : fmtW(widget.edit!.calories));
  late final _p = TextEditingController(text: widget.edit?.protein == null ? '' : fmtW(widget.edit!.protein));
  late final _c = TextEditingController(text: widget.edit?.carbs == null ? '' : fmtW(widget.edit!.carbs));
  late final _f = TextEditingController(text: widget.edit?.fat == null ? '' : fmtW(widget.edit!.fat));
  List<FoodEntry> _recent = [];

  @override
  void initState() {
    super.initState();
    if (widget.edit == null) _loadRecent('');
  }

  Future<void> _loadRecent(String q) async {
    final r = await NutritionRepo.recentFoods(query: q);
    if (mounted) setState(() => _recent = r);
  }

  void _fill(FoodEntry e) {
    setState(() {
      _name.text = e.name;
      _serving.text = e.serving ?? '';
      _cal.text = e.calories == null ? '' : fmtW(e.calories);
      _p.text = e.protein == null ? '' : fmtW(e.protein);
      _c.text = e.carbs == null ? '' : fmtW(e.carbs);
      _f.text = e.fat == null ? '' : fmtW(e.fat);
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    await NutritionRepo.saveEntry(
      id: widget.edit?.id,
      day: widget.day,
      meal: _meal,
      name: _name.text,
      serving: _serving.text.trim().isEmpty ? null : _serving.text.trim(),
      calories: _num(_cal),
      protein: _num(_p),
      carbs: _num(_c),
      fat: _num(_f),
    );
    if (mounted) Navigator.pop(context);
  }

  Widget _numField(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.edit == null ? 'Log food' : 'Edit food', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in meals)
              ChoiceChip(label: Text(mealLabels[m]!), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Food name', prefixIcon: Icon(Icons.search)),
            onChanged: widget.edit == null ? (v) => _loadRecent(v.trim()) : null,
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Muted('Recent foods - tap to fill', size: 12),
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final r in _recent)
                  Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(r.name), onPressed: () => _fill(r))),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          TextField(controller: _serving, decoration: const InputDecoration(labelText: 'Serving / quantity (e.g. 2 eggs, 1 bowl)')),
          const SizedBox(height: 10),
          Row(children: [_numField(_cal, 'Calories'), const SizedBox(width: 8), _numField(_p, 'Protein g')]),
          const SizedBox(height: 10),
          Row(children: [_numField(_c, 'Carbs g'), const SizedBox(width: 8), _numField(_f, 'Fat g')]),
          const SizedBox(height: 6),
          const Muted('Use the label or a trusted source. Leave blank if unsure - IronPulse never guesses values.', size: 11.5),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(widget.edit == null ? 'Add' : 'Save')),
        ]),
      ),
    );
  }
}

Future<void> showTargetsDialog(BuildContext context) async {
  final t = await NutritionRepo.targets();
  if (!context.mounted) return;
  var enabled = t.enabled;
  final cal = TextEditingController(text: t.calories == null ? '' : fmtW(t.calories));
  final p = TextEditingController(text: t.protein == null ? '' : fmtW(t.protein));
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Nutrition targets'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show targets'),
            value: enabled,
            onChanged: (v) => setD(() => enabled = v),
          ),
          TextField(
              controller: cal,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Daily calories (kcal)')),
          const SizedBox(height: 10),
          TextField(
              controller: p,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Daily protein (g)')),
          const SizedBox(height: 10),
          const Muted('Set your own numbers, ideally with a coach or dietitian. IronPulse does not prescribe deficits.', size: 12),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await NutritionRepo.saveTargets(Targets(enabled, _num(cal), _num(p)));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

const _suggestions = [
  ('Protein powder', 'supplement'),
  ('Creatine', 'supplement'),
  ('Soya chunks', 'food'),
  ('Milk', 'food'),
  ('Eggs', 'food'),
  ('Water (3 L)', 'habit'),
];

class ChecklistManager extends StatelessWidget {
  const ChecklistManager({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily checklist')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: IP.accent,
        foregroundColor: Colors.black,
        onPressed: () => _editItem(context),
        child: const Icon(Icons.add),
      ),
      body: Reloading<(List<ChecklistItem>, Map<String, int>)>(
        load: () async => (await NutritionRepo.items(), await NutritionRepo.checklistHistory(14)),
        builder: (context, data) {
          final (items, history) = data;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
            const Muted('Track whatever helps you. Supplements are never required - talk to a professional before '
                'starting one. Adding protein or calories lets ticks count toward your nutrition totals.'),
            const SectionTitle('Suggestions'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _suggestions.where((s) => !items.any((i) => i.name == s.$1)))
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(s.$1),
                  onPressed: () => _editItem(context, name: s.$1, category: s.$2),
                ),
            ]),
            const SectionTitle('Your items'),
            if (items.isEmpty) const Muted('Nothing yet.'),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IPCard(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.name,
                            style: TextStyle(fontWeight: FontWeight.w700, color: it.active ? IP.text : IP.muted)),
                        Muted(
                            [
                              it.category,
                              if (it.quantity != null) it.quantity!,
                              if (it.protein != null) '${fmtW(it.protein)} g P',
                              if (it.calories != null) '${fmtW(it.calories)} kcal',
                              if (!it.active) 'paused',
                            ].join(' · '),
                            size: 12),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'edit') {
                          await _editItem(context, item: it);
                        } else if (a == 'pause') {
                          await NutritionRepo.setItemActive(it.id, !it.active);
                        } else if (a == 'delete') {
                          await NutritionRepo.deleteItem(it.id);
                        }
                        notifyDataChanged();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'pause', child: Text(it.active ? 'Pause tracking' : 'Resume tracking')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ]),
                ),
              ),
            const SectionTitle('Last 14 days'),
            _HistoryStrip(history: history, total: items.where((i) => i.active).length),
          ]);
        },
      ),
    );
  }

  Future<void> _editItem(BuildContext context, {ChecklistItem? item, String? name, String? category}) async {
    final n = TextEditingController(text: item?.name ?? name);
    final q = TextEditingController(text: item?.quantity);
    final p = TextEditingController(text: item?.protein == null ? '' : fmtW(item!.protein));
    final c = TextEditingController(text: item?.calories == null ? '' : fmtW(item!.calories));
    var cat = item?.category ?? category ?? 'supplement';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(item == null ? 'Add item' : 'Edit item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final k in ['supplement', 'food', 'habit'])
                  ChoiceChip(label: Text(k), selected: cat == k, onSelected: (_) => setD(() => cat = k)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: q, decoration: const InputDecoration(labelText: 'Quantity (e.g. 1 scoop, 200 ml)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: p,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Protein g'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'kcal'))),
              ]),
              const SizedBox(height: 6),
              const Muted('Optional - from the product label.', size: 11.5),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      await NutritionRepo.saveItem(
          id: item?.id, name: n.text, category: cat, quantity: q.text, protein: _num(p), calories: _num(c));
      notifyDataChanged();
    }
  }
}

class _HistoryStrip extends StatelessWidget {
  final Map<String, int> history;
  final int total;
  const _HistoryStrip({required this.history, required this.total});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))];
    return IPCard(
      child: Row(children: [
        for (final d in days)
          Expanded(
            child: Column(children: [
              Container(
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: total == 0 || (history[dayKey(d)] ?? 0) == 0
                      ? IP.surface2
                      : IP.accent.withOpacity((0.3 + 0.7 * ((history[dayKey(d)] ?? 0) / total)).clamp(0.3, 1.0)),
                ),
              ),
              const SizedBox(height: 4),
              Text('${d.day}', style: const TextStyle(fontSize: 9, color: IP.muted)),
            ]),
          ),
      ]),
    );
  }
}
