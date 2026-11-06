import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/storage/local_db.dart';
import 'core/storage/providers.dart';
import 'features/auth/data/secure_session_storage.dart';
import 'features/notifications/data/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF16171A),
  ));

  if (Env.backendConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: SecureSessionStorage(),
        pkceAsyncStorage: SecurePkceStorage(),
      ),
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final db = await LocalDb.open();
  final notifications = NotificationService();
  String? launchPayload;
  try {
    launchPayload = await notifications.init();
  } catch (_) {
    // Notifications are optional; the app works without them.
  }

  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      localDbProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(notifications),
    ],
    child: IronPulseApp(initialNotificationPayload: launchPayload),
  ));
}
