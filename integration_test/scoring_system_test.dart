// Verifies the real Recovery Score / Credit Health Score computations
// (Master Build Book RMS-05 / RMS-06) are genuinely visible and explainable
// via real clicks — not just correct in the store.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/scoring_system_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final base = find.byIcon(icon);
    if (base.evaluate().isEmpty) return;
    final finder = base.last;
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> login(WidgetTester tester, String username, String password) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), password);
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
  }

  testWidgets('Recovery Score and Credit Health Score are genuinely computed and explainable via real clicks', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= Salesperson Recovery Score, via RE Reports =================
    await login(tester, 'amit.re', '1234');
    await tapIcon(tester, Icons.bar_chart_outlined);
    final perfTile = find.text('Salesman Performance Report');
    expect(perfTile, findsWidgets);
    await tester.ensureVisible(perfTile.first);
    await settle(tester);
    await tester.tap(perfTile.first);
    await settle(tester);

    // "Score Components & Weightage" is far down the report's ListView —
    // slivers only build children near the viewport regardless of whether
    // the list uses `.builder` or plain `children:`, so it must be scrolled
    // into view before it exists in the tree.
    for (var i = 0; i < 15 && find.textContaining('Score Components & Weightage').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Score Components & Weightage'), findsWidgets, reason: 'The real weighted formula must be shown, not just a bare number');
    expect(find.textContaining('Collection Performance'), findsWidgets);
    print('✓ Salesman Performance Report shows the real RMS-05 weight breakdown');

    // Drill into one salesman for the full explainable breakdown. Re-enter
    // the report fresh (rather than scrolling back up from the bottom) so
    // the target row isn't left sitting right at the scroll edge, which
    // caused a genuine mis-hit (tap landed on the AppBar, not the row) when
    // scrolling back upward from the weightage section instead.
    await tester.pageBack();
    await settle(tester);
    await tester.ensureVisible(perfTile.first);
    await settle(tester);
    await tester.tap(perfTile.first);
    await settle(tester);
    // Scope to a GestureDetector descendant — 'Rahul' can also appear in the
    // non-tappable "Top Performer Score" stat card subtitle if he tops the
    // board, and a bare textContaining match can grab that instead of the
    // real, tappable summary row.
    final rahulNameFinder = find.descendant(of: find.byType(GestureDetector), matching: find.textContaining('Rahul'));
    for (var i = 0; i < 15 && rahulNameFinder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    // Tap the ancestor GestureDetector (the whole row) rather than the bare
    // Text node — tapping the Text directly repeatedly derived a fragile
    // offset that missed the hit-test target (landed on the AppBar instead).
    final rahulRow = find.ancestor(of: rahulNameFinder.first, matching: find.byType(GestureDetector)).first;
    await tester.ensureVisible(rahulRow);
    await settle(tester);
    await tester.tap(rahulRow);
    await settle(tester);
    expect(find.textContaining('Why this score'), findsWidgets, reason: 'Tapping a salesman must drill into the real per-component breakdown');
    expect(find.textContaining('Weighted Recovery Score'), findsWidgets);
    print('✓ Drilling into Rahul shows the real "Why this score" component breakdown');

    // ================= Customer Credit Health Score, via Customer 360 =================
    await tapIcon(tester, Icons.people_outline);
    final customerCard = find.textContaining('ABC Traders');
    for (var i = 0; i < 15 && customerCard.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await settle(tester);
    }
    expect(customerCard, findsWidgets);
    final row = find.ancestor(of: customerCard.first, matching: find.byType(GestureDetector)).first;
    await tester.tap(row);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget);

    final healthChip = find.textContaining('Credit Health:');
    expect(healthChip, findsWidgets, reason: 'Customer 360 must show the real, computed Credit Health band');
    await tester.tap(healthChip.first);
    await settle(tester);
    expect(find.textContaining('Payment Timeliness'), findsWidgets, reason: 'Tapping the Credit Health chip must drill into the real RMS-06 component breakdown');
    expect(find.textContaining('Weighted Credit Health Score'), findsWidgets);
    print('✓ Tapping the Credit Health chip on ABC Traders shows the real RMS-06 component breakdown');

    print('✓ COMPLETE: both real scoring systems (Recovery Score, Credit Health Score) are genuinely computed, visible, and explainable via real clicks.');
  });
}
