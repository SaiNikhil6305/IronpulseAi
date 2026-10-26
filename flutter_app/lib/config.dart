// Build-time configuration. These values are PUBLIC by design (Supabase anon key is protected by
// Row Level Security; a Google *client id* is not a secret). Never put service-role keys or client
// secrets here. Provide them with:  flutter run --dart-define-from-file=env.json
// (env.json is created from env.example.json and kept out of git).

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Google OAuth client id of type "Web application" (used as serverClientId so Supabase can verify the token).
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

bool get cloudConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
bool get googleConfigured => cloudConfigured && googleWebClientId.isNotEmpty;
