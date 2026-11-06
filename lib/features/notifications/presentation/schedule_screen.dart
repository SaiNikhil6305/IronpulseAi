import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/domain/split.dart';
import '../data/notification_service.dart';
import '../data/reminder_sync.dart';

final notificationPermissionProvider =
    FutureProvider.autoDispose<bool>((ref) => ref.read(notificationServiceProvider).permissionGranted());

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});
  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  List<ScheduleDay>? _days;
  NotificationPrefs? _prefs;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(scheduleProvider);
    final split = ref.watch(activeSplitProvider);
    final days = _days ??= [
      for (var wd = 1; wd <= 7; wd++) saved.where((d) => d.weekday == wd).firstOrNull ?? ScheduleDay(weekday: wd, isRestDay: true)
    ];
    _prefs ??= ref.watch(notificationPrefsProvider);
    final prefs = _prefs!;
    final permission = ref.watch(notificationPermissionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gym schedule & reminders'), actions: [
        TextButton(onPressed: _saving ? null : _save, child: const Text('SAVE')),
      ]),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        if (permission.value == false)
          AppCard(
            borderColor: AppColors.warning,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Notifications are off for IronPulse', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Your schedule still works in the app, but reminders can\'t appear until you allow notifications.',
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: Gaps.sm),
              Row(children: [
                TextButton(
                  onPressed: () async {
                    await ref.read(notificationServiceProvider).requestPermission();
                    ref.invalidate(notificationPermissionProvider);
                  },
                  child: const Text('Allow'),
                ),
                TextButton(
                  onPressed: () => ref.read(notificationServiceProvider).openSettings(),
                  child: const Text('Open settings'),
                ),
              ]),
            ]),
          ),
        const SectionHeader('Weekly schedule'),
        for (var i = 0; i < 7; i++) _dayRow(i, days[i], split),
        const SectionHeader('Reminders'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gym reminders'),
          subtitle: const Text('Personalised with your planned day and last session'),
          value: prefs.gymRemindersEnabled,
          onChanged: (v) => setState(() => _prefs = _copy(prefs, gym: v)),
        ),
        const Text('Remind me', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: Gaps.sm),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (m, label) in [(30, '30 min before'), (20, '20 min before'), (10, '10 min before'), (0, 'At start time')])
            FilterChip(
              label: Text(label),
              selected: prefs.offsets.contains(m),
              onSelected: prefs.gymRemindersEnabled
                  ? (v) => setState(() {
                        final o = {...prefs.offsets};
                        v ? o.add(m) : o.remove(m);
                        _prefs = _copy(prefs, offsets: o.toList()..sort((a, b) => b - a));
                      })
                  : null,
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Checklist reminders'),
          subtitle: const Text('For items where you set a reminder time'),
          value: prefs.checklistEnabled,
          onChanged: (v) => setState(() => _prefs = _copy(prefs, checklist: v)),
        ),
        const SizedBox(height: Gaps.md),
        const Text(
          'Reminders are scheduled on this phone and follow your local time, including daylight-saving changes. '
          'Android may delay them by a few minutes to save battery, and some phones stop reminders for apps that '
          'have been force-stopped or battery-restricted — see docs/NOTIFICATIONS.md.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ]),
    );
  }

  NotificationPrefs _copy(NotificationPrefs p, {bool? gym, List<int>? offsets, bool? checklist}) => NotificationPrefs(
        gymRemindersEnabled: gym ?? p.gymRemindersEnabled,
        offsets: offsets ?? p.offsets,
        checklistEnabled: checklist ?? p.checklistEnabled,
        weighInWeekday: p.weighInWeekday,
        weighInTime: p.weighInTime,
      );

  Widget _dayRow(int i, ScheduleDay d, WorkoutSplit? split) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
        child: Row(children: [
          SizedBox(width: 44, child: Text(Dates.weekdayName(d.weekday, short: true), style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(
            child: d.isRestDay
                ? const Text('Rest', style: TextStyle(color: AppColors.textMuted))
                : Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                    ActionChip(
                      label: Text(d.timeLocal == null ? 'Set time' : Dates.timeLabel(d.timeLocal)),
                      avatar: const Icon(Icons.schedule, size: 16),
                      onPressed: () async {
                        final parts = (d.timeLocal ?? '18:00').split(':');
                        final t = await showTimePicker(
                            context: context, initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
                        if (t != null) setState(() => _days![i] = d.copyWith(timeLocal: Dates.hhmm(t.hour, t.minute)));
                      },
                    ),
                    if (split != null)
                      DropdownButton<String?>(
                        value: split.days.any((x) => x.name == d.workoutDayName) ? d.workoutDayName : null,
                        hint: const Text('Any day'),
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('From split')),
                          for (final s in split.days) DropdownMenuItem<String?>(value: s.name, child: Text(s.name)),
                        ],
                        onChanged: (v) => setState(() => _days![i] = d.copyWith(workoutDayName: v)),
                      ),
                  ]),
          ),
          Switch(
            value: !d.isRestDay,
            onChanged: (v) => setState(() => _days![i] = d.copyWith(isRestDay: !v, timeLocal: v ? (d.timeLocal ?? '18:00') : null)),
          ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(workoutRepositoryProvider).saveSchedule(_days!);
      await ref.read(dataWriterProvider).save(Col.meta, Meta.notificationPrefs, _prefs!.toJson(), path: '/v1/notification-preferences');
      final wantsReminders = _prefs!.gymRemindersEnabled || _prefs!.checklistEnabled;
      if (wantsReminders && !(await ref.read(notificationServiceProvider).permissionGranted())) {
        await ref.read(notificationServiceProvider).requestPermission();
        ref.invalidate(notificationPermissionProvider);
      }
      final n = await ref.read(reminderSyncProvider).resyncAll();
      if (mounted) showSnack(context, 'Schedule saved${n > 0 ? ' · $n weekly reminder${n == 1 ? '' : 's'} set' : ''}.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
