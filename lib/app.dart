import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/router.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/data/notification_service.dart';
import 'features/notifications/data/reminder_sync.dart';

class IronPulseApp extends ConsumerStatefulWidget {
  const IronPulseApp({super.key, this.initialNotificationPayload});
  final String? initialNotificationPayload;

  @override
  ConsumerState<IronPulseApp> createState() => _IronPulseAppState();
}

class _IronPulseAppState extends ConsumerState<IronPulseApp> with WidgetsBindingObserver {
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _taps = ref.read(notificationServiceProvider).taps.listen(_openPayload);
    final initial = widget.initialNotificationPayload;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPayload(initial));
    }
  }

  void _openPayload(String payload) {
    if (!payload.startsWith('route:')) return;
    final route = payload.substring(6);
    // Opening a notification only navigates; it never completes checklist items or sets.
    Future.delayed(const Duration(milliseconds: 300), () {
      final router = ref.read(routerProvider);
      if (route == '/workout/active') {
        router.push(route);
      } else if (route.startsWith('/home') || route.startsWith('/workout') || route == '/progress') {
        router.go(route);
      } else {
        router.push(route);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider.notifier).schedule(Duration.zero);
      unawaited(ref.read(reminderSyncProvider).resyncAll());
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'IronPulse',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
