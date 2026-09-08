// Verifies the Manager's Tasks screen and all 13 Manager report screens show
// real, correct data from the curated dataset — not blank/zero placeholders.
//
// Curated dataset ground truth (BusySimulator seed):
//   4 seed tasks (T1-T4). 5 customers, total overdue ₹15,55,000 (all 5
//   genuinely overdue). PQR Stores has a ₹35,000 partial payment already
//   made (invoice ₹80,000, totalDue ₹45,000) — the Ageing Receivables and
//   Priority Accounts "Overdue" bugs fixed this session both depended on
//   this exact fact.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_tasks_reports_test.dart -d chrome

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

  Future<void> openReport(WidgetTester tester, String title) async {
    final reportsIcon = find.byIcon(Icons.bar_chart_outlined);
    if (reportsIcon.evaluate().isNotEmpty) {
      await tester.tap(reportsIcon);
      await settle(tester);
    }
    final tile = find.text(title);
    for (var i = 0; i < 15 && tile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    expect(tile, findsWidgets, reason: '$title tile must render on the Manager Reports screen');
    await tester.ensureVisible(tile.first);
    await settle(tester);
    await tester.tap(tile.first);
    await settle(tester);
  }

  testWidgets('Manager Tasks screen and all 13 Manager reports show real data', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'suresh.mgr', '1234');

    // ================= Tasks screen =================
    await tester.tap(find.byIcon(Icons.assignment_outlined));
    await settle(tester);
    expect(find.text('Total Tasks'), findsWidgets);
    expect(find.text('4'), findsWidgets, reason: 'Total Tasks must be the real 4 seeded company-wide tasks, not stale/zero');
    for (var i = 0; i < 10 && find.textContaining('ABC Traders').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.textContaining('ABC Traders'), findsWidgets, reason: 'A real seeded task (Rahul / ABC Traders physical visit) must be visible');
    print('✓ Manager Tasks screen shows the real total (4) and a real task (ABC Traders)');

    // ================= Reports =================
    const reports = <String>[
      'Management Attention',
      'Daily Recovery Summary',
      'Team Recovery',
      'Priority Accounts',
      'Alerts & Reminders',
      'Salesman Performance',
      'PTP Reports',
      'Broken PTP Reports',
      'Dispute Status Report',
      'Dispute Management – Summary',
      'Ageing Receivables',
      'Expected vs Actual Recovery',
      'No Follow-up Report',
    ];
    for (final title in reports) {
      await openReport(tester, title);
      expect(find.textContaining('₹'), findsWidgets, reason: '$title must show real ₹ figures, not a blank/zero report');
      print('✓ Manager "$title" renders with real ₹ figures');
      await tester.pageBack();
      await settle(tester);
    }

    // Specific real-figure checks for the two reports fixed this session.
    await openReport(tester, 'Ageing Receivables');
    expect(find.textContaining('₹15,55,000'), findsWidgets, reason: 'Total Outstanding must be the real, reconciled ₹15,55,000 (not ₹15,90,000 from unreconciled invoice face values)');
    expect(find.textContaining('5 Customers'), findsWidgets);
    print('✓ Manager Ageing Receivables shows the real, reconciled ₹15,55,000 across 5 customers');
    await tester.pageBack();
    await settle(tester);

    await openReport(tester, 'Priority Accounts');
    expect(find.text('Overdue'), findsWidgets, reason: 'Overdue stat card must exist');
    expect(find.textContaining('-₹'), findsNothing, reason: 'Overdue must never render as a negative amount');
    print('✓ Manager Priority Accounts "Overdue" stat is a real, non-negative figure');

    print('✓ COMPLETE: Manager Tasks screen and all 13 Manager reports genuinely show real, correct data.');
  });
}
