import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_planner.dart';

/// Wraps flutter_local_notifications. Reminders are scheduled on-device
/// (no server push). Delivery while the app is closed depends on OS battery
/// policies — see docs/NOTIFICATIONS.md.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin]) : _p = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _p;
  bool _ready = false;
  String timezoneId = 'UTC';
  final _taps = StreamController<String>.broadcast();

  /// Payloads of tapped notifications (e.g. "route:/workout").
  Stream<String> get taps => _taps.stream;

  static const _gymChannel = AndroidNotificationDetails('gym_reminders', 'Gym reminders',
      channelDescription: 'Reminders before your scheduled workouts', importance: Importance.high,
      priority: Priority.high, category: AndroidNotificationCategory.reminder);
  static const _habitChannel = AndroidNotificationDetails('habit_reminders', 'Checklist & weigh-in reminders',
      channelDescription: 'Optional checklist and weekly weigh-in reminders', importance: Importance.defaultImportance);

  Future<String?> init() async {
    if (_ready) return null;
    tzdata.initializeTimeZones();
    try {
      timezoneId = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(timezoneId));
    } catch (_) {
      timezoneId = 'UTC';
      tz.setLocalLocation(tz.UTC);
    }
    await _p.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_ironpulse'),
        iOS: DarwinInitializationSettings(
            requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) _taps.add(r.payload!);
      },
    );
    _ready = true;
    final launch = await _p.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true ? launch!.notificationResponse?.payload : null;
  }

  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
  }

  Future<bool> permissionGranted() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    final ios = _p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final opts = await ios?.checkPermissions();
    return opts?.isEnabled ?? false;
  }

  Future<void> openSettings() async => _p.openAppNotificationSettings();

  tz.TZDateTime _nextInstance(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (t.weekday != weekday || !t.isAfter(now)) {
      t = tz.TZDateTime(tz.local, t.year, t.month, t.day + 1, hour, minute);
    }
    return t;
  }

  Future<void> _weekly(ReminderSpec r, AndroidNotificationDetails android) => _p.zonedSchedule(
        id: r.id,
        scheduledDate: _nextInstance(r.weekday, r.hour, r.minute),
        notificationDetails: NotificationDetails(android: android, iOS: const DarwinNotificationDetails()),
        // Inexact alarms avoid the restricted exact-alarm permission; reminders may arrive a few minutes late.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: r.payload,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );

  /// Replace all gym reminders (cancel the whole id range first: no duplicates).
  Future<int> rescheduleGymReminders(List<ReminderSpec> specs) async {
    if (!_ready) return 0;
    for (var id = ReminderIds.gymRange.$1; id <= ReminderIds.gymRange.$2; id++) {
      await _p.cancel(id: id);
    }
    for (final r in specs) {
      await _weekly(r, _gymChannel);
    }
    return specs.length;
  }

  Future<void> scheduleWeighIn(int? weekday, String? hhmm) async {
    if (!_ready) return;
    await _p.cancel(id: ReminderIds.weighIn);
    if (weekday == null || hhmm == null) return;
    final p = hhmm.split(':');
    await _weekly(
      ReminderSpec(id: ReminderIds.weighIn, weekday: weekday, hour: int.parse(p[0]), minute: int.parse(p[1]),
          title: 'Weekly weigh-in', body: 'Time for your weekly weigh-in. Same time, same conditions works best.',
          payload: 'route:/weight'),
      _habitChannel,
    );
  }

  /// Daily checklist reminders. Opening one never marks the item complete.
  Future<void> scheduleChecklist(List<({String id, String name, String hhmm})> items, Set<String> previousIds) async {
    if (!_ready) return;
    for (final id in previousIds) {
      await _p.cancel(id: ReminderIds.checklist(id));
    }
    for (final it in items) {
      final p = it.hhmm.split(':');
      final now = tz.TZDateTime.now(tz.local);
      var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      if (!t.isAfter(now)) t = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, t.hour, t.minute);
      await _p.zonedSchedule(
        id: ReminderIds.checklist(it.id),
        scheduledDate: t,
        notificationDetails: const NotificationDetails(android: _habitChannel, iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Daily checklist',
        body: 'Reminder: ${it.name}. Tap to open your checklist.',
        payload: 'route:/home',
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> scheduleRestTimer(DateTime at, {required bool sound, required bool vibrate}) async {
    if (!_ready) return;
    final when = tz.TZDateTime.from(at, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _p.zonedSchedule(
      id: ReminderIds.restTimer,
      scheduledDate: when,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          sound ? 'rest_timer' : 'rest_timer_silent',
          sound ? 'Rest timer' : 'Rest timer (silent)',
          channelDescription: 'Alerts when your rest period ends',
          importance: Importance.high,
          priority: Priority.high,
          playSound: sound,
          enableVibration: vibrate,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: DarwinNotificationDetails(presentSound: sound),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Rest complete',
      body: 'Time for your next set.',
      payload: 'route:/workout/active',
    );
  }

  Future<void> cancelRestTimer() async {
    if (_ready) await _p.cancel(id: ReminderIds.restTimer);
  }

  Future<int> pendingCount() async => _ready ? (await _p.pendingNotificationRequests()).length : 0;

  Future<void> cancelAll() async {
    if (_ready) await _p.cancelAll();
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());
