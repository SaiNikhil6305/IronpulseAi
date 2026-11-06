/// Public, build-time configuration supplied with
/// `--dart-define-from-file=config/app_config.json`.
///
/// Everything here is compiled into the app binary and must be treated as
/// PUBLIC. Never add service-role keys, database passwords, AI provider keys
/// or OAuth client secrets here — those live only in the backend environment.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon/publishable key. Public by design; RLS keeps data private.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// IronPulse FastAPI backend, e.g. https://api.example.com
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// OAuth *client IDs* (not secrets). The web client id is the
  /// `serverClientId` used to mint ID tokens that Supabase accepts.
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Deep-link scheme registered in AndroidManifest/Info.plist for auth emails.
  static const authRedirectScheme = 'com.ironpulse.app';
  static const passwordResetRedirect = '$authRedirectScheme://reset-callback';
  static const emailConfirmRedirect = '$authRedirectScheme://login-callback';

  static bool get backendConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && apiBaseUrl.isNotEmpty;

  static bool get googleConfigured => googleWebClientId.isNotEmpty;

  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
        if (apiBaseUrl.isEmpty) 'API_BASE_URL',
      ];
}
