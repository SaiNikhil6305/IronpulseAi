import 'package:flutter/material.dart';

import '../data/notifications.dart';
import '../data/repo.dart';
import '../logic/schedule.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Map<int, int?>? _schedule;
  bool _enabled = false;
  Set<int> _offsets = {20};
  bool? _permitted;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ScheduleRepo.schedule();
    final (en, offs) = await ScheduleRepo.reminderPrefs();
    bool? perm;
    try {
      perm = await Notifs.permitted();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _schedule = s;
      _enabled = en;
      _offsets = offs.toSet();
      _permitted = perm;
    });
  }

  Future<void> _pickTime(int day) async {
    final cur = _schedule![day] ?? 18 * 60;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t != null) setState(() => _schedule![day] = t.hour * 60 + t.minute);
  }

  Future<void> _toggleReminders(bool on) async {
    if (on) {
      final ok = await Notifs.requestPermission();
      if (!ok && mounted) {
        setState(() => _permitted = false);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Notifications are blocked'),
            content: const Text('IronPulse needs notification permission to remind you. You can allow it in '
                'Settings → Apps → IronPulse → Notifications, then turn reminders on again. '
                'Your schedule is still saved and shown on the Home screen.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }
      _permitted = true;
    }
    setState(() => _enabled = on);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ScheduleRepo.saveSchedule(_schedule!);
    await ScheduleRepo.saveReminderPrefs(_enabled, _offsets.toList()..sort((a, b) => b.compareTo(a)));
    var n = 0;
    String? error;
    try {
      n = await Notifs.reschedule();
    } catch (e) {
      error = '$e';
    }
    notifyDataChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error != null
          ? 'Schedule saved, but reminders could not be set: $error'
          : (_enabled ? 'Schedule saved · $n weekly reminder(s) set' : 'Schedule saved · reminders off')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = _schedule;
    return Scaffold(
      appBar: AppBar(title: const Text('Gym schedule')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
              const Muted('Set the days and times you plan to train. Your split rotation still decides '
                  'which workout comes next.'),
              const SectionTitle('Weekly plan'),
              IPCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (var d = 1; d <= 7; d++)
                    ListTile(
                      title: Text(weekdayNames[d - 1], style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(s[d] == null ? 'Rest day' : fmtClock(s[d]!),
                          style: TextStyle(color: s[d] == null ? IP.muted : IP.accent, fontWeight: FontWeight.w600)),
                      onTap: s[d] == null ? null : () => _pickTime(d),
                      trailing: Switch(
                        value: s[d] != null,
                        onChanged: (on) => setState(() => s[d] = on ? (s[d] ?? 18 * 60) : null),
                      ),
                    ),
                ]),
              ),
              const SectionTitle('Reminders'),
              IPCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remind me before workouts', style: TextStyle(fontWeight: FontWeight.w700)),
                    value: _enabled,
                    onChanged: _toggleReminders,
                  ),
                  if (_permitted == false)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Notification permission is off for IronPulse.', style: TextStyle(color: IP.warning)),
                    ),
                  const Muted('When', size: 12),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final o in reminderOffsets)
                      FilterChip(
                        label: Text(o == 0 ? 'At start time' : '$o min before'),
                        selected: _offsets.contains(o),
                        onSelected: _enabled
                            ? (on) => setState(() => on ? _offsets.add(o) : (_offsets.length > 1 ? _offsets.remove(o) : null))
                            : null,
                      ),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _enabled
                        ? () async {
                            await Notifs.sendTest();
                          }
                        : null,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Send a test notification'),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              const IPCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('If reminders do not arrive', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Muted('Reminders are scheduled on your phone and may arrive a few minutes late, because Android groups '
                      'alarms to save battery. Some phones (Realme, Xiaomi, Oppo, Vivo) stop background alarms for '
                      'apps they consider idle. If reminders go missing, open Settings → Apps → IronPulse → Battery '
                      'and choose "Allow background activity" or "Unrestricted".',
                      size: 12.5),
                ]),
              ),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
              onPressed: s == null || _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save schedule')),
        ),
      ),
    );
  }
}
