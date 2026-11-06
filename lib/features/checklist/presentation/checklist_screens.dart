import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../notifications/data/reminder_sync.dart';
import '../../workouts/domain/workout_models.dart';
import '../data/checklist_repository.dart';

const _categoryIcons = {'food': Icons.egg_alt_outlined, 'supplement': Icons.medication_outlined, 'habit': Icons.repeat};

class ChecklistCard extends ConsumerWidget {
  const ChecklistCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(activeChecklistItemsProvider);
    final day = Dates.iso(DateTime.now());
    final done = ref.watch(completedItemIdsProvider(day));
    if (items.isEmpty) {
      return AppCard(
        onTap: () => context.push('/checklist'),
        child: const Row(children: [
          Icon(Icons.playlist_add_check, color: AppColors.accent),
          SizedBox(width: 12),
          Expanded(child: Text('Build a daily checklist for foods, supplements or habits you want to track.')),
        ]),
      );
    }
    final count = items.where((i) => done.contains(i.id)).length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.sm, Gaps.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$count of ${items.length} done', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: Gaps.md),
          Expanded(child: ProgressBar(value: items.isEmpty ? 0 : count / items.length, height: 6)),
          const SizedBox(width: Gaps.md),
        ]),
        for (final item in items)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: done.contains(item.id),
            secondary: Icon(_categoryIcons[item.category], size: 20),
            title: Text(item.name),
            subtitle: item.quantity == null ? null : Text(item.quantity!),
            onChanged: (v) => _toggle(context, ref, item, day, v ?? false),
          ),
      ]),
    );
  }

  static Future<void> _toggle(BuildContext context, WidgetRef ref, ChecklistItem item, String day, bool value) async {
    final repo = ref.read(checklistRepositoryProvider);
    await repo.setCompleted(item, day, value);
    if (!context.mounted) return;
    showSnack(context, value ? '${item.name} checked' : '${item.name} unchecked',
        action: SnackBarAction(label: 'UNDO', onPressed: () => repo.setCompleted(item, day, !value)));
  }
}

class ChecklistManageScreen extends ConsumerWidget {
  const ChecklistManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(checklistItemsProvider);
    final completions = ref.watch(checklistCompletionsProvider);
    final hist = ChecklistRepository.history(completions, 14);
    final existing = {for (final i in items) i.name.toLowerCase()};
    final suggestions = checklistSuggestions.where((s) => !existing.contains(s.$1.toLowerCase())).toList();
    final repo = ref.read(checklistRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily checklist')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        tooltip: 'Add item',
        onPressed: () => _edit(context, ref, null, items.length),
        child: const Icon(Icons.add),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, 96), children: [
        const Text(
          'Track foods, supplements and habits you choose. Nothing here is required — supplements are optional, '
          'and IronPulse doesn\'t recommend doses. Ask a doctor or dietitian for personal advice.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        if (suggestions.isNotEmpty) ...[
          const SectionHeader('Suggestions'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in suggestions)
              ActionChip(
                avatar: Icon(_categoryIcons[s.$2], size: 16),
                label: Text(s.$1),
                onPressed: () => repo.saveItem(ChecklistItem(id: newId(), name: s.$1, category: s.$2, position: items.length)),
              ),
          ]),
        ],
        const SectionHeader('Your items'),
        if (items.isEmpty) const Text('No items yet.', style: TextStyle(color: AppColors.textMuted)),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final list = [...items];
            final it = list.removeAt(a);
            list.insert(b, it);
            repo.reorder(list);
          },
          children: [
            for (var i = 0; i < items.length; i++)
              ListTile(
                key: ValueKey(items[i].id),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                title: Text(items[i].name, style: TextStyle(color: items[i].paused ? AppColors.textMuted : null)),
                subtitle: Text([
                  _cap(items[i].category),
                  if (items[i].quantity != null) items[i].quantity!,
                  if (items[i].proteinG != null) '${Units.trimNum(items[i].proteinG!)} g protein',
                  if (items[i].reminderTime != null) '⏰ ${Dates.timeLabel(items[i].reminderTime)}',
                  if (items[i].paused) 'paused',
                ].join(' · ')),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') await _edit(context, ref, items[i], i);
                    if (v == 'pause') await repo.saveItem(items[i].copyWith(paused: !items[i].paused));
                    if (v == 'delete' && context.mounted) {
                      final ok = await confirmDialog(context,
                          title: 'Delete ${items[i].name}?',
                          message: 'Past completions stay in your history.',
                          confirm: 'Delete',
                          destructive: true);
                      if (ok) await repo.deleteItem(items[i].id);
                    }
                    await ref.read(reminderSyncProvider).resyncAll();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'pause', child: Text(items[i].paused ? 'Resume tracking' : 'Pause tracking')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
          ],
        ),
        const SectionHeader('Last 14 days'),
        if (hist.isEmpty)
          const Text('No completions yet.', style: TextStyle(color: AppColors.textMuted))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var d = 13; d >= 0; d--)
              () {
                final day = Dates.iso(DateTime.now().subtract(Duration(days: d)));
                final n = hist[day] ?? 0;
                return Tooltip(
                  message: '$day: $n completed',
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: n == 0 ? AppColors.surfaceHigh : AppColors.accent.withValues(alpha: (0.25 + n * 0.15).clamp(0, 1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: n == 0 ? AppColors.textMuted : Colors.black)),
                  ),
                );
              }(),
          ]),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ChecklistItem? item, int position) async {
    final saved = await showModalBottomSheet<bool>(
        context: context, isScrollControlled: true, builder: (_) => _ItemSheet(item: item, position: position));
    if (saved == true) await ref.read(reminderSyncProvider).resyncAll();
  }
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({this.item, required this.position});
  final ChecklistItem? item;
  final int position;
  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _qty = TextEditingController(text: widget.item?.quantity);
  late final _protein = TextEditingController(text: widget.item?.proteinG == null ? '' : Units.trimNum(widget.item!.proteinG!));
  late final _kcal = TextEditingController(text: widget.item?.calories == null ? '' : Units.trimNum(widget.item!.calories!));
  late String _category = widget.item?.category ?? 'food';
  late String? _reminder = widget.item?.reminderTime;

  @override
  void dispose() {
    for (final c in [_name, _qty, _protein, _kcal]) {
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
          Text(widget.item == null ? 'New checklist item' : 'Edit item', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gaps.lg),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => Validators.required(v, field: 'Name') ?? Validators.maxLength(60)(v),
          ),
          const SizedBox(height: Gaps.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'food', label: Text('Food')),
              ButtonSegment(value: 'supplement', label: Text('Supplement')),
              ButtonSegment(value: 'habit', label: Text('Habit')),
            ],
            selected: {_category},
            onSelectionChanged: (s) => setState(() => _category = s.first),
          ),
          const SizedBox(height: Gaps.md),
          TextFormField(
            controller: _qty,
            decoration: const InputDecoration(labelText: 'Quantity (optional)', hintText: 'e.g. 1 scoop, 2 eggs, 250 ml'),
            validator: Validators.maxLength(40),
          ),
          if (_category != 'habit') ...[
            const SizedBox(height: Gaps.md),
            const Text('Nutrition per completion (optional). Only filled values are added to your nutrition log.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: Gaps.sm),
            Row(children: [
              Expanded(child: NumberField(controller: _protein, label: 'Protein', suffix: 'g', validator: Validators.number(min: 0, max: 300))),
              const SizedBox(width: Gaps.md),
              Expanded(child: NumberField(controller: _kcal, label: 'Calories', suffix: 'kcal', validator: Validators.number(min: 0, max: 5000))),
            ]),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Daily reminder'),
            subtitle: Text(_reminder == null ? 'Off' : Dates.timeLabel(_reminder)),
            trailing: _reminder == null ? const Icon(Icons.add_alarm) : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _reminder = null)),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
              if (t != null) setState(() => _reminder = Dates.hhmm(t.hour, t.minute));
            },
          ),
          const SizedBox(height: Gaps.md),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final item = ChecklistItem(
                id: widget.item?.id ?? newId(),
                name: _name.text.trim(),
                category: _category,
                quantity: _qty.text.trim().isEmpty ? null : _qty.text.trim(),
                proteinG: _category == 'habit' ? null : Validators.parseNum(_protein.text),
                calories: _category == 'habit' ? null : Validators.parseNum(_kcal.text),
                reminderTime: _reminder,
                paused: widget.item?.paused ?? false,
                position: widget.item?.position ?? widget.position,
              );
              await ref.read(checklistRepositoryProvider).saveItem(item);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
          if (_reminder != null)
            const Padding(
              padding: EdgeInsets.only(top: Gaps.sm),
              child: Text('Turn on checklist reminders in Settings › Reminders for these to fire.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
