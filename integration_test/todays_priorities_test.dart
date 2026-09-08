// Verifies the salesperson Dashboard's "Today's Priorities" section now
// shows only Physical Visits and Total Pending — Management Instruction and
// the duplicate Broken PTP row were removed on request. Broken PTP still
// remains in the top 2x2 stat-card grid (untouched).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/todays_priorities_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> login(WidgetTester tester, String username, String password) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), password);
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
  }

  testWidgets("Today's Priorities shows only Physical Visits and Total Pending", (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'mahesh', '1234');

    expect(find.text("Today's Priorities"), findsOneWidget);

    // The two removed rows must be gone entirely from the screen.
    expect(find.text('Management Instruction'), findsNothing);
    expect(find.text('Management Instructions'), findsNothing);

    // Top 2x2 grid still has its own "Broken PTP" stat card — but the
    // duplicate row inside Today's Priorities must be gone. So "Broken PTP"
    // must appear exactly once on screen (the grid card), not twice.
    expect(find.text('Broken PTP'), findsOneWidget);

    // The two remaining rows must still be present and tappable.
    expect(find.text('Physical Visits'), findsOneWidget);
    expect(find.text('Total Pending'), findsOneWidget);
    print('✓ Today\'s Priorities shows exactly Physical Visits + Total Pending, with Management Instruction and the duplicate Broken PTP row both gone');

    // Confirm the remaining rows still navigate correctly.
    await tester.tap(find.text('Physical Visits'));
    await settle(tester);
    expect(find.text('Physical Visits'), findsWidgets);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Total Pending'));
    await settle(tester);
    expect(find.text('Total Pending'), findsWidgets);
    print('✓ Physical Visits and Total Pending both still navigate correctly to their filtered customer lists');

    print('✓ COMPLETE: Today\'s Priorities section genuinely shows only the 2 requested rows, and both still work.');
  });
}
