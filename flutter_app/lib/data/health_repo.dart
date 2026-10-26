import 'dart:io' show Platform;

import 'package:health/health.dart';
import 'package:sqflite/sqflite.dart';

import '../logic/health_summary.dart';
import 'account_repo.dart';
import 'db.dart';
import 'repo.dart';

enum HcStatus { unsupported, notInstalled, needsUpdate, available }

class HealthState {
  final HcStatus status;
  final bool enabled;
  final DateTime? lastSync;
  final String? lastError;
  const HealthState(this.status, this.enabled, this.lastSync, this.lastError);
}

/// Android Health Connect integration (read-only). Fitbit, Samsung Health, Wear OS watches and the phone's
/// own step counter all write into Health Connect, so one integration covers them - nothing is guessed.
class HealthRepo {
  static Future<Database> get _db => AppDb.get();
  static final _health = Health();
  static bool _configured = false;

  static const types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
  ];

  static Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static Future<HcStatus> status() async {
    if (!Platform.isAndroid) return HcStatus.unsupported;
    try {
      await _configure();
      final s = await _health.getHealthConnectSdkStatus();
      return switch (s) {
        HealthConnectSdkStatus.sdkAvailable => HcStatus.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HcStatus.needsUpdate,
        _ => HcStatus.notInstalled,
      };
    } catch (_) {
      return HcStatus.notInstalled;
    }
  }

  static Future<void> openInstall() async {
    await _configure();
    await _health.installHealthConnect();
  }

  static Future<HealthState> state() async {
    final p = await Repo.profile();
    final last = p?['health_last_sync'] as String?;
    return HealthState(await status(), (p?['health_enabled'] as int? ?? 0) == 1,
        last == null ? null : DateTime.parse(last), p?['health_last_error'] as String?);
  }

  /// Shows the Health Connect permission screen. Returns true if the user allowed access.
  static Future<bool> connect() async {
    await _configure();
    final ok = await _health.requestAuthorization(types, permissions: types.map((_) => HealthDataAccess.READ).toList());
    await Repo.updateProfile({'health_enabled': ok ? 1 : 0, 'health_last_error': ok ? null : 'Permission not granted'});
    await AccountRepo.recordConsent('health_connect', ok);
    return ok;
  }

  /// Disconnects: revokes permissions and deletes everything imported.
  static Future<void> disconnect() async {
    try {
      await _configure();
      await _health.revokePermissions();
    } catch (_) {}
    final db = await _db;
    await db.delete('health_daily');
    await Repo.updateProfile({'health_enabled': 0, 'health_last_sync': null, 'health_last_error': null});
    await AccountRepo.recordConsent('health_connect', false);
  }

  /// Revokes Health Connect access without touching the database (used before deleting everything).
  static Future<void> revokeOnly() async {
    try {
      await _configure();
      await _health.revokePermissions();
    } catch (_) {}
  }

  /// Imports the last [days] days as daily summaries. Returns the number of days with data.
  static Future<int> sync({int days = 7}) async {
    await _configure();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    try {
      final stepsByDay = <String, int>{};
      for (var d = start; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
        final end = d.add(const Duration(days: 1));
        final n = await _health.getTotalStepsInInterval(d, end.isAfter(now) ? now : end);
        if (n != null && n > 0) stepsByDay[healthDayKey(d)] = n;
      }
      // Sleep that ends this morning may have started yesterday evening, so look back one more day.
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE, HealthDataType.RESTING_HEART_RATE, HealthDataType.SLEEP_SESSION],
        startTime: start.subtract(const Duration(days: 1)),
        endTime: now,
      );
      final raw = <RawSample>[];
      for (final p in points) { // already de-duplicated by the plugin
        final v = p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue.toDouble() : 0.0;
        final kind = switch (p.type) {
          HealthDataType.HEART_RATE => Sample.heartRate,
          HealthDataType.RESTING_HEART_RATE => Sample.restingHeartRate,
          HealthDataType.SLEEP_SESSION => Sample.sleep,
          _ => null,
        };
        if (kind != null) raw.add(RawSample(kind, p.dateFrom, p.dateTo, v));
      }
      final summary = summarize(raw, stepsByDay)..removeWhere((k, v) => k.compareTo(healthDayKey(start)) < 0 || v.isEmpty);
      await saveSummaries(summary.values);
      await Repo.updateProfile({'health_last_sync': nowIso(), 'health_last_error': null});
      return summary.length;
    } catch (e) {
      await Repo.updateProfile({'health_last_error': 'Sync failed: $e'});
      rethrow;
    }
  }

  static Future<void> saveSummaries(Iterable<DailyHealth> rows) async {
    final db = await _db;
    await db.transaction((t) async {
      for (final r in rows) {
        await t.insert('health_daily', {...r.toMap(), 'synced_at': nowIso()}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<List<DailyHealth>> recent({int days = 7}) async {
    final since = healthDayKey(DateTime.now().subtract(Duration(days: days - 1)));
    final r = await (await _db).query('health_daily', where: 'day >= ?', whereArgs: [since], orderBy: 'day');
    return r.map(DailyHealth.fromMap).toList();
  }
}
