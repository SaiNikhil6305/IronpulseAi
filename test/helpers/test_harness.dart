import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ironpulse/core/network/api_client.dart';
import 'package:ironpulse/core/storage/local_db.dart';
import 'package:ironpulse/core/storage/providers.dart';
import 'package:ironpulse/core/sync/sync_service.dart';
import 'package:ironpulse/features/auth/data/auth_controller.dart';
import 'package:ironpulse/features/notifications/data/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<LocalDb> openTestDb() async {
  sqfliteFfiInit();
  return LocalDb.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
}

/// Signed-in account (sync enabled) without touching Supabase.
class FakeAccountAuth extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, userId: 'user-1', email: 'a@example.test');
  @override
  Future<String?> accessToken({bool forceRefresh = false}) async => 'test-token';
}

/// Device-only mode.
class FakeLocalAuth extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, userId: 'local', isLocal: true);
}

class FakeNetwork implements NetworkMonitor {
  final controller = StreamController<bool>.broadcast();
  bool online = true;
  @override
  Stream<bool> get onlineChanges => controller.stream;
  @override
  Future<bool> isOnline() async => online;
  void set(bool v) {
    online = v;
    controller.add(v);
  }
}

/// Notification service that records calls instead of using the platform plugin.
class FakeNotifications extends NotificationService {
  int restScheduled = 0;
  int restCancelled = 0;
  @override
  Future<void> scheduleRestTimer(DateTime at, {required bool sound, required bool vibrate}) async => restScheduled++;
  @override
  Future<void> cancelRestTimer() async => restCancelled++;
  @override
  Future<bool> permissionGranted() async => true;
}

/// Scriptable HTTP backend for ApiClient tests.
class FakeBackend implements HttpClientAdapter {
  bool online = true;
  final List<RequestOptions> requests = [];
  ResponseBody Function(RequestOptions o)? handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (!online) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'offline');
    }
    requests.add(options);
    return (handler ?? (_) => ResponseBody.fromString('{}', 200, headers: _json))(options);
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType]
  };

  static ResponseBody json(String body, [int status = 200]) => ResponseBody.fromString(body, status, headers: _json);

  @override
  void close({bool force = false}) {}
}

Future<ProviderContainer> makeContainer({
  required LocalDb db,
  bool account = false,
  FakeBackend? backend,
  FakeNetwork? network,
  FakeNotifications? notifications,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final be = backend ?? FakeBackend();
  return ProviderContainer(overrides: [
    localDbProvider.overrideWithValue(db),
    prefsProvider.overrideWithValue(sp),
    authControllerProvider.overrideWith(account ? FakeAccountAuth.new : FakeLocalAuth.new),
    networkMonitorProvider.overrideWithValue(network ?? FakeNetwork()),
    notificationServiceProvider.overrideWithValue(notifications ?? FakeNotifications()),
    apiClientProvider.overrideWith((ref) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test', contentType: 'application/json'))..httpClientAdapter = be;
      return ApiClient(tokenProvider: ({bool forceRefresh = false}) async => 'test-token', dio: dio);
    }),
  ]);
}
