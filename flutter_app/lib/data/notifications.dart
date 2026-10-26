import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logic/schedule.dart';
import 'repo.dart';

/// Local notifications for gym reminders. Reminders are weekly alarms held by the OS, so they can fire
/// while the app is closed - but delivery depends on the phone's battery settings (see ScheduleScreen).
class Notifs {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String? payload)? onTap;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'gym_reminders',
      'Gym reminders',
      channelDescription: 'Reminders before your scheduled workouts',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Falls back to UTC offsets via DateTime if the zone is unknown.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
    _ready = true;
  }

  /// Payload if the app was opened by tapping a notification.
  static Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse?.payload : null;
  }

  /// Asks the OS for permission. Returns false if the user declines.
  static Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await a?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final i = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await i?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  static Future<bool> permitted() async {
    await init();
    if (Platform.isAndroid) {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await a?.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  /// Cancels everything and schedules the current plan. Safe to call any time (app start, after a
  /// workout, after editing the schedule) - ids are stable, so there are never duplicates.
  /// Returns the number of reminders scheduled.
  static Future<int> reschedule() async {
    await init();
    await _plugin.cancelAll();
    final (enabled, offsets) = await ScheduleRepo.reminderPrefs();
    if (!enabled || offsets.isEmpty) return 0;
    final plan = planReminders(await ScheduleRepo.schedule(), offsets);
    if (plan.isEmpty) return 0;

    final next = await Repo.nextDay();
    final dayName = next?.$2.name ?? 'workout';
    final last = (await Repo.doneSessions(limit: 1)).firstOrNull;
    final lastNames = last == null ? <String>[] : (await Repo.loadSession(last.id)).map((e) => e.exercise.name).toList();

    final now = tz.TZDateTime.now(tz.local);
    for (final r in plan) {
      final at = nextWeekly(now, r.weekday, r.hour, r.minute);
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.offset == 0 ? '$dayName time' : '$dayName in ${r.offset} min',
        body: reminderText(dayName, r.offset, lastNames),
        payload: 'start',
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
    return plan.length;
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static Future<void> sendTest() async {
    await init();
    await _plugin.show(
      id: 9999,
      title: 'IronPulse reminders are working',
      body: 'Tap to open your workout.',
      notificationDetails: _details,
      payload: 'start',
    );
  }
}
