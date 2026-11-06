import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../notifications/data/notification_service.dart';

@immutable
class RestTimerState {
  const RestTimerState({this.endsAt, this.totalS = 0, this.pausedRemainingS});
  final DateTime? endsAt;
  final int totalS;
  final int? pausedRemainingS;

  bool get active => endsAt != null || pausedRemainingS != null;
  bool get paused => pausedRemainingS != null;

  int remainingS([DateTime? now]) {
    if (pausedRemainingS != null) return pausedRemainingS!;
    if (endsAt == null) return 0;
    final r = endsAt!.difference(now ?? DateTime.now()).inMilliseconds;
    return r <= 0 ? 0 : (r / 1000).ceil();
  }

  Map<String, dynamic> toJson() =>
      {'ends_at': endsAt?.toIso8601String(), 'total_s': totalS, 'paused_remaining_s': pausedRemainingS};

  factory RestTimerState.fromJson(Map<String, dynamic> j) => RestTimerState(
        endsAt: j['ends_at'] == null ? null : DateTime.parse(j['ends_at'] as String),
        totalS: (j['total_s'] as num?)?.toInt() ?? 0,
        pausedRemainingS: (j['paused_remaining_s'] as num?)?.toInt(),
      );
}

class RestSettings {
  const RestSettings({this.defaultSeconds = 90, this.sound = true, this.vibrate = true, this.autoStart = true});
  final int defaultSeconds;
  final bool sound;
  final bool vibrate;
  final bool autoStart;
}

/// Rest timer that survives app restarts (persisted) and alerts through a
/// local notification even when the app is in the background.
class RestTimerController extends Notifier<RestTimerState> {
  static const _key = 'rest_timer.state';

  @override
  RestTimerState build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const RestTimerState();
    try {
      final s = RestTimerState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!s.paused && s.remainingS() == 0) return const RestTimerState();
      return s;
    } catch (_) {
      return const RestTimerState();
    }
  }

  RestSettings get settings {
    final p = ref.read(prefsProvider);
    return RestSettings(
      defaultSeconds: p.getInt('rest.default_s') ?? 90,
      sound: p.getBool('rest.sound') ?? true,
      vibrate: p.getBool('rest.vibrate') ?? true,
      autoStart: p.getBool('rest.auto_start') ?? true,
    );
  }

  Future<void> saveSettings(RestSettings s) async {
    final p = ref.read(prefsProvider);
    await p.setInt('rest.default_s', s.defaultSeconds);
    await p.setBool('rest.sound', s.sound);
    await p.setBool('rest.vibrate', s.vibrate);
    await p.setBool('rest.auto_start', s.autoStart);
  }

  Future<void> _persist(RestTimerState s) async {
    state = s;
    final p = ref.read(prefsProvider);
    if (s.active) {
      await p.setString(_key, jsonEncode(s.toJson()));
    } else {
      await p.remove(_key);
    }
  }

  NotificationService get _n => ref.read(notificationServiceProvider);

  Future<void> start([int? seconds]) async {
    final secs = seconds ?? settings.defaultSeconds;
    final ends = DateTime.now().add(Duration(seconds: secs));
    await _persist(RestTimerState(endsAt: ends, totalS: secs));
    await _n.cancelRestTimer();
    await _n.scheduleRestTimer(ends, sound: settings.sound, vibrate: settings.vibrate);
  }

  Future<void> addSeconds(int delta) async {
    if (!state.active) return;
    if (state.paused) {
      final r = (state.pausedRemainingS! + delta).clamp(0, 3600);
      await _persist(RestTimerState(totalS: state.totalS + delta, pausedRemainingS: r));
      return;
    }
    final ends = state.endsAt!.add(Duration(seconds: delta));
    await _persist(RestTimerState(endsAt: ends, totalS: (state.totalS + delta).clamp(1, 3600)));
    await _n.cancelRestTimer();
    await _n.scheduleRestTimer(ends, sound: settings.sound, vibrate: settings.vibrate);
  }

  Future<void> togglePause() async {
    if (!state.active) return;
    if (state.paused) {
      final ends = DateTime.now().add(Duration(seconds: state.pausedRemainingS!));
      await _persist(RestTimerState(endsAt: ends, totalS: state.totalS));
      await _n.scheduleRestTimer(ends, sound: settings.sound, vibrate: settings.vibrate);
    } else {
      await _persist(RestTimerState(totalS: state.totalS, pausedRemainingS: state.remainingS()));
      await _n.cancelRestTimer();
    }
  }

  Future<void> skip() async {
    await _persist(const RestTimerState());
    await _n.cancelRestTimer();
  }
}

final restTimerProvider = NotifierProvider<RestTimerController, RestTimerState>(RestTimerController.new);
