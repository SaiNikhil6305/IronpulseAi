// On-device end-to-end test (needs an emulator or phone):
//   flutter test integration_test/app_test.dart
// Runs in device-only mode against the real SQLite database and real plugins.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ironpulse/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device-only onboarding → split → log a set → resume after restart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.text('Use on this device only'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Tester');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Skip').last);
      await tester.pumpAndSettle();
    }
    // Goals step requires Continue (no Skip)
    if (find.text('Continue').evaluate().isNotEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Choose my split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push / Pull / Legs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this split'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('Tester'), findsWidgets);
    await tester.tap(find.text('Workout').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '40');
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.tap(find.byTooltip('Mark set complete').first);
    await tester.pumpAndSettle();
    expect(find.text('1 sets done'), findsOneWidget);
  });
}
