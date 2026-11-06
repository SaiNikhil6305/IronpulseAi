import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/env.dart';
import '../../../core/storage/providers.dart';

enum AuthStatus { unknown, signedOut, signedIn }

@immutable
class AuthState {
  const AuthState({required this.status, this.userId, this.email, this.isLocal = false, this.recovering = false});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut() : this(status: AuthStatus.signedOut);

  final AuthStatus status;
  final String? userId;
  final String? email;

  /// Device-only mode, offered only when no backend is configured in this build.
  final bool isLocal;

  /// The user opened a password-reset link and must choose a new password.
  final bool recovering;

  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get canSync => isSignedIn && !isLocal;
}

class AuthFailure implements Exception {
  AuthFailure(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

const _localModeKey = 'auth.local_mode';

class AuthController extends Notifier<AuthState> {
  StreamSubscription<sb.AuthState>? _sub;
  bool _googleInitialised = false;

  sb.GoTrueClient get _auth => sb.Supabase.instance.client.auth;

  @override
  AuthState build() {
    ref.onDispose(() => _sub?.cancel());
    final prefs = ref.watch(prefsProvider);
    if (!Env.backendConfigured) {
      return prefs.getBool(_localModeKey) == true
          ? const AuthState(status: AuthStatus.signedIn, userId: 'local', isLocal: true)
          : const AuthState.signedOut();
    }
    _sub = _auth.onAuthStateChange.listen((data) {
      final s = data.session;
      if (data.event == sb.AuthChangeEvent.passwordRecovery && s != null) {
        state = AuthState(status: AuthStatus.signedIn, userId: s.user.id, email: s.user.email, recovering: true);
      } else if (s == null) {
        state = const AuthState.signedOut();
      } else {
        state = AuthState(status: AuthStatus.signedIn, userId: s.user.id, email: s.user.email,
            recovering: state.recovering && data.event != sb.AuthChangeEvent.userUpdated);
      }
    }, onError: (_) {});
    final session = _auth.currentSession;
    return session == null
        ? const AuthState.signedOut()
        : AuthState(status: AuthStatus.signedIn, userId: session.user.id, email: session.user.email);
  }

  /// Current access token for the backend (refreshing when asked or expired).
  Future<String?> accessToken({bool forceRefresh = false}) async {
    if (!Env.backendConfigured) return null;
    var session = _auth.currentSession;
    if (session == null) return null;
    if (forceRefresh || session.isExpired) {
      try {
        session = (await _auth.refreshSession()).session;
      } on sb.AuthException {
        return null;
      }
    }
    return session?.accessToken;
  }

  Future<void> enableLocalMode() async {
    if (Env.backendConfigured) return;
    await ref.read(prefsProvider).setBool(_localModeKey, true);
    state = const AuthState(status: AuthStatus.signedIn, userId: 'local', isLocal: true);
  }

  Future<void> signInWithEmail(String email, String password) => _guard(() async {
        await _auth.signInWithPassword(email: email.trim(), password: password);
      });

  /// Returns true when the account still needs email confirmation.
  Future<bool> signUpWithEmail(String email, String password) async {
    late bool needsConfirmation;
    await _guard(() async {
      final res = await _auth.signUp(
          email: email.trim(), password: password, emailRedirectTo: Env.emailConfirmRedirect);
      needsConfirmation = res.session == null;
    });
    return needsConfirmation;
  }

  Future<void> sendPasswordReset(String email) => _guard(() async {
        await _auth.resetPasswordForEmail(email.trim(), redirectTo: Env.passwordResetRedirect);
      });

  Future<void> setNewPassword(String password) => _guard(() async {
        await _auth.updateUser(sb.UserAttributes(password: password));
        state = AuthState(status: AuthStatus.signedIn, userId: state.userId, email: state.email);
      });

  /// Native Google Sign-In → Google ID token → Supabase session.
  Future<void> signInWithGoogle() async {
    if (!Env.backendConfigured || !Env.googleConfigured) {
      throw AuthFailure('Google Sign-In is not configured for this build.');
    }
    final google = GoogleSignIn.instance;
    try {
      if (!_googleInitialised) {
        await google.initialize(
          serverClientId: Env.googleWebClientId,
          clientId: defaultTargetPlatform == TargetPlatform.iOS && Env.googleIosClientId.isNotEmpty
              ? Env.googleIosClientId
              : null,
        );
        _googleInitialised = true;
      }
      final account = await google.authenticate(scopeHint: const ['email', 'profile']);
      final idToken = account.authentication.idToken;
      if (idToken == null) throw AuthFailure('Google did not return an ID token. Check the OAuth client setup.');
      await _guard(() => _auth.signInWithIdToken(provider: sb.OAuthProvider.google, idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw AuthFailure('Google sign-in was cancelled.', cancelled: true);
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw AuthFailure('Google Sign-In is misconfigured (OAuth client / SHA-1). See docs/AUTH_SETUP.md.');
      }
      throw AuthFailure('Google sign-in failed: ${e.description ?? e.code.name}');
    }
  }

  Future<void> signOut() async {
    if (state.isLocal) {
      await ref.read(prefsProvider).remove(_localModeKey);
      state = const AuthState.signedOut();
      return;
    }
    if (Env.googleConfigured && _googleInitialised) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    try {
      await _auth.signOut();
    } on sb.AuthException {
      // Token already revoked/expired: local sign-out still proceeds.
    }
    state = const AuthState.signedOut();
  }

  Future<void> _guard(Future<void> Function() fn) async {
    try {
      await fn();
    } on sb.AuthException catch (e) {
      throw AuthFailure(_friendly(e));
    } on AuthFailure {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
        throw AuthFailure('No internet connection. Please try again when you are online.');
      }
      throw AuthFailure('Something went wrong. Please try again.');
    }
  }

  static String _friendly(sb.AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) return 'Incorrect email or password.';
    if (m.contains('email not confirmed')) return 'Please confirm your email address first — check your inbox.';
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    if (m.contains('rate limit') || e.statusCode == '429') return 'Too many attempts. Please wait a moment.';
    if (m.contains('password')) return e.message;
    return e.message;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
