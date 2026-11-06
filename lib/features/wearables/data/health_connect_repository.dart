import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

import '../../../core/storage/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/units.dart';

/// Daily aggregate imported from Health Connect / Apple Health. Values come
/// from the user's devices; calories are the device's own estimate.
class HealthDay {
  const HealthDay({required this.day, this.steps, this.heartRateAvg, this.activeKcal, this.workoutMin, this.sleepMin});
  final String day;
  final int? steps;
  final double? heartRateAvg;
  final double? activeKcal;
  final double? workoutMin;
  final double? sleepMin;

  factory HealthDay.fromJson(Map<String, dynamic> j) => HealthDay(
        day: j['day'] as String,
        steps: (j['steps'] as num?)?.toInt(),
        heartRateAvg: (j['heart_rate_avg'] as num?)?.toDouble(),
        activeKcal: (j['active_kcal'] as num?)?.toDouble(),
        workoutMin: (j['workout_min'] as num?)?.toDouble(),
        sleepMin: (j['sleep_min'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'steps': steps,
        'heart_rate_avg': heartRateAvg,
        'active_kcal': activeKcal,
        'workout_min': workoutMin,
        'sleep_min': sleepMin,
      };
}

enum HealthAvailability { available, needsInstall, needsUpdate, unsupported }

class HealthConnectRepository {
  HealthConnectRepository(this.ref, [Health? health]) : _health = health ?? Health();
  final Ref ref;
  final Health _health;
  bool _configured = false;

  static const types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
    HealthDataType.SLEEP_SESSION,
  ];

  String get provider => Platform.isIOS ? 'apple_health' : 'health_connect';

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthAvailability> availability() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return HealthAvailability.unsupported;
    await _configure();
    if (Platform.isIOS) return HealthAvailability.available;
    final s = await _health.getHealthConnectSdkStatus();
    return switch (s) {
      HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HealthAvailability.needsUpdate,
      _ => HealthAvailability.needsInstall,
    };
  }

  Future<void> install() => _health.installHealthConnect();

  /// Real platform permission dialog. Read-only access.
  Future<bool> connect() async {
    await _configure();
    final ok = await _health.requestAuthorization(types, permissions: [for (final _ in types) HealthDataAccess.READ]);
    await ref.read(localDbProvider).putDoc(Col.meta, Meta.wearable, {
      'status': ok ? 'connected' : 'denied',
      'provider': provider,
      'granted_types': ok ? [for (final t in types) t.name] : <String>[],
      'last_synced_at': null,
      'last_error': ok ? null : 'Permission not granted',
    });
    return ok;
  }

  Future<void> disconnect({bool deleteData = false}) async {
    try {
      await _health.revokePermissions();
    } catch (_) {}
    final db = ref.read(localDbProvider);
    await db.putDoc(Col.meta, Meta.wearable, {'status': 'disconnected', 'provider': provider});
    if (deleteData) {
      for (final d in await db.listDocs(Col.healthDaily)) {
        await db.deleteDoc(Col.healthDaily, d['day'] as String);
      }
    }
    await ref.read(dataWriterProvider).enqueue('DELETE', '/v1/wearables/$provider?delete_data=$deleteData', null);
  }

  /// Import the last [days] days as daily aggregates and queue them for backup.
  Future<int> sync({int days = 7}) async {
    await _configure();
    final db = ref.read(localDbProvider);
    final now = DateTime.now();
    final start = Dates.dayOnly(now).subtract(Duration(days: days - 1));
    try {
      final points = _health.removeDuplicates(
          await _health.getHealthDataFromTypes(types: types.where((t) => t != HealthDataType.STEPS).toList(), startTime: start, endTime: now));
      final out = <HealthDay>[];
      for (var i = 0; i < days; i++) {
        final dayStart = start.add(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(days: 1));
        final steps = await _health.getTotalStepsInInterval(dayStart, dayEnd.isAfter(now) ? now : dayEnd);
        bool inDay(DateTime t) => !t.isBefore(dayStart) && t.isBefore(dayEnd);
        double? sum(HealthDataType type, {bool useEnd = false}) {
          final ps = points.where((p) => p.type == type && inDay(useEnd ? p.dateTo : p.dateFrom));
          if (ps.isEmpty) return null;
          return ps.fold<double>(0, (a, p) {
            if (type == HealthDataType.WORKOUT || type == HealthDataType.SLEEP_SESSION) {
              return a + p.dateTo.difference(p.dateFrom).inMinutes;
            }
            final v = p.value;
            return a + (v is NumericHealthValue ? v.numericValue.toDouble() : 0);
          });
        }

        final hr = points.where((p) => p.type == HealthDataType.HEART_RATE && inDay(p.dateFrom)).toList();
        double? hrAvg;
        if (hr.isNotEmpty) {
          hrAvg = hr.fold<double>(0, (a, p) => a + (p.value is NumericHealthValue ? (p.value as NumericHealthValue).numericValue.toDouble() : 0)) / hr.length;
        }
        out.add(HealthDay(
          day: Dates.iso(dayStart),
          steps: steps,
          heartRateAvg: hrAvg,
          activeKcal: sum(HealthDataType.ACTIVE_ENERGY_BURNED),
          workoutMin: sum(HealthDataType.WORKOUT),
          sleepMin: sum(HealthDataType.SLEEP_SESSION, useEnd: true),
        ));
      }
      for (final d in out) {
        await db.putDoc(Col.healthDaily, d.day, d.toJson());
      }
      final records = <Map<String, dynamic>>[];
      for (final d in out) {
        final s = DateTime.parse(d.day).toUtc().toIso8601String();
        final e = DateTime.parse(d.day).add(const Duration(days: 1)).toUtc().toIso8601String();
        void add(String type, num? v, String unit) {
          if (v != null) records.add({'record_uid': '$type:${d.day}', 'data_type': type, 'value': v, 'unit': unit, 'start_at': s, 'end_at': e});
        }

        add('steps', d.steps, 'count');
        add('heart_rate', d.heartRateAvg, 'bpm_avg');
        add('calories', d.activeKcal, 'kcal_device_estimate');
        add('active_minutes', d.workoutMin, 'min');
        add('sleep', d.sleepMin, 'min');
      }
      final meta = await db.getDoc(Col.meta, Meta.wearable) ?? {};
      await db.putDoc(Col.meta, Meta.wearable, {
        ...meta,
        'status': 'connected',
        'provider': provider,
        'last_synced_at': DateTime.now().toIso8601String(),
        'last_error': null,
      });
      await ref.read(dataWriterProvider).enqueue('POST', '/v1/wearables/sync',
          {'provider': provider, 'granted_types': meta['granted_types'] ?? [], 'records': records});
      return out.length;
    } catch (e) {
      final meta = await db.getDoc(Col.meta, Meta.wearable) ?? {};
      await db.putDoc(Col.meta, Meta.wearable, {...meta, 'last_error': e.toString()});
      rethrow;
    }
  }
}

final healthRepositoryProvider = Provider<HealthConnectRepository>((ref) => HealthConnectRepository(ref));

final healthDaysProvider = Provider<List<HealthDay>>((ref) {
  final docs = ref.watch(docsProvider(Col.healthDaily)).value ?? const [];
  return [for (final d in docs) HealthDay.fromJson(d)]..sort((a, b) => b.day.compareTo(a.day));
});
