// Configures the Android project for IronPulse reminders. Safe to run more than once.
// Usage (from the project folder):  dart run tool/setup_android.dart
import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (!manifest.existsSync() || (!kts.existsSync() && !groovy.existsSync())) {
    stderr.writeln('Run this from the IronPulse project folder (the one with pubspec.yaml and android/).');
    exit(1);
  }

  // ---- AndroidManifest.xml ----
  var m = manifest.readAsStringSync();
  const perms = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
    'android.permission.INTERNET',
    'android.permission.health.READ_STEPS',
    'android.permission.health.READ_HEART_RATE',
    'android.permission.health.READ_RESTING_HEART_RATE',
    'android.permission.health.READ_SLEEP',
  ];
  final missing = perms.where((p) => !m.contains(p)).toList();
  if (missing.isNotEmpty) {
    final tag = RegExp(r'<manifest[^>]*>').firstMatch(m)!;
    final lines = missing.map((p) => '\n    <uses-permission android:name="$p"/>').join();
    m = m.replaceRange(tag.end, tag.end, lines);
  }

  const receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
''';
  if (!m.contains('ScheduledNotificationReceiver')) {
    m = m.replaceFirst('</application>', '$receivers    </application>');
  }
  m = m.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="IronPulse"');
  // ---- Health Connect: detect the app, show our rationale, Android 14 permission-usage link ----
  if (!m.contains('com.google.android.apps.healthdata')) {
    const q = '''
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
        <intent>
            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
        </intent>
    </queries>''';
    final appStart = m.indexOf('<application');
    m = m.replaceRange(appStart, appStart, '${q.trim()}\n    ');
  }
  // Intent filter on MainActivity so Health Connect can show why IronPulse asks for access.
  if (!m.contains('<!-- ironpulse:health-rationale -->')) {
    final actStart = m.indexOf(RegExp(r'<activity[^>]*\.MainActivity'));
    final actEnd = actStart < 0 ? -1 : m.indexOf('</activity>', actStart);
    if (actEnd > 0) {
      m = m.replaceRange(actEnd, actEnd, '''    <!-- ironpulse:health-rationale -->
            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
            </intent-filter>
        ''');
    }
  }
  if (!m.contains('ViewPermissionUsageActivity')) {
    m = m.replaceFirst('</application>', '''        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity=".MainActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
            </intent-filter>
        </activity-alias>
    </application>''');
  }
  // Plain HTTP is allowed ONLY to this phone itself (127.0.0.1 / localhost), which is how the
  // IronPulse AI server is reached over USB via "adb reverse". Everything else must use HTTPS.
  if (!m.contains('networkSecurityConfig')) {
    m = m.replaceFirst('<application', '<application\n        android:networkSecurityConfig="@xml/network_security_config"');
  }
  final xml = File('android/app/src/main/res/xml/network_security_config.xml');
  xml.parent.createSync(recursive: true);
  xml.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
''');
  manifest.writeAsStringSync(m);
  stdout.writeln('✓ AndroidManifest.xml: permissions, reminder receivers, app name, USB-only HTTP rule');

  // ---- Gradle: core library desugaring (required by flutter_local_notifications) ----
  if (kts.existsSync()) {
    var g = kts.readAsStringSync();
    if (!g.contains('isCoreLibraryDesugaringEnabled')) {
      g = g.replaceFirst('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
    }
    if (!g.contains('desugar_jdk_libs')) {
      g = '${g.trimRight()}\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n';
    }
    kts.writeAsStringSync(g);
    stdout.writeln('✓ build.gradle.kts: desugaring enabled');
  } else {
    var g = groovy.readAsStringSync();
    if (!g.contains('coreLibraryDesugaringEnabled')) {
      if (g.contains('compileOptions {')) {
        g = g.replaceFirst('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true');
      } else {
        g = g.replaceFirst('android {', 'android {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }');
      }
    }
    if (!g.contains('desugar_jdk_libs')) {
      g = '${g.trimRight()}\n\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n';
    }
    groovy.writeAsStringSync(g);
    stdout.writeln('✓ build.gradle: desugaring enabled');
  }
  // ---- Health Connect needs FlutterFragmentActivity (permission screen) and Android 8.0+ ----
  final kotlinDir = Directory('android/app/src/main/kotlin');
  if (kotlinDir.existsSync()) {
    for (final f in kotlinDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('MainActivity.kt'))) {
      var k = f.readAsStringSync();
      if (!k.contains('FlutterFragmentActivity')) {
        k = k
            .replaceAll('io.flutter.embedding.android.FlutterActivity', 'io.flutter.embedding.android.FlutterFragmentActivity')
            .replaceAll(': FlutterActivity()', ': FlutterFragmentActivity()');
        f.writeAsStringSync(k);
      }
      stdout.writeln('✓ MainActivity uses FlutterFragmentActivity');
    }
  }
  for (final gf in [kts, groovy].where((f) => f.existsSync())) {
    var g = gf.readAsStringSync();
    g = g.replaceFirst(RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'), 'minSdk = 26');
    g = g.replaceFirst(RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'), 'minSdkVersion 26');
    gf.writeAsStringSync(g);
  }
  stdout.writeln('✓ minSdk 26 (Android 8.0+, required by Health Connect)');
  // ---- Release signing: uses android/key.properties if it exists (never committed) ----
  if (kts.existsSync()) {
    var g = kts.readAsStringSync();
    if (!g.contains('ironpulse:release-signing')) {
      // Imports go first; the properties block must come after plugins {} (Gradle rule), so it goes before android {}.
      g = '// ironpulse:release-signing\nimport java.util.Properties\nimport java.io.FileInputStream\n\n' + g;
      g = g.replaceFirst(RegExp(r'^android\s*\{', multiLine: true), '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {''');
      g = g.replaceFirst(RegExp(r'buildTypes\s*\{'), '''signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {''');
      g = g.replaceFirst('signingConfig = signingConfigs.getByName("debug")',
          'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")');
      kts.writeAsStringSync(g);
    }
    stdout.writeln('✓ Release signing reads android/key.properties when present');
  }
  stdout.writeln('Done. Now run: flutter run');
}
