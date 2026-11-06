import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session (access + refresh token) in the platform
/// keystore (Android Keystore / iOS Keychain) instead of plain preferences.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'ironpulse.supabase.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

/// PKCE verifier storage for email links / password reset, also in the keystore.
class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: 'ironpulse.pkce.$key');

  @override
  Future<void> removeItem({required String key}) => _storage.delete(key: 'ironpulse.pkce.$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: 'ironpulse.pkce.$key', value: value);
}
