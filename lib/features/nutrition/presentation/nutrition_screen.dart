import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../workouts/domain/workout_models.dart';
import '../data/food_search.dart';
import '../data/nutrition_repository.dart';

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});
  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  DateTime _day = Dates.dayOnly(DateTime.now());

  String get _iso => Dates.iso(_day);

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(mealsForDayProvider(_iso));
    final totals = NutritionTotals.of(meals);
    final targets = ref.watch(nutritionTargetsProvider);
    final history = nutritionHistory(ref.watch(allMealsProvider), 7, DateTime.now());
    final custom = meals.map((m) => m.category).where((c) => !mealCategories.contains(c)).toSet();
    final isToday = _day == Dates.dayOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition'), actions: [
        IconButton(tooltip: 'Targets', icon: const Icon(Icons.tune), onPressed: () => _editTargets(targets)),
      ]),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        Row(children: [
          IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1)))),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setState(() => _day = d);
              },
              child: Text(Dates.friendly(_day), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: isToday ? null : () => setState(() => _day = _day.add(const Duration(days: 1)))),
        ]),
        _TotalsCard(totals: totals, targets: targets),
        if (history.isNotEmpty) ...[
          const SizedBox(height: Gaps.md),
          AppCard(
            padding: const EdgeInsets.all(Gaps.md),
            child: Builder(builder: (_) {
              final n = history.length;
              final avgP = history.fold<double>(0, (a, d) => a + d.totals.protein) / n;
              final avgC = history.fold<double>(0, (a, d) => a + d.totals.calories) / n;
              return Text(
                '7-day average over $n logged day${n == 1 ? '' : 's'}: ${avgP.round()} g protein · ${avgC.round()} kcal',
                style: const TextStyle(color: AppColors.textMuted),
              );
            }),
          ),
        ],
        for (final c in [...mealCategories, ...custom]) _MealSection(day: _iso, category: c, meal: meals.where((m) => m.category == c).firstOrNull),
        const SizedBox(height: Gaps.md),
        OutlinedButton.icon(
          onPressed: () async {
            final c = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Custom meal category'),
                content: TextField(controller: c, autofocus: true, maxLength: 30, decoration: const InputDecoration(hintText: 'e.g. Pre-workout')),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add food'))],
              ),
            );
            if (name != null && name.isNotEmpty && context.mounted) {
              await showAddFoodSheet(context, _iso, name.toLowerCase());
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Custom category'),
        ),
        const SizedBox(height: Gaps.lg),
        const Text(
          'Values come from what you enter or from Open Food Facts (crowd-sourced). Items marked ≈ are estimates. '
          'IronPulse never sets calorie targets automatically.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ]),
    );
  }

  Future<void> _editTargets(NutritionTargets t) async {
    final p = TextEditingController(text: t.proteinG == null ? '' : Units.trimNum(t.proteinG!));
    final k = TextEditingController(text: t.calories == null ? '' : Units.trimNum(t.calories!));
    final cb = TextEditingController(text: t.carbsG == null ? '' : Units.trimNum(t.carbsG!));
    final f = TextEditingController(text: t.fatG == null ? '' : Units.trimNum(t.fatG!));
    var enabled = t.enabled;
    final form = GlobalKey<FormState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Form(
            key: form,
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(Gaps.lg), children: [
              Text('Daily targets', style: Theme.of(ctx).textTheme.titleLarge),
              const Text('Use numbers from your own plan, coach or dietitian.', style: TextStyle(color: AppColors.textMuted)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show progress toward targets'),
                value: enabled,
                onChanged: (v) => set(() => enabled = v),
              ),
              NumberField(controller: p, label: 'Protein', suffix: 'g', validator: Validators.number(min: 0, max: 600)),
              const SizedBox(height: Gaps.md),
              NumberField(controller: k, label: 'Calories', suffix: 'kcal', validator: Validators.number(min: 0, max: 10000)),
              const SizedBox(height: Gaps.md),
              Row(children: [
                Expanded(child: NumberField(controller: cb, label: 'Carbs', suffix: 'g', validator: Validators.number(min: 0, max: 1500))),
                const SizedBox(width: Gaps.md),
                Expanded(child: NumberField(controller: f, label: 'Fat', suffix: 'g', validator: Validators.number(min: 0, max: 600))),
              ]),
              const SizedBox(height: Gaps.lg),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  await ref.read(nutritionRepositoryProvider).saveTargets(NutritionTargets(
                        enabled: enabled,
                        proteinG: Validators.parseNum(p.text),
                        calories: Validators.parseNum(k.text),
                        carbsG: Validators.parseNum(cb.text),
                        fatG: Validators.parseNum(f.text),
                      ));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save targets'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.targets});
  final NutritionTotals totals;
  final NutritionTargets targets;

  @override
  Widget build(BuildContext context) {
    Widget macro(String label, double v, double? target, String unit) {
      final show = targets.enabled && target != null && target > 0;
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${v.round()}${show ? '/${target.round()}' : ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(unit, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          if (show) ...[const SizedBox(height: 4), ProgressBar(value: v / target, height: 5)],
        ]),
      );
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          macro('CALORIES${totals.estimates ? ' ≈' : ''}', totals.calories, targets.calories, 'kcal'),
          const SizedBox(width: Gaps.md),
          macro('PROTEIN', totals.protein, targets.proteinG, 'g'),
          const SizedBox(width: Gaps.md),
          macro('CARBS', totals.carbs, targets.carbsG, 'g'),
          const SizedBox(width: Gaps.md),
          macro('FAT', totals.fat, targets.fatG, 'g'),
        ]),
        const SizedBox(height: Gaps.sm),
        Text(
          '${totals.mealsLogged} meal${totals.mealsLogged == 1 ? '' : 's'} logged'
          '${totals.missing > 0 ? ' · ${totals.missing} item(s) have no values and aren\'t counted' : ''}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ]),
    );
  }
}

class _MealSection extends ConsumerWidget {
  const _MealSection({required this.day, required this.category, required this.meal});
  final String day;
  final String category;
  final Meal? meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(nutritionRepositoryProvider);
    final label = mealCategoryLabels[category] ?? (category[0].toUpperCase() + category.substring(1));
    final t = meal == null ? null : NutritionTotals.of([meal!]);
    final yesterday = Dates.iso(DateTime.parse(day).subtract(const Duration(days: 1)));
    final prevMeal = ref.watch(mealsForDayProvider(yesterday)).where((m) => m.category == category).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.lg),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.sm, Gaps.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(width: 8),
            if (t != null) Text('${t.calories.round()} kcal · ${t.protein.round()} g P', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'copy' && prevMeal != null) await repo.duplicateInto(prevMeal, day, category);
                if (v == 'save' && meal != null && context.mounted) {
                  final c = TextEditingController(text: label);
                  final name = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Save as meal'),
                      content: TextField(controller: c, autofocus: true, maxLength: 80),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))],
                    ),
                  );
                  if (name != null && name.isNotEmpty) {
                    await repo.saveAsTemplate(meal!, name);
                    if (context.mounted) showSnack(context, 'Saved "$name" to your meals.');
                  }
                }
              },
              itemBuilder: (_) => [
                if (prevMeal != null && category != 'checklist') PopupMenuItem(value: 'copy', child: Text('Copy yesterday\'s $label')),
                if (meal != null && meal!.entries.isNotEmpty) const PopupMenuItem(value: 'save', child: Text('Save as meal')),
              ],
            ),
          ]),
          if (meal != null)
            for (final e in meal!.entries)
              Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), color: AppColors.error.withValues(alpha: 0.3), child: const Icon(Icons.delete_outline)),
                onDismissed: (_) async {
                  await repo.removeEntry(meal!, e.id);
                  if (context.mounted) {
                    showSnack(context, 'Removed ${e.foodName}',
                        action: SnackBarAction(label: 'UNDO', onPressed: () => repo.addEntry(day, category, e)));
                  }
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${e.isEstimate ? '≈ ' : ''}${e.foodName}'),
                  subtitle: Text([
                    '${Units.trimNum(e.quantity)} × ${e.servingSize ?? 'serving'}',
                    if (e.hasMissingValues) 'no values' else '${e.totalCalories.round()} kcal · ${Units.trimNum(e.totalProtein, maxDecimals: 1)} g P',
                  ].join(' · ')),
                  onTap: category == 'checklist' ? null : () => showFoodForm(context, day, category, existing: e, meal: meal),
                ),
              ),
          if (category != 'checklist')
            TextButton.icon(onPressed: () => showAddFoodSheet(context, day, category), icon: const Icon(Icons.add), label: const Text('Add food')),
        ]),
      ),
    );
  }
}

Future<void> showAddFoodSheet(BuildContext context, String day, String category) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _AddFoodSheet(day: day, category: category, scroll: scroll),
      ),
    );

class _AddFoodSheet extends ConsumerStatefulWidget {
  const _AddFoodSheet({required this.day, required this.category, required this.scroll});
  final String day;
  final String category;
  final ScrollController scroll;
  @override
  ConsumerState<_AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends ConsumerState<_AddFoodSheet> {
  String _q = '';
  Timer? _debounce;
  List<FoodSearchResult> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String v) {
    setState(() => _q = v);
    _debounce?.cancel();
    if (v.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() {
        _searching = true;
        _error = null;
      });
      try {
        final r = await ref.read(foodSearchProvider).search(v);
        if (mounted && _q == v) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _error = 'Online food search unavailable. Use your recent foods or enter values manually.');
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentFoodsProvider).where((e) => _q.isEmpty || e.foodName.toLowerCase().contains(_q.toLowerCase())).toList();
    final saved = ref.watch(savedMealsProvider).where((m) => _q.isEmpty || (m.name ?? '').toLowerCase().contains(_q.toLowerCase())).toList();
    final repo = ref.read(nutritionRepositoryProvider);
    final label = mealCategoryLabels[widget.category] ?? widget.category;

    Future<void> addQuick(FoodEntry e) async {
      await repo.addEntry(widget.day, widget.category, e.copyWith(id: newId()));
      if (context.mounted) {
        Navigator.pop(context);
        showSnack(context, 'Added ${e.foodName} to $label');
      }
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg), children: [
      Text('Add to $label', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: Gaps.md),
      TextField(
        autofocus: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search foods'),
        onChanged: _onQuery,
      ),
      const SizedBox(height: Gaps.sm),
      FilledButton.tonalIcon(
        onPressed: () async {
          Navigator.pop(context);
          await showFoodForm(context, widget.day, widget.category, initialName: _q);
        },
        icon: const Icon(Icons.edit_note),
        label: const Text('Quick add — enter values'),
      ),
      if (saved.isNotEmpty) ...[
        const SectionHeader('Saved meals'),
        for (final m in saved)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bookmark_outline),
            title: Text(m.name ?? 'Meal'),
            subtitle: Text('${m.entries.length} items · ${NutritionTotals.of([m]).calories.round()} kcal'),
            trailing: const Icon(Icons.add_circle_outline, color: AppColors.accent),
            onTap: () async {
              await repo.duplicateInto(m, widget.day, widget.category);
              if (context.mounted) Navigator.pop(context);
            },
          ),
      ],
      if (recents.isNotEmpty) ...[
        const SectionHeader('Recent foods'),
        for (final e in recents.take(15))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${e.isEstimate ? '≈ ' : ''}${e.foodName}'),
            subtitle: Text('${Units.trimNum(e.quantity)} × ${e.servingSize ?? 'serving'} · ${e.totalCalories.round()} kcal · ${e.totalProtein.round()} g P'),
            trailing: const Icon(Icons.add_circle_outline, color: AppColors.accent),
            onTap: () => addQuick(e),
          ),
      ],
      if (_q.trim().length >= 3) ...[
        const SectionHeader('Open Food Facts', subtitle: 'Crowd-sourced values per 100 g — check against the label'),
        if (_searching) const Padding(padding: EdgeInsets.all(Gaps.lg), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.warning)),
        if (!_searching && _error == null && _results.isEmpty) const Text('No results.', style: TextStyle(color: AppColors.textMuted)),
        for (final r in _results)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r.name),
            subtitle: Text([
              if (r.brand != null && r.brand!.isNotEmpty) r.brand!,
              'per 100 g: ${r.kcal100?.round() ?? '?'} kcal · ${r.protein100 == null ? '?' : Units.trimNum(r.protein100!, maxDecimals: 1)} g P',
            ].join(' · ')),
            onTap: () async {
              Navigator.pop(context);
              await showFoodForm(context, widget.day, widget.category,
                  prefill: FoodEntry(
                    id: newId(),
                    foodName: r.brand == null ? r.name : '${r.name} (${r.brand})',
                    servingSize: '100 g',
                    calories: r.kcal100,
                    proteinG: r.protein100,
                    carbsG: r.carbs100,
                    fatG: r.fat100,
                    isEstimate: true,
                    notes: 'Source: Open Food Facts',
                  ));
            },
          ),
        const Padding(
          padding: EdgeInsets.only(top: Gaps.sm),
          child: Text('Food data © Open Food Facts contributors, ODbL.', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ),
      ],
    ]);
  }
}

Future<void> showFoodForm(BuildContext context, String day, String category,
        {FoodEntry? existing, Meal? meal, FoodEntry? prefill, String initialName = ''}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FoodForm(day: day, category: category, existing: existing, meal: meal, prefill: prefill, initialName: initialName),
    );

class _FoodForm extends ConsumerStatefulWidget {
  const _FoodForm({required this.day, required this.category, this.existing, this.meal, this.prefill, this.initialName = ''});
  final String day, category;
  final FoodEntry? existing;
  final Meal? meal;
  final FoodEntry? prefill;
  final String initialName;
  @override
  ConsumerState<_FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends ConsumerState<_FoodForm> {
  final _form = GlobalKey<FormState>();
  late final FoodEntry? _src = widget.existing ?? widget.prefill;
  late final _name = TextEditingController(text: _src?.foodName ?? widget.initialName);
  late final _serving = TextEditingController(text: _src?.servingSize);
  late final _qty = TextEditingController(text: Units.trimNum(_src?.quantity ?? 1));
  late final _kcal = TextEditingController(text: _fmt(_src?.calories));
  late final _p = TextEditingController(text: _fmt(_src?.proteinG));
  late final _c = TextEditingController(text: _fmt(_src?.carbsG));
  late final _f = TextEditingController(text: _fmt(_src?.fatG));
  late final _notes = TextEditingController(text: _src?.notes);
  late bool _estimate = _src?.isEstimate ?? false;

  static String _fmt(double? v) => v == null ? '' : Units.trimNum(v, maxDecimals: 1);

  @override
  void dispose() {
    for (final c in [_name, _serving, _qty, _kcal, _p, _c, _f, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(Gaps.lg), children: [
          Text(widget.existing == null ? 'Add food' : 'Edit food', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gaps.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Food name'),
            validator: (v) => Validators.required(v, field: 'Food name') ?? Validators.maxLength(120)(v),
          ),
          const SizedBox(height: Gaps.md),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextFormField(controller: _serving, decoration: const InputDecoration(labelText: 'Serving', hintText: 'e.g. 1 cup, 100 g'), validator: Validators.maxLength(40)),
            ),
            const SizedBox(width: Gaps.md),
            Expanded(flex: 2, child: NumberField(controller: _qty, label: 'Servings', validator: Validators.number(min: 0.01, max: 100, optional: false))),
          ]),
          const SizedBox(height: Gaps.md),
          const Text('Per serving (leave blank if unknown — blanks are not counted)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: Gaps.sm),
          Row(children: [
            Expanded(child: NumberField(controller: _kcal, label: 'kcal', validator: Validators.number(min: 0, max: 10000))),
            const SizedBox(width: Gaps.sm),
            Expanded(child: NumberField(controller: _p, label: 'Protein g', validator: Validators.number(min: 0, max: 1000))),
          ]),
          const SizedBox(height: Gaps.sm),
          Row(children: [
            Expanded(child: NumberField(controller: _c, label: 'Carbs g', validator: Validators.number(min: 0, max: 2000))),
            const SizedBox(width: Gaps.sm),
            Expanded(child: NumberField(controller: _f, label: 'Fat g', validator: Validators.number(min: 0, max: 1000))),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('These values are an estimate'),
            value: _estimate,
            onChanged: (v) => setState(() => _estimate = v),
          ),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)'), validator: Validators.maxLength(500)),
          const SizedBox(height: Gaps.lg),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final entry = FoodEntry(
                id: widget.existing?.id ?? newId(),
                foodName: _name.text.trim(),
                servingSize: _serving.text.trim().isEmpty ? null : _serving.text.trim(),
                quantity: Validators.parseNum(_qty.text) ?? 1,
                calories: Validators.parseNum(_kcal.text),
                proteinG: Validators.parseNum(_p.text),
                carbsG: Validators.parseNum(_c.text),
                fatG: Validators.parseNum(_f.text),
                isEstimate: _estimate,
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              );
              final repo = ref.read(nutritionRepositoryProvider);
              if (widget.existing != null && widget.meal != null) {
                await repo.updateEntry(widget.meal!, entry);
              } else {
                await repo.addEntry(widget.day, widget.category, entry);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(widget.existing == null ? 'Add' : 'Save'),
          ),
          if (widget.existing != null && widget.meal != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () async {
                await ref.read(nutritionRepositoryProvider).removeEntry(widget.meal!, widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Delete'),
            ),
        ]),
      ),
    );
  }
}

