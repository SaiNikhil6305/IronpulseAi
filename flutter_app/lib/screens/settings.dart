import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/account_repo.dart';
import '../data/health_repo.dart';
import '../data/notifications.dart';
import '../data/repo.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ai.dart';
import 'legal.dart';
import 'nutrition.dart';
import 'onboarding.dart';
import 'schedule.dart';
import 'split_picker.dart';
import 'wearables.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _go(BuildContext context, Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Widget _tile(BuildContext c, IconData i, String t, VoidCallback onTap, {String? sub, Color? color}) => ListTile(
        leading: Icon(i, color: color ?? IP.muted),
        title: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: sub == null ? null : Text(sub),
        trailing: const Icon(Icons.chevron_right, color: IP.muted),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        const SectionTitle('You'),
        IPCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            _tile(context, Icons.person_outline, 'Edit profile', () => _go(context, const EditProfileScreen()),
                sub: 'Name, body, goal, weekly target, rest timer'),
            _tile(context, Icons.view_week_outlined, 'Workout split', () => _go(context, const SplitPickerScreen())),
            _tile(context, Icons.notifications_none, 'Gym schedule & reminders', () => _go(context, const ScheduleScreen())),
            _tile(context, Icons.restaurant_outlined, 'Nutrition targets', () => showTargetsDialog(context)),
            _tile(context, Icons.checklist, 'Daily checklist', () => _go(context, const ChecklistManager())),
            _tile(context, Icons.watch_outlined, 'Wearables', () => _go(context, const WearablesScreen())),
            _tile(context, Icons.auto_awesome_outlined, 'IronPulse AI', () => _go(context, const AiSettingsScreen())),
          ]),
        ),
        const SectionTitle('Privacy'),
        IPCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            _tile(context, Icons.privacy_tip_outlined, 'Privacy policy',
                () => _go(context, const LegalScreen(title: 'Privacy policy', body: privacyPolicy))),
            _tile(context, Icons.description_outlined, 'Terms of use',
                () => _go(context, const LegalScreen(title: 'Terms of use', body: termsOfUse))),
            _tile(context, Icons.verified_user_outlined, 'Your privacy choices',
                () => _go(context, const ConsentHistoryScreen()), sub: 'When you turned optional features on or off'),
            _tile(context, Icons.download_outlined, 'Export my data', () => _export(context),
                sub: 'JSON (everything) + CSV for workouts, food and weight'),
            _tile(context, Icons.code, 'Open-source licenses',
                () => showLicensePage(context: context, applicationName: 'IronPulse', applicationVersion: '0.1.0')),
          ]),
        ),
        const SectionTitle('Danger zone'),
        IPCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _tile(context, Icons.delete_forever_outlined, 'Delete all my data', () => _deleteAll(context),
              sub: 'Erases everything IronPulse stores on this phone', color: IP.error),
        ),
        const SizedBox(height: 16),
        const Center(child: Muted('IronPulse 0.1.0 · Train Smart. Track Every Rep. Become Stronger.', size: 11.5)),
      ]),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final paths = await AccountRepo.writeExportFiles();
      await SharePlus.instance.share(ShareParams(
        files: paths.map(XFile.new).toList(),
        subject: 'IronPulse data export',
        text: 'My IronPulse data export. Contains personal health and fitness data - store it safely.',
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _deleteAll(BuildContext context) async {
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Delete all data?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This permanently erases workouts, nutrition, weight, goals, AI chats, imported health data, '
                'reminders and saved tokens from this phone. It cannot be undone.\n\n'
                'Tip: use "Export my data" first if you want a copy.'),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
              onChanged: (_) => setD(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: IP.error, foregroundColor: Colors.white),
              onPressed: confirm.text.trim() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Notifs.cancelAll();
    } catch (_) {}
    if ((await HealthRepo.state()).enabled) await HealthRepo.revokeOnly();
    await AccountRepo.deleteAllLocalData();
    notifyDataChanged();
    navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()), (_) => false);
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  String? _experience, _goal;
  int _target = 3, _rest = 90;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Repo.profile().then((p) {
      if (p == null || !mounted) return;
      setState(() {
        _name.text = p['name'] as String;
        _weight.text = p['weight_kg'] == null ? '' : fmtW((p['weight_kg'] as num).toDouble());
        _height.text = p['height_cm'] == null ? '' : fmtW((p['height_cm'] as num).toDouble());
        _experience = experienceLevels.contains(p['experience']) ? p['experience'] as String : null;
        _goal = goals.contains(p['goal']) ? p['goal'] as String : null;
        _target = p['weekly_target'] as int;
        _rest = p['rest_seconds'] as int;
        _loaded = true;
      });
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    await Repo.updateProfile({
      'name': _name.text.trim(),
      'weight_kg': double.tryParse(_weight.text.replaceAll(',', '.')),
      'height_cm': double.tryParse(_height.text.replaceAll(',', '.')),
      'experience': _experience,
      'goal': _goal,
      'weekly_target': _target,
      'rest_seconds': _rest,
    });
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Display name')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Weight kg (optional)'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _height,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Height cm (optional)'))),
              ]),
              const SectionTitle('Experience'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in experienceLevels)
                  ChoiceChip(label: Text(e), selected: _experience == e, onSelected: (_) => setState(() => _experience = e)),
              ]),
              const SectionTitle('Main goal'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in goals) ChoiceChip(label: Text(g), selected: _goal == g, onSelected: (_) => setState(() => _goal = g)),
              ]),
              const SectionTitle('Workouts per week'),
              Wrap(spacing: 8, children: [
                for (var n = 1; n <= 7; n++)
                  ChoiceChip(label: Text('$n'), selected: _target == n, onSelected: (_) => setState(() => _target = n)),
              ]),
              const SectionTitle('Default rest timer'),
              Wrap(spacing: 8, children: [
                for (final s in [60, 90, 120, 180, 240])
                  ChoiceChip(
                      label: Text(s < 120 ? '${s}s' : '${s ~/ 60} min'),
                      selected: _rest == s,
                      onSelected: (_) => setState(() => _rest = s)),
              ]),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ]),
    );
  }
}
