import 'package:flutter/material.dart';

import '../data/health_repo.dart';
import '../logic/health_summary.dart';
import '../logic/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

class WearablesScreen extends StatefulWidget {
  const WearablesScreen({super.key});
  @override
  State<WearablesScreen> createState() => _WearablesScreenState();
}

class _WearablesScreenState extends State<WearablesScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    notifyDataChanged();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _connect() => _run(() async {
        final ok = await HealthRepo.connect();
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Access was not granted. You can allow it any time in Health Connect → App permissions.')));
          }
          return;
        }
        final n = await HealthRepo.sync();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(n == 0 ? 'Connected. No data in Health Connect yet.' : 'Imported $n day(s) of data')));
        }
      });

  Future<void> _sync() => _run(() async {
        final n = await HealthRepo.sync();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Synced $n day(s)')));
      });

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Health Connect?'),
        content: const Text('IronPulse will stop reading health data and delete everything it imported. '
            'Data stays in Health Connect and your other apps.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok == true) await _run(HealthRepo.disconnect);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wearables')),
      body: Reloading<(HealthState, List<DailyHealth>)>(
        load: () async => (await HealthRepo.state(), await HealthRepo.recent()),
        builder: (context, data) {
          final (s, days) = data;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            const Muted('IronPulse reads from Android Health Connect, which collects data from your phone, '
                'Fitbit, Samsung Health, Wear OS watches and many other apps. Read-only - IronPulse never writes to it.'),
            const SectionTitle('Health Connect'),
            _statusCard(s),
            if (s.enabled && days.isNotEmpty) ...[
              const SectionTitle('Last 7 days (imported)'),
              IPCard(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(flex: 3, child: Muted('DAY', size: 11)),
                      Expanded(flex: 3, child: Muted('STEPS', size: 11)),
                      Expanded(flex: 3, child: Muted('HEART RATE', size: 11)),
                      Expanded(flex: 3, child: Muted('SLEEP', size: 11)),
                    ]),
                  ),
                  for (final d in days.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(fmtDate(DateTime.parse(d.day)).split(',').last.trim())),
                        Expanded(flex: 3, child: Text(d.steps?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700))),
                        Expanded(
                            flex: 3,
                            child: Text(d.hrAvg == null ? (d.restingHr == null ? '-' : '${d.restingHr!.round()} rest')
                                : '${d.hrAvg!.round()} avg')),
                        Expanded(flex: 3, child: Text(fmtSleep(d.sleepMinutes))),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              const Muted('Values are as reported by your devices. Calorie estimates are not imported.', size: 11.5),
            ],
            const SectionTitle('Other devices'),
            IPCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                _provider('Fitbit', 'Turn on Health Connect sync in the Fitbit app - data then appears here.', 'Via Health Connect'),
                _provider('Wear OS / Samsung / Mi Band', 'Supported when the device app syncs to Health Connect.', 'Via Health Connect'),
                _provider('Apple Health / Apple Watch', 'iPhone version planned.', 'Planned'),
                _provider('Direct Bluetooth', 'Not supported - devices are read through their official apps.', 'Unavailable'),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _provider(String name, String sub, String tag) => ListTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        trailing: Text(tag, style: TextStyle(fontSize: 11, color: tag == 'Via Health Connect' ? IP.success : IP.muted)),
      );

  Widget _statusCard(HealthState s) {
    final (label, color) = switch (s.status) {
      HcStatus.unsupported => ('Not available on this device', IP.muted),
      HcStatus.notInstalled => ('Health Connect is not installed', IP.warning),
      HcStatus.needsUpdate => ('Health Connect needs an update', IP.warning),
      HcStatus.available => s.enabled ? ('Connected', IP.success) : ('Not connected', IP.muted),
    };
    return IPCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.favorite, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        if (s.enabled) ...[
          const SizedBox(height: 6),
          Muted(s.lastSync == null
              ? 'Not synced yet'
              : 'Last sync: ${fmtDate(s.lastSync!)} ${s.lastSync!.hour.toString().padLeft(2, '0')}:${s.lastSync!.minute.toString().padLeft(2, '0')}'),
          const Muted('Reads: steps, heart rate, resting heart rate, sleep', size: 12),
        ],
        if (s.lastError != null) ...[
          const SizedBox(height: 6),
          Text(s.lastError!, style: const TextStyle(color: IP.warning, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else if (s.status == HcStatus.notInstalled || s.status == HcStatus.needsUpdate)
          FilledButton(
              onPressed: () => _run(HealthRepo.openInstall),
              child: Text(s.status == HcStatus.needsUpdate ? 'Update Health Connect' : 'Install Health Connect'))
        else if (s.status == HcStatus.available && !s.enabled)
          FilledButton(onPressed: _connect, child: const Text('Connect Health Connect'))
        else if (s.status == HcStatus.available)
          Row(children: [
            Expanded(child: FilledButton(onPressed: _sync, child: const Text('Sync now'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect'))),
          ]),
      ]),
    );
  }
}

/// Compact card for the Progress screen. Shows nothing until the user connects.
class HealthSummaryCard extends StatelessWidget {
  const HealthSummaryCard({super.key});

  @override
  Widget build(BuildContext context) => Reloading<(HealthState, List<DailyHealth>)>(
        load: () async => (await HealthRepo.state(), await HealthRepo.recent()),
        builder: (context, data) {
          final (s, days) = data;
          if (!s.enabled) {
            return IPCard(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WearablesScreen())),
              child: const Row(children: [
                Icon(Icons.watch_outlined, color: IP.accent),
                SizedBox(width: 12),
                Expanded(child: Text('Connect Health Connect to see steps, heart rate and sleep here.')),
              ]),
            );
          }
          final steps = days.where((d) => d.steps != null).map((d) => d.steps!).toList();
          final sleep = days.where((d) => d.sleepMinutes != null).map((d) => d.sleepMinutes!).toList();
          final rest = days.where((d) => d.restingHr != null).map((d) => d.restingHr!).toList();
          String avg(List<num> l, String Function(double) f) => l.isEmpty ? '-' : f(l.reduce((a, b) => a + b) / l.length);
          return Row(children: [
            StatTile('Avg steps', avg(steps, (v) => v.round().toString()), icon: Icons.directions_walk),
            const SizedBox(width: 10),
            StatTile('Avg sleep', avg(sleep, (v) => fmtSleep(v.round())), icon: Icons.bedtime_outlined),
            const SizedBox(width: 10),
            StatTile('Resting HR', avg(rest, (v) => '${v.round()}'), icon: Icons.favorite_border),
          ]);
        },
      );
}
