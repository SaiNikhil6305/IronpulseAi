import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'account_repo.dart';
import 'repo.dart';

class CloudException implements Exception {
  final String message;
  CloudException(this.message);
  @override
  String toString() => message;
}

class BackupInfo {
  final DateTime updatedAt;
  final int sizeBytes;
  BackupInfo(this.updatedAt, this.sizeBytes);
}

/// Accounts (Supabase Auth: email + Google) and cloud backup of the on-device database.
/// The phone stays the source of truth; the cloud holds one private backup per user, protected by
/// Row Level Security so no user can read another's row.
class CloudRepo {
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready || !cloudConfigured) return;
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    if (googleConfigured) {
      await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
    }
    _ready = true;
  }

  static SupabaseClient get _c {
    if (!_ready) throw CloudException('Cloud backup is not set up in this build.');
    return Supabase.instance.client;
  }

  static User? get user => _ready ? Supabase.instance.client.auth.currentUser : null;
  static bool get signedIn => user != null;

  /// Current login token (refreshed if expired), used to reach IronPulse AI. Null when signed out.
  static Future<String?> accessToken() async {
    if (!_ready) return null;
    final auth = Supabase.instance.client.auth;
    var s = auth.currentSession;
    if (s == null) return null;
    if (s.isExpired) {
      try {
        s = (await auth.refreshSession()).session;
      } catch (_) {
        return null;
      }
    }
    return s?.accessToken;
  }

  static String _friendly(Object e) {
    if (e is CloudException) return e.message;
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return 'Wrong email or password.';
      if (m.contains('already registered')) return 'An account with this email already exists. Sign in instead.';
      if (m.contains('email not confirmed')) return 'Confirm your email first - enter the code we sent.';
      if (m.contains('token') && m.contains('expired')) return 'That code has expired. Request a new one.';
      if (m.contains('password')) return e.message;
      return e.message;
    }
    if (e is GoogleSignInException) {
      return e.code == GoogleSignInExceptionCode.canceled ? 'Google sign-in was cancelled.' : 'Google sign-in failed: ${e.description ?? e.code.name}';
    }
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
      return 'No internet connection. Your data is safe on this phone - try again when online.';
    }
    return 'Something went wrong: $s';
  }

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw CloudException(_friendly(e));
    }
  }

  // ---------- Email ----------
  /// Creates an account. Supabase emails a 6-digit code; confirm it with [verifySignupCode].
  static Future<bool> signUp(String email, String password) => _guard(() async {
        final r = await _c.auth.signUp(email: email.trim(), password: password);
        return r.session != null; // true if email confirmation is switched off in Supabase
      });

  static Future<void> verifySignupCode(String email, String code) =>
      _guard(() => _c.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.signup));

  static Future<void> signIn(String email, String password) =>
      _guard(() => _c.auth.signInWithPassword(email: email.trim(), password: password));

  /// Sends a 6-digit reset code by email; then call [resetPassword].
  static Future<void> sendPasswordReset(String email) => _guard(() => _c.auth.resetPasswordForEmail(email.trim()));

  static Future<void> resetPassword(String email, String code, String newPassword) => _guard(() async {
        await _c.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.recovery);
        await _c.auth.updateUser(UserAttributes(password: newPassword));
      });

  // ---------- Google ----------
  static Future<void> signInWithGoogle() => _guard(() async {
        if (!googleConfigured) throw CloudException('Google Sign-In is not set up in this build.');
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) throw CloudException('Google did not return a sign-in token.');
        await _c.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
      });

  static Future<void> signOut() => _guard(() async {
        if (googleConfigured) {
          try {
            await GoogleSignIn.instance.signOut();
          } catch (_) {}
        }
        await _c.auth.signOut();
      });

  // ---------- Backup ----------
  static Future<BackupInfo?> lastBackup() => _guard(() async {
        final uid = user?.id;
        if (uid == null) return null;
        final r = await _c.from('backups').select('updated_at, size_bytes').eq('user_id', uid).maybeSingle();
        if (r == null) return null;
        return BackupInfo(DateTime.parse(r['updated_at'] as String).toLocal(), (r['size_bytes'] as num).toInt());
      });

  /// Uploads the full local data set (same content as Export, never tokens) to the user's private row.
  static Future<BackupInfo> backupNow() => _guard(() async {
        final uid = user?.id;
        if (uid == null) throw CloudException('Sign in to back up.');
        final data = await AccountRepo.exportData();
        final size = data.toString().length;
        final now = DateTime.now().toUtc();
        await _c.from('backups').upsert({
          'user_id': uid,
          'data': data,
          'app_version': '0.2.0',
          'size_bytes': size,
          'updated_at': now.toIso8601String(),
        });
        await Repo.updateProfile({'cloud_last_backup': now.toIso8601String()});
        return BackupInfo(now.toLocal(), size);
      });

  /// Replaces this phone's data with the cloud backup.
  static Future<void> restore() => _guard(() async {
        final uid = user?.id;
        if (uid == null) throw CloudException('Sign in to restore.');
        final r = await _c.from('backups').select('data').eq('user_id', uid).maybeSingle();
        if (r == null) throw CloudException('No backup found for this account yet.');
        await AccountRepo.importData(Map<String, dynamic>.from(r['data'] as Map));
      });

  /// Quiet automatic backup after a workout. Never throws; skipped when signed out or offline.
  static Future<void> autoBackup() async {
    if (!signedIn) return;
    try {
      final p = await Repo.profile();
      if ((p?['cloud_auto_backup'] as int? ?? 1) == 1) await backupNow();
    } catch (_) {}
  }

  /// Deletes the cloud backup and the login itself (server function runs as the signed-in user only).
  static Future<void> deleteCloudAccount() => _guard(() async {
        await _c.rpc('delete_my_account');
        try {
          await signOut();
        } catch (_) {}
      });
}
