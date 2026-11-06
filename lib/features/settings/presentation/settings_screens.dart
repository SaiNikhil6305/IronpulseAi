import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/widgets.dart';
import '../../ai_assistant/presentation/ai_screen.dart';
import '../../auth/data/auth_controller.dart';
import '../../notifications/data/notification_service.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import '../../profile/domain/profile.dart';
import '../../workouts/data/rest_timer.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/domain/workout_models.dart';
import 'legal_text.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final profile = ref.watch(profileProvider) ?? Profile.empty;
    final sync = ref.watch(syncServiceProvider);

    Widget tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Widget? trailing, Color? color}) =>
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(title, style: TextStyle(color: color)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(Gaps.lg),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.accentMuted,
              child: Text(profile.displayName.isEmpty ? '?' : profile.displayName[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.accent, fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: Gaps.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.displayName.isEmpty ? 'Athlete' : profile.displayName, style: Theme.of(context).textTheme.titleLarge),
                Text(auth.isLocal ? 'Device-only mode' : (auth.email ?? ''), style: const TextStyle(color: AppColors.textMuted)),
              ]),
            ),
          ]),
        ),
        const _Header('Profile'),
        tile(Icons.person_outline, 'Personal profile & goals', subtitle: 'Body stats, experience, goals, equipment, diet',
            onTap: () => context.push('/profile')),
        tile(Icons.straighten, 'Units',
            subtitle: profile.units == 'imperial' ? 'Pounds, inches' : 'Kilograms, centimetres',
            trailing: Switch(
              value: profile.units == 'imperial',
              onChanged: (v) => ref.read(profileRepositoryProvider).save(profile.copyWith({'units': v ? 'imperial' : 'metric'})),
            )),
        tile(Icons.flag_outlined, 'Weekly training target', subtitle: '${profile.weeklyTarget} workouts per week',
            onTap: () => _pickTarget(context, ref, profile)),
        const _Header('Training'),
        tile(Icons.view_week_outlined, 'Workout split', subtitle: ref.watch(activeSplitProvider)?.name ?? 'Not set',
            onTap: () => context.push('/split')),
        tile(Icons.calendar_month_outlined, 'Gym schedule & reminders', onTap: () => context.push('/schedule')),
        tile(Icons.timer_outlined, 'Rest timer', subtitle: '${ref.read(restTimerProvider.notifier).settings.defaultSeconds}s default',
            onTap: () => _restSettings(context, ref)),
        tile(Icons.menu_book_outlined, 'Exercise library', onTap: () => context.push('/exercises')),
        tile(Icons.history, 'Workout history', onTap: () => context.push('/workout/history')),
        tile(Icons.emoji_events_outlined, 'XP & achievements', onTap: () => context.push('/achievements')),
        const _Header('Nutrition & body'),
        tile(Icons.checklist, 'Daily checklist', onTap: () => context.push('/checklist')),
        tile(Icons.flag, 'Fitness goals', onTap: () => context.push('/goals')),
        tile(Icons.monitor_weight_outlined, 'Body weight', onTap: () => context.push('/weight')),
        tile(Icons.photo_library_outlined, 'Progress photos', onTap: () => context.push('/photos')),
        tile(Icons.watch_outlined, 'Wearables & health data', onTap: () => context.push('/wearables')),
        const _Header('Privacy & data'),
        tile(Icons.auto_awesome_outlined, 'What IronPulse AI can see',
            subtitle: profile.aiContextScopes.isEmpty ? 'Nothing shared' : '${profile.aiContextScopes.length} categories shared',
            onTap: () => showAiPrivacySheet(context)),
        if (!auth.isLocal)
          tile(Icons.sync, 'Sync status',
              subtitle: sync.failed > 0
                  ? '${sync.failed} need attention'
                  : sync.pending > 0
                      ? '${sync.pending} waiting to upload'
                      : 'Everything synced',
              onTap: () => context.push('/sync')),
        tile(Icons.download_outlined, 'Export my data', subtitle: 'JSON (everything) and CSV (workout sets)', onTap: () => _export(context, ref)),
        tile(Icons.policy_outlined, 'Privacy policy', onTap: () => context.push('/privacy')),
        tile(Icons.description_outlined, 'Terms & conditions', onTap: () => context.push('/terms')),
        const _Header('Account'),
        tile(Icons.logout, auth.isLocal ? 'Leave device-only mode' : 'Sign out', onTap: () => _signOut(context, ref)),
        tile(Icons.delete_forever_outlined, auth.isLocal ? 'Erase all data on this device' : 'Delete account',
            color: AppColors.error, onTap: () => _delete(context, ref)),
        const Padding(
          padding: EdgeInsets.all(Gaps.xl),
          child: Column(children: [
            Brand(size: 16),
            SizedBox(height: 4),
            Text('Train Smart. Track Every Rep. Become Stronger.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Text('Version 1.0.0', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Future<void> _pickTarget(BuildContext context, WidgetRef ref, Profile profile) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          const ListTile(title: Text('Workouts per week', style: TextStyle(fontWeight: FontWeight.w800))),
          for (var i = 1; i <= 7; i++)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 12),
              child: ChoiceChip(label: Text('$i'), selected: profile.weeklyTarget == i, onSelected: (_) => Navigator.pop(ctx, i)),
            ),
        ]),
      ),
    );
    if (v != null) await ref.read(profileRepositoryProvider).save(profile.copyWith({'weekly_target': v}));
  }

  Future<void> _restSettings(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(restTimerProvider.notifier);
    var s = ctrl.settings;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rest timer', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: Gaps.md),
              Wrap(spacing: 8, children: [
                for (final sec in [45, 60, 90, 120, 150, 180, 240])
                  ChoiceChip(
                    label: Text(sec < 60 ? '${sec}s' : '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}'),
                    selected: s.defaultSeconds == sec,
                    onSelected: (_) => set(() => s = RestSettings(defaultSeconds: sec, sound: s.sound, vibrate: s.vibrate, autoStart: s.autoStart)),
                  ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start automatically after a set'),
                value: s.autoStart,
                onChanged: (v) => set(() => s = RestSettings(defaultSeconds: s.defaultSeconds, sound: s.sound, vibrate: s.vibrate, autoStart: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sound'),
                value: s.sound,
                onChanged: (v) => set(() => s = RestSettings(defaultSeconds: s.defaultSeconds, sound: v, vibrate: s.vibrate, autoStart: s.autoStart)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vibration'),
                value: s.vibrate,
                onChanged: (v) => set(() => s = RestSettings(defaultSeconds: s.defaultSeconds, sound: s.sound, vibrate: v, autoStart: s.autoStart)),
              ),
              const SizedBox(height: Gaps.md),
              FilledButton(
                onPressed: () async {
                  await ctrl.saveSettings(s);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authControllerProvider);
    final db = ref.read(localDbProvider);
    try {
      Map<String, dynamic> data;
      if (auth.canSync) {
        await ref.read(syncServiceProvider.notifier).syncNow();
        data = Map<String, dynamic>.from(await ref.read(apiClientProvider).get('/v1/account/export') as Map);
      } else {
        data = await localExport(db);
      }
      final dir = await getTemporaryDirectory();
      final stamp = Dates.iso(DateTime.now());
      final json = File(p.join(dir.path, 'ironpulse-export-$stamp.json'))
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
      final sessions = [for (final d in await db.listDocs(Col.sessions)) WorkoutSession.fromJson(d)];
      final csv = File(p.join(dir.path, 'ironpulse-workout-sets-$stamp.csv'))..writeAsStringSync(workoutSetsCsv(sessions));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(json.path, mimeType: 'application/json'), XFile(csv.path, mimeType: 'text/csv')],
        subject: 'IronPulse data export',
      ));
    } catch (e) {
      if (context.mounted) showSnack(context, 'Export failed: ${ApiException.from(e).message}', error: true);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final sync = ref.read(syncServiceProvider);
    final auth = ref.read(authControllerProvider);
    if (auth.canSync && (sync.pending > 0 || sync.failed > 0)) {
      await ref.read(syncServiceProvider.notifier).syncNow();
    }
    final left = ref.read(syncServiceProvider);
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: auth.isLocal ? 'Leave device-only mode?' : 'Sign out?',
      message: auth.isLocal
          ? 'Your data stays on this device and will be here if you choose device-only mode again.'
          : (left.pending + left.failed > 0
              ? '${left.pending + left.failed} change(s) have not reached the server and will be lost. Sign out anyway?'
              : 'Your data is safely synced. It will be removed from this device and restored when you sign in again.'),
      confirm: 'Sign out',
      destructive: !auth.isLocal && left.pending + left.failed > 0,
    );
    if (!ok) return;
    if (!auth.isLocal) {
      // Remove this account's data from the device; it is restored from the server on next sign-in.
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(restTimerProvider.notifier).skip();
      await _wipeDevice(ref);
    }
    await ref.read(authControllerProvider.notifier).signOut();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authControllerProvider);
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(auth.isLocal ? 'Erase all data?' : 'Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(auth.isLocal
                ? 'This permanently erases every workout, meal, goal and photo stored in IronPulse on this device.'
                : 'This permanently deletes your account and all your IronPulse data on our servers and this device: '
                    'workouts, nutrition, goals, photos, AI conversations and imported health data. This cannot be undone. '
                    'Consider exporting your data first.'),
            const SizedBox(height: Gaps.md),
            const Text('Type DELETE to confirm'),
            TextField(controller: c, autofocus: true, onChanged: (_) => set(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: c.text.trim() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      if (auth.canSync) {
        final r = await ref.read(apiClientProvider).delete('/v1/account');
        if (r is Map && r['status'] == 'partial' && context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Data deleted'),
              content: Text('Your IronPulse data was deleted. Some cleanup needs follow-up by the operator '
                  '(reference ${r['request_id']}).'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
        }
      }
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(restTimerProvider.notifier).skip();
      await _wipeDevice(ref);
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Could not delete account: ${ApiException.from(e).message}. Nothing was removed.', error: true);
      }
    }
  }
}

Future<void> _wipeDevice(WidgetRef ref) async {
  await ref.read(localDbProvider).clearAll();
  final prefs = ref.read(prefsProvider);
  for (final k in prefs.getKeys().toList()) {
    if (k != 'auth.local_mode') await prefs.remove(k);
  }
  try {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'progress_photos'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {}
}

/// Device-only export: every local document grouped by collection.
Future<Map<String, dynamic>> localExport(LocalDb db) async {
  final out = <String, dynamic>{'format': 'ironpulse-local-export-v1', 'exported_at': DateTime.now().toUtc().toIso8601String()};
  for (final c in [Col.meta, Col.sessions, Col.userExercises, Col.checklistItems, Col.checklistCompletions, Col.meals, Col.goals,
    Col.weights, Col.photos, Col.healthDaily]) {
    out[c] = await db.listDocs(c);
  }
  (out[Col.meta] as List).removeWhere((m) => (m as Map).containsKey('ends_at'));
  return out;
}

String _csv(Object? v) {
  final s = v?.toString() ?? '';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// One row per set, for spreadsheets.
String workoutSetsCsv(List<WorkoutSession> sessions) {
  final b = StringBuffer('date,workout,exercise,set,side,weight_kg,reps,rpe,duration_s,distance_m,completed\n');
  final sorted = [...sessions]..sort((a, c) => a.startedAt.compareTo(c.startedAt));
  for (final s in sorted.where((s) => s.status != 'discarded')) {
    for (final e in s.exercises) {
      for (var i = 0; i < e.sets.length; i++) {
        final st = e.sets[i];
        b.writeln([
          s.startedAt.toUtc().toIso8601String(), s.name, e.exerciseName, i + 1, st.side, st.weightKg, st.reps, st.rpe,
          st.durationS, st.distanceM, st.completed,
        ].map(_csv).join(','));
      }
    }
  }
  return b.toString();
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.lg, Gaps.xs),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.textMuted)),
      );
}

class ProfileEditScreen extends StatelessWidget {
  const ProfileEditScreen({super.key});
  @override
  Widget build(BuildContext context) => const OnboardingScreen(editMode: true);
}

enum LegalKind { privacy, terms }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});
  final LegalKind kind;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(kind == LegalKind.privacy ? 'Privacy policy' : 'Terms & conditions')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Gaps.lg),
          child: SelectableText(kind == LegalKind.privacy ? privacyPolicyText : termsText, style: const TextStyle(height: 1.5)),
        ),
      );
}

class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    ref.watch(collectionTickProvider('outbox'));
    return Scaffold(
      appBar: AppBar(title: const Text('Sync status')),
      body: ListView(padding: const EdgeInsets.all(Gaps.lg), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sync.syncing ? 'Syncing…' : (sync.allSynced ? 'Everything is synced' : '${sync.pending} waiting · ${sync.failed} need attention'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            if (sync.lastSyncedAt != null)
              Text('Last successful sync ${TimeOfDay.fromDateTime(sync.lastSyncedAt!).format(context)}',
                  style: const TextStyle(color: AppColors.textMuted)),
            if (sync.lastError != null) Text(sync.lastError!, style: const TextStyle(color: AppColors.warning)),
            const SizedBox(height: Gaps.md),
            Row(children: [
              FilledButton(onPressed: () => ref.read(syncServiceProvider.notifier).syncNow(), child: const Text('Sync now')),
              const SizedBox(width: Gaps.md),
              if (sync.failed > 0)
                OutlinedButton(onPressed: () => ref.read(syncServiceProvider.notifier).retryFailed(), child: const Text('Retry failed')),
            ]),
          ]),
        ),
        const SizedBox(height: Gaps.md),
        const Text(
          'Changes are saved on this phone first, then uploaded. Nothing is deleted if an upload fails — rejected '
          'changes stay here for review. When the same workout was edited on two devices, the most recent edit wins.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SectionHeader('Queue'),
        FutureBuilder<List<OutboxOp>>(
          future: ref.read(localDbProvider).pendingOps(includeFailed: true),
          builder: (_, snap) {
            final ops = snap.data ?? const [];
            if (ops.isEmpty) return const Text('Empty.', style: TextStyle(color: AppColors.textMuted));
            return Column(children: [
              for (final o in ops)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(o.failedPermanently ? Icons.error_outline : Icons.schedule,
                      color: o.failedPermanently ? AppColors.error : AppColors.textMuted),
                  title: Text('${o.method} ${o.path}', style: const TextStyle(fontSize: 13)),
                  subtitle: Text([
                    'attempts ${o.attempts}',
                    if (o.lastError != null) o.lastError!,
                  ].join(' · ')),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

