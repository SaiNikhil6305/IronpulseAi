# Authentication setup (Supabase + Google Sign-In)

The app supports email/password sign-up and sign-in, password reset, session restore, sign-out, account
deletion and native Google Sign-In. Nothing works until the steps below are done — until then the app shows
"Account sign-in not configured" and offers device-only mode (it never shows a fake Google button).

## 1. Supabase project

1. Create a project at supabase.com. Note **Project URL** and the **anon / publishable key**
   (Project Settings → API). These two are public and go into `config/app_config.json`.
2. Keep the **service role key** and **database password** for the backend only (`backend/.env`).
3. Authentication → Providers → **Email**: enable; keep "Confirm email" on (recommended).
4. Authentication → URL Configuration → **Redirect URLs**: add
   * `com.ironpulse.app://login-callback` (email confirmation)
   * `com.ironpulse.app://reset-callback` (password reset)
5. Database: run `alembic upgrade head` from `backend/` with `DATABASE_URL` pointing at the project (Project
   Settings → Database → connection string, `postgresql+psycopg://…`), then run `backend/supabase/policies.sql`
   in the SQL editor (RLS lockdown + private `progress-photos` bucket).
6. JWT verification: new projects use asymmetric signing keys — set only `SUPABASE_URL` in the backend.
   Legacy projects with a shared JWT secret: also set `SUPABASE_JWT_SECRET`.

## 2. Google Cloud OAuth

In one Google Cloud project (APIs & Services):

1. **OAuth consent screen**: app name *IronPulse*, support email, privacy-policy URL (host
   `docs/public/privacy.html`), scopes `openid`, `email`, `profile` only. Publish when ready (testing mode
   limits sign-in to listed test users).
2. **Web application client** → this is `GOOGLE_WEB_CLIENT_ID` (used as `serverClientId` so Google issues an ID
   token Supabase accepts). Its **client secret goes only into the Supabase dashboard**, never into the app.
3. **Android client**: package name `com.ironpulse.app` + SHA-1 of each signing key:
   * debug: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   * release/upload key: `keytool -list -v -keystore upload-keystore.jks -alias upload`
   * Play App Signing: copy the **App signing key** SHA-1 from Play Console → Setup → App signing.
   Create one Android client per SHA-1 (debug, upload, Play signing).
4. **iOS client**: bundle ID `com.ironpulse.app` → this is `GOOGLE_IOS_CLIENT_ID`. Put it and its *reversed*
   form in `ios/Flutter/Google.xcconfig`.

## 3. Supabase Google provider

Authentication → Providers → **Google**: enable, paste the **web client ID** and **web client secret**. Add the
iOS (and Android) client IDs to the authorized client IDs list (comma-separated). Turn on **Skip nonce check**
(required for native iOS sign-in with `google_sign_in`).

## 4. App configuration

```bash
cp config/app_config.example.json config/app_config.json   # git-ignored
# fill SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL, GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID
flutter run --dart-define-from-file=config/app_config.json
```

## 5. How it works in the app

| Flow | Implementation |
|---|---|
| Email sign-up | `auth.signUp(emailRedirectTo: com.ironpulse.app://login-callback)`; if confirmation is on, the user confirms then signs in. |
| Google | `GoogleSignIn.instance.initialize(serverClientId: web, clientId: iOS)` → `authenticate()` → ID token → `signInWithIdToken(OAuthProvider.google)`. Cancellation is silent; misconfiguration shows a clear message. |
| Password reset | `resetPasswordForEmail(redirectTo: …reset-callback)` → deep link → PKCE exchange → `passwordRecovery` event → *Choose a new password* screen. |
| Session storage | Access/refresh tokens in Android Keystore / iOS Keychain (`SecureSessionStorage`). |
| Session restore / expiry | Restored at launch; refreshed automatically and on a backend `401` (one retry). A failed refresh signs the user out. |
| New vs existing account | After sign-in the app hydrates from `/v1/sync/snapshot`; no completed profile → onboarding, otherwise home. |
| Sign-out | Syncs pending changes first (warns if some can't be sent), wipes local data and reminders, signs out of Google and Supabase. |
| Account deletion | `DELETE /v1/account` erases data, storage objects and the Supabase auth user (service role, server-side). |

## 6. Verify (manual, on a device)

- [ ] Email sign-up → confirmation email → link opens app → sign in works
- [ ] Wrong password shows "Incorrect email or password."
- [ ] Password reset email → link opens app → new password works
- [ ] Google sign-in (new account → onboarding; existing → home with data restored)
- [ ] Cancel Google picker → no error shown
- [ ] Kill and reopen app → still signed in
- [ ] Sign out → sign-in screen; data gone from device; sign in again → data restored
- [ ] Airplane mode → log a workout → reconnect → appears on another device
