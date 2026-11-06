import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/data/auth_controller.dart';
import '../network/api_client.dart';
import '../storage/local_db.dart';
import '../storage/providers.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      tokenProvider: ({bool forceRefresh = false}) =>
          ref.read(authControllerProvider.notifier).accessToken(forceRefresh: forceRefresh),
    ));

@immutable
class SyncState {
  const SyncState({
    this.pending = 0,
    this.failed = 0,
    this.syncing = false,
    this.online = true,
    this.lastSyncedAt,
    this.lastError,
    this.enabled = false,
  });

  final int pending;
  final int failed;
  final bool syncing;
  final bool online;
  final DateTime? lastSyncedAt;
  final String? lastError;

  /// False in device-only mode or when signed out.
  final bool enabled;

  bool get allSynced => pending == 0 && failed == 0;

  SyncState copyWith({int? pending, int? failed, bool? syncing, bool? online, DateTime? lastSyncedAt,
          String? lastError, bool clearError = false, bool? enabled}) =>
      SyncState(
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        syncing: syncing ?? this.syncing,
        online: online ?? this.online,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        enabled: enabled ?? this.enabled,
      );
}

/// Abstracts connectivity so tests can simulate loss and recovery.
abstract class NetworkMonitor {
  Stream<bool> get onlineChanges;
  Future<bool> isOnline();
}

class PlatformNetworkMonitor implements NetworkMonitor {
  final _c = Connectivity();
  static bool _up(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  @override
  Stream<bool> get onlineChanges => _c.onConnectivityChanged.map(_up);
  @override
  Future<bool> isOnline() async => _up(await _c.checkConnectivity());
}

final networkMonitorProvider = Provider<NetworkMonitor>((ref) => PlatformNetworkMonitor());

/// Processes the outbox in order, retrying transient failures and keeping
/// permanently rejected operations visible to the user (never silently dropped).
class SyncService extends Notifier<SyncState> {
  Timer? _debounce;
  Timer? _periodic;
  bool _running = false;
  final List<StreamSubscription<Object?>> _subs = [];

  LocalDb get _db => ref.read(localDbProvider);
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  SyncState build() {
    final auth = ref.watch(authControllerProvider);
    ref.onDispose(() {
      _debounce?.cancel();
      _periodic?.cancel();
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
    final enabled = auth.canSync;
    _subs.add(ref.read(localDbProvider).changes.where((c) => c == 'outbox' || c == '*').listen((_) => _refreshCounts()));
    if (enabled) {
      final net = ref.read(networkMonitorProvider);
      _subs.add(net.onlineChanges.listen((online) {
        state = state.copyWith(online: online);
        if (online) schedule(Duration.zero);
      }));
      _periodic = Timer.periodic(const Duration(minutes: 2), (_) => schedule(Duration.zero));
      Future.microtask(() async {
        state = state.copyWith(online: await net.isOnline());
        schedule(Duration.zero);
      });
    }
    Future.microtask(_refreshCounts);
    return SyncState(enabled: enabled);
  }

  Future<void> _refreshCounts() async {
    try {
      final c = await _db.outboxCounts();
      state = state.copyWith(pending: c.pending, failed: c.failed);
    } catch (_) {}
  }

  /// Debounced trigger used after local writes.
  void schedule([Duration delay = const Duration(seconds: 2)]) {
    if (!state.enabled) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (!state.enabled || _running) return;
    _running = true;
    state = state.copyWith(syncing: true);
    var anySuccess = false;
    try {
      final ops = await _db.pendingOps();
      for (final op in ops) {
        try {
          final res = await _api.request(op.method, op.path, body: op.body);
          await _afterSuccess(op, res);
          await _db.removeOp(op.opId);
          anySuccess = true;
        } on ApiException catch (e) {
          if (op.method == 'DELETE' && e.status == 404) {
            await _db.removeOp(op.opId);
            continue;
          }
          if (e.isTransient || e.isAuth) {
            await _db.recordAttempt(op.opId, e.message);
            state = state.copyWith(lastError: e.message, online: e.code != 'network' && state.online);
            break; // keep ordering; retry later
          }
          // Rejected by the server (validation/conflict). Keep it for the user to review.
          await _db.recordAttempt(op.opId, '${e.code}: ${e.message}', permanent: true);
        }
      }
      if (anySuccess) {
        state = state.copyWith(lastSyncedAt: DateTime.now(), clearError: true, online: true);
        await refreshGamification();
      }
    } finally {
      _running = false;
      state = state.copyWith(syncing: false);
      await _refreshCounts();
    }
  }

  Future<void> _afterSuccess(OutboxOp op, dynamic res) async {
    if (op.method == 'PUT' && op.path.startsWith('/v1/sessions/') && res is Map) {
      await _db.putDoc(Col.sessionSync, '${res['id']}', Map<String, dynamic>.from(res));
    }
  }

  Future<void> refreshGamification() async {
    if (!state.enabled) return;
    try {
      final res = await _api.get('/v1/gamification/summary');
      if (res is Map) await _db.putDoc(Col.meta, Meta.gamification, Map<String, dynamic>.from(res));
    } catch (_) {}
  }

  Future<void> retryFailed() async {
    await _db.retryFailed();
    schedule(Duration.zero);
  }

  /// Pull the server's copy of the user's data into the local store, without
  /// overwriting anything that still has unsent local changes.
  Future<void> hydrate() async {
    if (!state.enabled) return;
    await syncNow();
    final snap = await _api.get('/v1/sync/snapshot') as Map;
    final pendingIds = await _db.idsWithPendingChanges();
    final pendingPaths = (await _db.pendingOps(includeFailed: true)).map((o) => o.path).toSet();

    Map<String, Map<String, dynamic>> byId(String key) => {
          for (final m in (snap[key] as List? ?? const [])) '${(m as Map)['id']}': Map<String, dynamic>.from(m)
        };

    Future<void> meta(String id, Object? value, String path) async {
      if (pendingPaths.contains(path)) return;
      if (value == null) {
        await _db.deleteDoc(Col.meta, id);
      } else {
        await _db.putDoc(Col.meta, id, value is Map ? Map<String, dynamic>.from(value) : {'items': value});
      }
    }

    await meta(Meta.profile, snap['profile'], '/v1/profile');
    if (!pendingPaths.any((p) => p.startsWith('/v1/splits/'))) {
      await meta(Meta.split, snap['active_split'], '/v1/splits/');
    }
    await meta(Meta.nutritionTargets, snap['nutrition_targets'], '/v1/nutrition/targets');
    await meta(Meta.schedule, {'days': snap['schedule'] ?? []}, '/v1/schedule');
    await meta(Meta.notificationPrefs, snap['notification_preferences'], '/v1/notification-preferences');

    // Sessions: keep local history outside the snapshot window.
    await _db.replaceCollection(Col.sessions, byId('sessions'), keep: pendingIds, deleteMissing: false);
    await _db.replaceCollection(Col.userExercises, byId('user_exercises'), keep: pendingIds);
    await _db.replaceCollection(Col.checklistItems, byId('checklist_items'), keep: pendingIds);
    final completions = <String, Map<String, dynamic>>{
      for (final c in (snap['checklist_completions'] as List? ?? const []))
        '${(c as Map)['item_id']}_${c['day']}': Map<String, dynamic>.from(c)
    };
    final keepCompletions = {
      for (final d in await _db.listDocs(Col.checklistCompletions))
        if (pendingIds.contains(d['item_id'])) '${d['item_id']}_${d['day']}'
    };
    await _db.replaceCollection(Col.checklistCompletions, completions, keep: keepCompletions);
    await _db.replaceCollection(Col.meals, byId('meals'), keep: pendingIds);
    await _db.replaceCollection(Col.goals, byId('goals'), keep: pendingIds);
    await _db.replaceCollection(Col.weights, byId('weights'), keep: pendingIds);
    try {
      final photos = await _api.get('/v1/photos') as List;
      await _db.replaceCollection(
          Col.photos, {for (final p in photos) '${(p as Map)['id']}': Map<String, dynamic>.from(p)},
          keep: pendingIds);
    } catch (_) {}
    await refreshGamification();
  }
}

final syncServiceProvider = NotifierProvider<SyncService, SyncState>(SyncService.new);

/// Single entry point for local-first writes: persist locally, then queue the
/// matching idempotent API call (skipped in device-only mode).
class DataWriter {
  DataWriter(this.ref);
  final Ref ref;
  static const _uuid = Uuid();

  LocalDb get _db => ref.read(localDbProvider);
  bool get _sync => ref.read(authControllerProvider).canSync;

  Future<void> save(String collection, String id, Map<String, dynamic> doc,
      {String? path, Map<String, dynamic>? body, String method = 'PUT'}) async {
    await _db.putDoc(collection, id, doc);
    if (path != null) await enqueue(method, path, body ?? doc);
  }

  Future<void> remove(String collection, String id, {String? path}) async {
    await _db.deleteDoc(collection, id);
    if (path != null) await enqueue('DELETE', path, null);
  }

  Future<void> enqueue(String method, String path, Map<String, dynamic>? body) async {
    if (!_sync) return;
    await _db.enqueue(OutboxOp(
      opId: _uuid.v4(),
      method: method,
      path: path,
      body: body,
      // A newer PUT or DELETE of the same resource supersedes older pending ones.
      coalesceKey: path,
    ));
    ref.read(syncServiceProvider.notifier).schedule();
  }
}

final dataWriterProvider = Provider<DataWriter>((ref) => DataWriter(ref));
