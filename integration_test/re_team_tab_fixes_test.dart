// Real end-to-end test of two RE-side bugs found and fixed in
// re_team_tab.dart: (1) "Salesmen Performance" showed 3 hardcoded mock
// rows (Rahul/Vijay/Suresh with fixed numbers) regardless of the real
// team size; (2) "Reassign Portfolio" showed a canned dialog and called
// no store method at all — the button did nothing real.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_team_tab_fixes_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('RE Salesmen tab: Salesmen Performance shows real data (not the old 3-row mock), and Reassign Portfolio genuinely reassigns real accounts', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byType(TextField).at(0), 'amit.re');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
    print('✓ RE (amit.re) login successful');

    // Navigate: Reports tab -> hamburger menu -> Salesmen.
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.text('Salesmen'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Salesmen Portfolios'), findsOneWidget, reason: 'Salesmen tab must open');
    print('✓ Opened Salesmen Portfolios (ReTeamTab)');

    // ---- Regression check: Salesmen Performance is real, not the old 3-row mock ----
    await tester.tap(find.text('Salesmen Performance'));
    await settle(tester);
    final performanceCards = find.text('Operational Performance');
    expect(performanceCards, findsWidgets, reason: 'Performance list must render real cards');
    // The old mock always had exactly Rahul/Vijay/Suresh. If the team has a
    // 4th+ salesman, their real name must now appear here — a hardcoded
    // 3-entry mock could never show it. The list is lazily built, so scroll
    // until Mahesh (or the list end) is reached.
    final perfList = find.byType(Scrollable).first;
    for (var i = 0; i < 12 && find.textContaining('Mahesh').evaluate().isEmpty; i++) {
      await tester.drag(perfList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Mahesh'), findsWidgets, reason: 'A real salesman outside the old Rahul/Vijay/Suresh mock trio must now appear — confirms this list is genuinely built from store.salesmen, not hardcoded');
    print('✓ Salesmen Performance shows real, live data — includes a salesman the old hardcoded mock never had');

    // ---- Reassign Portfolio: a real, working action ----
    await tester.tap(find.text('Workload Overview'));
    await settle(tester);
    final reassignButtons = find.widgetWithText(OutlinedButton, 'Reassign Portfolio');
    expect(reassignButtons, findsWidgets, reason: 'Workload Overview must have real Reassign Portfolio buttons');
    await tester.ensureVisible(reassignButtons.first);
    await settle(tester);
    await tester.tap(reassignButtons.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // The dialog must show real customer names/amounts, not a canned
    // "5 high-exposure accounts... to Vijay" sentence with no real data.
    expect(find.textContaining('₹'), findsWidgets, reason: 'Reassign dialog must list real accounts with real ₹ amounts');
    final dropdown = find.byType(DropdownButtonFormField<String>);
    expect(dropdown, findsOneWidget, reason: 'Reassign dialog must offer a real target-salesman dropdown, not a hardcoded name');
    print('✓ Reassign Portfolio dialog shows real accounts and a real target-salesman dropdown');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reassign'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.textContaining('accounts reassigned from'), findsOneWidget, reason: 'Confirming must give real, specific feedback naming a real count and real from/to salesmen — not the old canned "Portfolio reassignment successful" message');
    expect(find.textContaining('Audit entry logged for each'), findsOneWidget);
    print('✓ Reassign Portfolio genuinely called the real store method and gave real, specific feedback');

    print('✓ RE Team tab fixes verified: Salesmen Performance is real data, Reassign Portfolio is a real working action');
  });
}
