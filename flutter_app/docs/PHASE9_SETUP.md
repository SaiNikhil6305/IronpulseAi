# Phase 9 setup - accounts, Google Sign-In, cloud backup, release build

Everything below is free tier. Do the parts in order. **Never paste keys, passwords or tokens into chat.**
Values you put in `env.json` are public by design (Supabase anon key + Google client ID); the Google
**client secret** goes only into the Supabase dashboard.

---
## Part A - Supabase project (accounts + backup database), ~10 min
1. Go to **supabase.com** → sign in with GitHub → **New project**.
   Name `ironpulse`, choose a strong database password (save it in a password manager),
   region **Mumbai (ap-south-1)** if offered. Wait ~2 minutes.
2. **SQL Editor → New query**, paste the whole of `flutter_app/supabase/schema.sql`, click **Run**.
   You should see "Success. No rows returned".
3. **Authentication → Sign In / Providers → Email**: keep **Email** enabled and **Confirm email** ON.
4. **Authentication → Emails → Templates**. The app uses 6-digit codes instead of links:
   - **Confirm signup**: replace the body with
     `<h2>Your IronPulse code</h2><p>Enter this code in the app: <b>{{ .Token }}</b></p>`
   - **Reset password**: replace the body with
     `<h2>Reset your IronPulse password</h2><p>Enter this code in the app: <b>{{ .Token }}</b></p>`
5. **Project Settings → API**: copy the **Project URL** and the **anon / publishable** key (NOT service_role).

## Part B - Google Sign-In, ~15 min
1. **console.cloud.google.com** → create project `IronPulse`.
2. **APIs & Services → OAuth consent screen**: External, app name IronPulse, your support email,
   add yourself under **Test users**.
3. **Credentials → Create credentials → OAuth client ID → Web application** (name "IronPulse web").
   Copy the **Client ID** and **Client secret**.
4. Get your debug SHA-1 (PowerShell):
   ```powershell
   & "$env:JAVA_HOME\bin\keytool.exe" -list -v -alias androiddebugkey -storepass android -keypass android -keystore "$env:USERPROFILE\.android\debug.keystore" | Select-String SHA1
   ```
5. **Create credentials → OAuth client ID → Android**: package name `com.ironpulse.ironpulse`,
   paste the SHA-1. (Add your release SHA-1 later too - Part E.)
6. Supabase → **Authentication → Sign In / Providers → Google** → enable.
   **Client IDs**: the *Web* client ID first, then a comma, then the *Android* client ID.
   **Client Secret**: the Web client secret. Save.

## Part C - put the public values in the app
In `C:\projects\Ironpulse` create `env.json` (copy of `env.example.json`) with your Project URL,
anon key and **Web** client ID. It is listed in `.gitignore`.
```powershell
cd C:\projects\Ironpulse
Copy-Item env.example.json env.json
notepad env.json
```
Run with:
```powershell
dart run tool/setup_android.dart
flutter run -d fd33a430 --dart-define-from-file=env.json
```
Test: Settings (person icon) → **Account & cloud backup** → Create account → code from email →
**Back up now** → Restore. Then try **Continue with Google**.

## Part D - automated checks (GitHub Actions)
Copy `ci/ci.yml` to `.github/workflows/ci.yml` in the IronpulseAi repo and push. Every push then runs
the AI server tests + dependency audit, Flutter analyze + all tests, a no-secrets check, and an APK build.

## Part E - release signing (Play Store / sharing the APK)
1. Create an upload key (keep the file and passwords safe - losing them blocks app updates):
   ```powershell
   & "$env:JAVA_HOME\bin\keytool.exe" -genkey -v -keystore "$env:USERPROFILE\ironpulse-upload.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `C:\projects\Ironpulse\android\key.properties` (never commit it):
   ```
   storePassword=YOUR-STORE-PASSWORD
   keyPassword=YOUR-KEY-PASSWORD
   keyAlias=upload
   storeFile=C:/Users/SaiNikhil Gandrakota/ironpulse-upload.jks
   ```
3. `dart run tool/setup_android.dart` (wires signing in), then
   ```powershell
   flutter build appbundle --dart-define-from-file=env.json   # for Google Play
   flutter build apk --split-per-abi --dart-define-from-file=env.json   # to share/install directly
   ```
4. Add the release key's SHA-1 to the Google **Android** OAuth client (and, after Play upload, the
   Play App Signing SHA-1 from Play Console → Setup → App signing).

## iOS (later)
Building for iPhone needs a Mac with Xcode, an Apple Developer account ($99/yr), an iOS OAuth client
in Google Cloud (bundle id `com.ironpulse.ironpulse`), HealthKit capability for wearables, and the
Supabase Google provider client-ID list extended with the iOS client ID ("Skip nonce check" may be
required on iOS). Alternatively use a cloud Mac build service (e.g. Codemagic). Not built or tested yet.
