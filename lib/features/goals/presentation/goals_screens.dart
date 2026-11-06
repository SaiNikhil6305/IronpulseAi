import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_controller.dart';
import '../../notifications/data/reminder_sync.dart';
import '../../profile/domain/profile.dart';
import '../../progress/presentation/charts.dart';
import '../../workouts/domain/workout_models.dart';
import '../data/goals_repository.dart';

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final units = ref.watch(unitsProvider);
    final active = goals.where((g) => g.goal.status == 'active').toList();
    final other = goals.where((g) => g.goal.status != 'active').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Fitness goals')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.flag_outlined),
        label: const Text('New goal'),
      ),
      body: goals.isEmpty
          ? const EmptyState(
              icon: Icons.flag_outlined,
              title: 'No goals yet',
              message: 'Set a 2-, 3- or 6-month goal. Measurable goals (target weight, workout count) track progress automatically.')
          : ListView(padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, 96), children: [
              for (final g in active) _GoalCard(g: g, units: units, onTap: () => _edit(context, g.goal)),
              if (other.isNotEmpty) const SectionHeader('Completed & archived'),
              for (final g in other) _GoalCard(g: g, units: units, onTap: () => _edit(context, g.goal)),
            ]),
    );
  }

  void _edit(BuildContext context, Goal? g) =>
      showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _GoalSheet(goal: g));
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.g, required this.units, required this.onTap});
  final GoalProgress g;
  final String units;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final goal = g.goal;
    final isWeight = goal.type == 'target_weight';
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: AppCard(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(goal.title, style: Theme.of(context).textTheme.titleMedium)),
            Pill(goal.status == 'active' ? '${g.daysRemaining} days left' : goal.status,
                color: goal.status == 'completed' ? AppColors.success : AppColors.textMuted),
          ]),
          Text('${goalTypeLabels[goal.type] ?? goal.type} · ${Dates.iso(goal.startDate)} → ${Dates.iso(goal.targetDate)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          if (g.progress != null) ...[
            const SizedBox(height: Gaps.md),
            ProgressBar(value: g.progress!),
            const SizedBox(height: 4),
            Text(
              isWeight
                  ? 'Now ${Units.weight(g.current, units)} · target ${Units.weight(goal.targetValue, units)} (from ${Units.weight(goal.startValue, units)})'
                  : '${g.current?.toInt()} of ${goal.targetValue?.toInt()} workouts',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ] else if (goal.type != 'target_weight' && goal.type != 'workout_count')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Track this goal with milestones and your Progress charts.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          if (goal.milestones.isNotEmpty) ...[
            const SizedBox(height: Gaps.sm),
            for (final m in goal.milestones)
              Row(children: [
                Icon(m['done'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16, color: m['done'] == true ? AppColors.success : AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(child: Text('${m['title']}')),
              ]),
          ],
        ]),
      ),
    );
  }
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({this.goal});
  final Goal? goal;
  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  final _form = GlobalKey<FormState>();
  late String _type = widget.goal?.type ?? 'target_weight';
  late final _title = TextEditingController(text: widget.goal?.title);
  late final _notes = TextEditingController(text: widget.goal?.notes);
  late final _target = TextEditingController();
  late final _milestone = TextEditingController();
  late final DateTime _start = widget.goal?.startDate ?? Dates.dayOnly(DateTime.now());
  late DateTime _end = widget.goal?.targetDate ?? DateTime(_start.year, _start.month + 3, _start.day);
  late List<Map<String, dynamic>> _milestones = widget.goal?.milestones ?? [];
  late String _status = widget.goal?.status ?? 'active';

  @override
  void initState() {
    super.initState();
    final t = widget.goal?.targetValue;
    if (t != null) {
      _target.text = _type == 'target_weight' ? Units.trimNum(Units.fromKg(t, ref.read(unitsProvider)), maxDecimals: 1) : Units.trimNum(t);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _notes, _target, _milestone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider);
    final measurable = _type == 'target_weight' || _type == 'workout_count';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(Gaps.lg), children: [
          Text(widget.goal == null ? 'New goal' : 'Edit goal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gaps.lg),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Goal type'),
            items: [for (final e in goalTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: widget.goal != null ? null : (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: Gaps.md),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Reach 72 kg by March'),
            validator: (v) => Validators.required(v, field: 'Title') ?? Validators.maxLength(100)(v),
          ),
          if (measurable) ...[
            const SizedBox(height: Gaps.md),
            NumberField(
              controller: _target,
              label: _type == 'target_weight' ? 'Target weight' : 'Workouts to complete',
              suffix: _type == 'target_weight' ? Units.weightLabel(units) : 'workouts',
              integer: _type == 'workout_count',
              validator: Validators.number(min: 1, max: 1000, optional: false),
            ),
          ],
          const SizedBox(height: Gaps.md),
          const Text('Duration', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: Gaps.sm),
          Wrap(spacing: 8, children: [
            for (final m in [2, 3, 6])
              ChoiceChip(
                label: Text('$m months'),
                selected: _end == DateTime(_start.year, _start.month + m, _start.day),
                onSelected: (_) => setState(() => _end = DateTime(_start.year, _start.month + m, _start.day)),
              ),
            ActionChip(
              label: Text('Custom: ${Dates.iso(_end)}'),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _end, firstDate: _start.add(const Duration(days: 1)), lastDate: DateTime(_start.year + 3));
                if (d != null) setState(() => _end = d);
              },
            ),
          ]),
          const SizedBox(height: Gaps.md),
          const Text('Milestones', style: TextStyle(fontWeight: FontWeight.w700)),
          for (var i = 0; i < _milestones.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _milestones[i]['done'] == true,
              title: Text('${_milestones[i]['title']}'),
              onChanged: (v) => setState(() => _milestones = [..._milestones]..[i] = {..._milestones[i], 'done': v}),
              secondary: IconButton(
                  icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _milestones = [..._milestones]..removeAt(i))),
            ),
          Row(children: [
            Expanded(child: TextField(controller: _milestone, decoration: const InputDecoration(hintText: 'Add a milestone'))),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _milestones.length >= 20
                  ? null
                  : () {
                      if (_milestone.text.trim().isEmpty) return;
                      setState(() => _milestones = [..._milestones, {'title': _milestone.text.trim(), 'done': false}]);
                      _milestone.clear();
                    },
            ),
          ]),
          const SizedBox(height: Gaps.md),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
          if (widget.goal != null) ...[
            const SizedBox(height: Gaps.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'completed', label: Text('Completed')),
                ButtonSegment(value: 'abandoned', label: Text('Archived')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
          ],
          const SizedBox(height: Gaps.lg),
          FilledButton(onPressed: _save, child: const Text('Save goal')),
          if (widget.goal != null)
            TextButton(
              onPressed: () async {
                await ref.read(goalsRepositoryProvider).deleteGoal(widget.goal!.id);
                if (context.mounted) Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete goal'),
            ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final units = ref.read(unitsProvider);
    final raw = Validators.parseNum(_target.text);
    final target = raw == null ? null : (_type == 'target_weight' ? Units.toKg(raw, units) : raw);
    final weights = ref.read(weightsProvider);
    final startValue = widget.goal?.startValue ??
        (_type == 'target_weight' ? (weights.isNotEmpty ? weights.last.weightKg : ref.read(profileProvider)?.currentWeightKg) : null);
    final goal = Goal({
      'id': widget.goal?.id ?? newId(),
      'goal_type': _type,
      'title': _title.text.trim(),
      'start_date': Dates.iso(_start),
      'target_date': Dates.iso(_end),
      'target_value': target,
      'start_value': startValue,
      'milestones': _milestones,
      'status': _status,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    });
    await ref.read(goalsRepositoryProvider).saveGoal(goal);
    if (mounted) Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Weight
// ---------------------------------------------------------------------------
Future<void> showWeightSheet(BuildContext context, WidgetRef ref, [WeightEntry? existing]) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _WeightSheet(existing: existing));

class _WeightSheet extends ConsumerStatefulWidget {
  const _WeightSheet({this.existing});
  final WeightEntry? existing;
  @override
  ConsumerState<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends ConsumerState<_WeightSheet> {
  final _form = GlobalKey<FormState>();
  late final _w = TextEditingController(
      text: widget.existing == null ? '' : Units.trimNum(Units.fromKg(widget.existing!.weightKg, ref.read(unitsProvider)), maxDecimals: 2));
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late DateTime _day = widget.existing == null ? DateTime.now() : DateTime.parse(widget.existing!.day);

  @override
  void dispose() {
    _w.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider);
    final imperial = Units.isImperial(units);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(Gaps.lg), children: [
          Text('Record weight', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Gaps.lg),
          NumberField(
            controller: _w,
            autofocus: true,
            label: 'Body weight',
            suffix: Units.weightLabel(units),
            validator: Validators.number(min: imperial ? 55 : 25, max: imperial ? 880 : 400, optional: false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(Dates.friendly(_day)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2015), lastDate: DateTime.now());
              if (d != null) setState(() => _day = d);
            },
          ),
          TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)'), validator: Validators.maxLength(300)),
          const SizedBox(height: Gaps.lg),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              await ref.read(goalsRepositoryProvider).saveWeight(WeightEntry(
                    id: widget.existing?.id ?? newId(),
                    day: Dates.iso(_day),
                    weightKg: Units.toKg(Validators.parseNum(_w.text)!, units),
                    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  ));
              if (context.mounted) {
                Navigator.pop(context);
                showSnack(context, 'Weight saved.');
              }
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}

class WeightScreen extends ConsumerWidget {
  const WeightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weights = ref.watch(weightsProvider);
    final units = ref.watch(unitsProvider);
    final prefs = ref.watch(notificationPrefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Body weight'), actions: [
        IconButton(tooltip: 'Progress photos', icon: const Icon(Icons.photo_library_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PhotosScreen()))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: () => showWeightSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Record'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, 96), children: [
        AppCard(
          child: DateLineChart(
            points: [for (final w in weights) (DateTime.parse(w.day), Units.fromKg(w.weightKg, units))],
            unit: Units.weightLabel(units),
          ),
        ),
        const SizedBox(height: Gaps.sm),
        const Text(
          'Day-to-day weight moves with water, food and sleep. Look at the trend over several weeks — a single '
          'reading can\'t show whether you gained muscle or lost fat.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SectionHeader('Weekly weigh-in reminder'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.sm),
          child: Row(children: [
            Expanded(
              child: Text(prefs.weighInWeekday == null
                  ? 'Off'
                  : '${Dates.weekdayName(prefs.weighInWeekday!)} at ${Dates.timeLabel(prefs.weighInTime)}'),
            ),
            TextButton(onPressed: () => _pickReminder(context, ref, prefs), child: const Text('Change')),
          ]),
        ),
        const SectionHeader('Entries'),
        if (weights.isEmpty) const Text('No entries yet.', style: TextStyle(color: AppColors.textMuted)),
        for (final w in weights.reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(Units.weight(w.weightKg, units)),
            subtitle: Text([Dates.friendly(DateTime.parse(w.day)), if (w.notes != null) w.notes!].join(' · ')),
            onTap: () => showWeightSheet(context, ref, w),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(goalsRepositoryProvider).deleteWeight(w.id),
            ),
          ),
      ]),
    );
  }

  Future<void> _pickReminder(BuildContext context, WidgetRef ref, NotificationPrefs prefs) async {
    final day = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Weigh-in day', style: TextStyle(fontWeight: FontWeight.w800))),
          for (var d = 1; d <= 7; d++) ListTile(title: Text(Dates.weekdayName(d)), onTap: () => Navigator.pop(ctx, d)),
          ListTile(title: const Text('Turn off', style: TextStyle(color: AppColors.error)), onTap: () => Navigator.pop(ctx, 0)),
        ]),
      ),
    );
    if (day == null || !context.mounted) return;
    String? time;
    if (day > 0) {
      final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 30));
      if (t == null) return;
      time = Dates.hhmm(t.hour, t.minute);
    }
    final next = NotificationPrefs(
      gymRemindersEnabled: prefs.gymRemindersEnabled,
      offsets: prefs.offsets,
      checklistEnabled: prefs.checklistEnabled,
      weighInWeekday: day == 0 ? null : day,
      weighInTime: time,
    );
    await ref.read(dataWriterProvider).save(Col.meta, Meta.notificationPrefs, next.toJson(), path: '/v1/notification-preferences');
    await ref.read(reminderSyncProvider).resyncAll();
  }
}

// ---------------------------------------------------------------------------
// Progress photos (private)
// ---------------------------------------------------------------------------
const _bucket = 'progress-photos';

final photosProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final docs = [...(ref.watch(docsProvider(Col.photos)).value ?? const <Map<String, dynamic>>[])];
  docs.sort((a, b) => '${b['taken_on']}'.compareTo('${a['taken_on']}'));
  return docs;
});

Future<String> _localPhotoPath(String id) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'progress_photos'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return p.join(dir.path, '$id.jpg');
}

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});
  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  bool _showHidden = false;
  bool _busy = false;

  Future<void> _add() async {
    final view = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Which view?', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final v in ['front', 'side', 'back'])
            ListTile(title: Text('${v[0].toUpperCase()}${v.substring(1)} view'), onTap: () => Navigator.pop(ctx, v)),
        ]),
      ),
    );
    if (view == null || !mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final id = newId();
      final local = await _localPhotoPath(id);
      await File(picked.path).copy(local);
      final auth = ref.read(authControllerProvider);
      final storagePath = '${auth.userId}/$id.jpg';
      final doc = {
        'id': id,
        'storage_path': storagePath,
        'view': view,
        'taken_on': Dates.iso(DateTime.now()),
        'notes': null,
        'hidden': false,
        'uploaded': false,
      };
      await ref.read(localDbProvider).putDoc(Col.photos, id, doc);
      if (auth.canSync) await _upload(doc);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save photo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Upload only on explicit user action; the bucket is private and per-user.
  Future<void> _upload(Map<String, dynamic> doc) async {
    try {
      final bytes = await File(await _localPhotoPath(doc['id'] as String)).readAsBytes();
      await sb.Supabase.instance.client.storage.from(_bucket).uploadBinary(doc['storage_path'] as String, bytes,
          fileOptions: const sb.FileOptions(contentType: 'image/jpeg', upsert: true));
      final meta = Map<String, dynamic>.from(doc)..remove('uploaded');
      await ref.read(dataWriterProvider).save(Col.photos, doc['id'] as String, {...meta, 'uploaded': true},
          path: '/v1/photos/${doc['id']}', body: meta);
    } catch (_) {
      if (mounted) showSnack(context, 'Saved on this device. Upload failed — tap the photo to retry.', error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> doc) async {
    final ok = await confirmDialog(context,
        title: 'Delete photo?', message: 'It will be removed from this device and from your private cloud storage.', confirm: 'Delete', destructive: true);
    if (!ok) return;
    final local = File(await _localPhotoPath(doc['id'] as String));
    if (local.existsSync()) local.deleteSync();
    final auth = ref.read(authControllerProvider);
    if (auth.canSync && doc['uploaded'] == true) {
      try {
        await sb.Supabase.instance.client.storage.from(_bucket).remove([doc['storage_path'] as String]);
      } catch (_) {}
    }
    await ref.read(dataWriterProvider).remove(Col.photos, doc['id'] as String, path: auth.canSync ? '/v1/photos/${doc['id']}' : null);
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider).where((d) => _showHidden || d['hidden'] != true).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Progress photos'), actions: [
        IconButton(
          tooltip: _showHidden ? 'Hide hidden photos' : 'Show hidden photos',
          icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _showHidden = !_showHidden),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: _busy ? null : _add,
        child: _busy ? const CircularProgressIndicator(color: Colors.black) : const Icon(Icons.add_a_photo_outlined),
      ),
      body: photos.isEmpty
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'Private progress photos',
              message: 'Photos stay private: stored on this device and, when signed in, in your own private cloud folder. '
                  'Nothing is uploaded unless you add a photo.')
          : GridView.builder(
              padding: const EdgeInsets.all(Gaps.md),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.75),
              itemCount: photos.length,
              itemBuilder: (_, i) => _PhotoTile(
                doc: photos[i],
                onDelete: () => _delete(photos[i]),
                onRetry: () => _upload(photos[i]),
                onToggleHidden: () => ref.read(dataWriterProvider).save(
                    Col.photos, photos[i]['id'] as String, {...photos[i], 'hidden': photos[i]['hidden'] != true},
                    path: photos[i]['uploaded'] == true && ref.read(authControllerProvider).canSync ? '/v1/photos/${photos[i]['id']}' : null,
                    body: (Map<String, dynamic>.from(photos[i])..remove('uploaded'))..['hidden'] = photos[i]['hidden'] != true),
              ),
            ),
    );
  }
}

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({required this.doc, required this.onDelete, required this.onRetry, required this.onToggleHidden});
  final Map<String, dynamic> doc;
  final VoidCallback onDelete, onRetry, onToggleHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: _localPhotoPath(doc['id'] as String),
      builder: (context, snap) {
        Widget image;
        final local = snap.data == null ? null : File(snap.data!);
        if (local != null && local.existsSync()) {
          image = Image.file(local, fit: BoxFit.cover);
        } else if (ref.read(authControllerProvider).canSync && doc['uploaded'] != false) {
          image = FutureBuilder<String>(
            future: sb.Supabase.instance.client.storage.from(_bucket).createSignedUrl(doc['storage_path'] as String, 3600),
            builder: (_, s) => s.hasData
                ? CachedNetworkImage(imageUrl: s.data!, fit: BoxFit.cover, cacheKey: doc['id'] as String)
                : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else {
          image = const Center(child: Icon(Icons.broken_image_outlined));
        }
        return GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(title: Text('${doc['view']} · ${doc['taken_on']}')),
                if (doc['uploaded'] == false && ref.read(authControllerProvider).canSync)
                  ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: const Text('Upload to private cloud'), onTap: () {
                    Navigator.pop(ctx);
                    onRetry();
                  }),
                ListTile(
                    leading: Icon(doc['hidden'] == true ? Icons.visibility : Icons.visibility_off_outlined),
                    title: Text(doc['hidden'] == true ? 'Unhide' : 'Hide from gallery'),
                    onTap: () {
                      Navigator.pop(ctx);
                      onToggleHidden();
                    }),
                ListTile(
                    leading: const Icon(Icons.delete_outline, color: AppColors.error),
                    title: const Text('Delete', style: TextStyle(color: AppColors.error)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onDelete();
                    }),
              ]),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              image,
              Positioned(left: 6, bottom: 6, child: Pill('${doc['view']}', color: AppColors.text)),
              if (doc['hidden'] == true) Container(color: Colors.black54, child: const Icon(Icons.visibility_off)),
            ]),
          ),
        );
      },
    );
  }
}
