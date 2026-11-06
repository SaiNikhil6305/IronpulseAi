import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../data/health_connect_repository.dart';

final _availabilityProvider = FutureProvider.autoDispose<HealthAvailability>((ref) async {
  try {
    return await ref.read(healthRepositoryProvider).availability();
  } catch (_) {
    return HealthAvailability.unsupported;
  }
});

class WearablesScreen extends ConsumerStatefulWidget {
  const WearablesScreen({super.key});
  @override
  ConsumerState<WearablesScreen> createState() => _WearablesScreenState();
}

class _WearablesScreenState extends ConsumerState<WearablesScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showSnack(context, 'Health sync failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avail = ref.watch(_availabilityProvider);
    final meta = ref.watch(docProvider((Col.meta, Meta.wearable))).value;
    final days = ref.watch(healthDaysProvider);
    final repo = ref.read(healthRepositoryProvider);
    final connected = meta?['status'] == 'connected';
    final name = Platform.isIOS ? 'Apple Health' : 'Health Connect';

    return Scaffold(
      appBar: AppBar(title: const Text('Wearables & health data')),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.favorite_outline, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
              Pill(connected ? 'Connected' : (meta?['status'] == 'denied' ? 'Permission denied' : 'Not connected'),
                  color: connected ? AppColors.success : AppColors.textMuted),
            ]),
            const SizedBox(height: Gaps.sm),
            Text(
              'Reads steps, heart rate, active energy, workouts and sleep from $name (read-only). Works with watches and '
              'trackers that write to $name, such as many Wear OS, Samsung, Fitbit and Garmin devices via their apps.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (meta?['last_synced_at'] != null)
              Padding(
                padding: const EdgeInsets.only(top: Gaps.sm),
                child: Text('Last sync: ${Dates.friendly(DateTime.parse(meta!['last_synced_at'] as String))} '
                    '${TimeOfDay.fromDateTime(DateTime.parse(meta['last_synced_at'] as String)).format(context)}'),
              ),
            if (meta?['last_error'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Last error: ${meta!['last_error']}', style: const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            const SizedBox(height: Gaps.md),
            avail.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (a) => switch (a) {
                HealthAvailability.unsupported => const Text('Not supported on this device.', style: TextStyle(color: AppColors.textMuted)),
                HealthAvailability.needsInstall || HealthAvailability.needsUpdate => LoadingButton(
                    label: a == HealthAvailability.needsUpdate ? 'Update Health Connect' : 'Install Health Connect',
                    onPressed: () => repo.install(),
                  ),
                HealthAvailability.available => connected
                    ? Row(children: [
                        Expanded(
                          child: LoadingButton(
                            label: 'Sync now',
                            loading: _busy,
                            icon: Icons.sync,
                            onPressed: () => _run(() async {
                              final n = await repo.sync();
                              if (context.mounted) showSnack(context, 'Imported $n days from $name.');
                            }),
                          ),
                        ),
                        const SizedBox(width: Gaps.md),
                        OutlinedButton(
                          onPressed: () async {
                            final del = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Disconnect $name?'),
                                content: const Text('IronPulse will stop reading health data. Also delete data already imported?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep data')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete data')),
                                ],
                              ),
                            );
                            if (del != null) await _run(() => repo.disconnect(deleteData: del));
                          },
                          child: const Text('Disconnect'),
                        ),
                      ])
                    : LoadingButton(
                        label: 'Connect $name',
                        loading: _busy,
                        onPressed: () => _run(() async {
                          final ok = await repo.connect();
                          if (ok) {
                            await repo.sync();
                          } else if (context.mounted) {
                            showSnack(context, 'Permission was not granted. You can allow it later in $name settings.');
                          }
                        }),
                      ),
              },
            ),
          ]),
        ),
        const SectionHeader('Imported data'),
        if (days.isEmpty)
          const Text('Nothing imported yet.', style: TextStyle(color: AppColors.textMuted))
        else
          for (final d in days)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(Dates.friendly(DateTime.parse(d.day))),
              subtitle: Text([
                if (d.steps != null) '${d.steps} steps',
                if (d.heartRateAvg != null) 'avg HR ${d.heartRateAvg!.round()} bpm',
                if (d.activeKcal != null) '≈${d.activeKcal!.round()} active kcal (device estimate)',
                if (d.workoutMin != null) '${d.workoutMin!.round()} min workouts',
                if (d.sleepMin != null) '${(d.sleepMin! / 60).toStringAsFixed(1)} h sleep',
              ].join(' · ').ifEmpty('No data recorded')),
            ),
        const SectionHeader('Other devices'),
        for (final (n, why) in [
          ('Fitbit Web API', 'Planned — requires Fitbit developer approval. Many Fitbit devices already sync via Health Connect.'),
          ('Direct Wear OS app', 'Planned — a watch app is not part of this release.'),
          ('Generic Bluetooth', 'Not supported — devices don\'t share a common Bluetooth fitness protocol.'),
        ])
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.watch_outlined), title: Text(n), subtitle: Text(why), trailing: const Pill('Unavailable')),
        const SizedBox(height: Gaps.md),
        const Text(
          'Health data is sensitive. It is stored privately on this device and, when signed in, in your account. '
          'It is never used for advertising and never shared with IronPulse AI unless you enable that.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
