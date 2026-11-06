# iOS build

**Status: configured but not built.** iOS binaries require macOS + Xcode, which were not available. No iOS
build has been produced or tested.

## Requirements

* macOS with Xcode (current stable, iOS deployment target 15.0) and CocoaPods
* Apple Developer Program membership for device installs, TestFlight and the App Store
* Bundle ID: `com.ironpulse.app` (set in `ios/Runner.xcodeproj`)

## Configure

1. `ios/Flutter/Google.xcconfig`: set `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` (AUTH_SETUP.md).
   `Info.plist` already contains the URL types (`com.ironpulse.app` for auth links, reversed client id for Google),
   `GIDClientID`, and camera / photo-library / HealthKit usage descriptions.
2. Xcode → Runner → Signing & Capabilities: choose your team; add **HealthKit** capability (needed for Apple
   Health import) and enable "Background Delivery" only if you later add it (not used now).
3. Push notifications are not used (reminders are local), so no APNs setup is needed.

## Build

```bash
flutter pub get && cd ios && pod install && cd ..
flutter build ipa --release --dart-define-from-file=config/app_config.json
```
Upload `build/ios/ipa/*.ipa` with Xcode Organizer or Transporter.

## Without a Mac

Cloud options: Codemagic, GitHub Actions `macos-latest` runners (add a job running `flutter build ipa` with
signing certificates stored as secrets), or Bitrise.

## App Store notes

* App Privacy labels: Health & Fitness, Contact info (email), Photos (optional, user content), User content
  (AI chats) — linked to the user, not used for tracking.
* HealthKit data must not be used for advertising or sold; IronPulse reads only and stores per-user.
* Sign in with Apple: Apple requires it when an app offers third-party sign-in (Google) unless an exemption
  applies — **planned, not implemented**; add before App Store submission.
