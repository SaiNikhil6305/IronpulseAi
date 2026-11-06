import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_controller.dart';
import '../../features/notifications/data/reminder_sync.dart';
import '../storage/providers.dart';
import '../sync/sync_service.dart';

const _ownerKey = 'data.owner';

/// Runs after sign-in: makes sure the local store belongs to this user and
/// pulls their data from the server before deciding onboarding vs. home.
class BootstrapController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isSignedIn || auth.userId == null) return false;
    final prefs = ref.read(prefsProvider);
    final db = ref.read(localDbProvider);

    // Never mix two accounts' data on one device.
    final owner = prefs.getString(_ownerKey);
    if (owner != null && owner != auth.userId) await db.clearAll();
    await prefs.setString(_ownerKey, auth.userId!);

    if (auth.canSync) {
      final hasLocalProfile = await db.getDoc(Col.meta, Meta.profile) != null;
      try {
        await ref.read(syncServiceProvider.notifier).hydrate().timeout(const Duration(seconds: 25));
      } catch (e) {
        // Offline start with existing local data is fine; a brand-new device needs the server.
        if (!hasLocalProfile) rethrow;
      }
    }
    unawaited(ref.read(reminderSyncProvider).resyncAll());
    return true;
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}

final bootstrapProvider = AsyncNotifierProvider<BootstrapController, bool>(BootstrapController.new);

Future<void> clearLocalUserData(Ref ref) async {
  await ref.read(localDbProvider).clearAll();
  await ref.read(prefsProvider).remove(_ownerKey);
}
