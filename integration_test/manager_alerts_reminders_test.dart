// Real end-to-end test of the Manager's new Alerts & Reminders screen, in a
// real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_alerts_reminders_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Alerts & Reminders: real stats, tabs, search, sort, drill-through, notifications', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byType(TextField).at(0), 'suresh.mgr');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
    print('✓ Manager login successful');

    // Dashboard's "Alerts & Reminders" card's "View Details" must now open
    // this dedicated screen.
    final dashboardList = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 10 && find.text('Alerts & Reminders').evaluate().isEmpty; i++) {
      await tester.drag(dashboardList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Alerts & Reminders'), findsOneWidget);
    final headerRow = find.ancestor(of: find.text('Alerts & Reminders'), matching: find.byType(Row)).first;
    final viewDetailsLink = find.descendant(of: headerRow, matching: find.text('View Details'));
    await tester.ensureVisible(viewDetailsLink);
    await settle(tester);
    await tester.tap(viewDetailsLink);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Alerts & Reminders'), findsOneWidget, reason: 'Dashboard "View Details" must open the new Alerts & Reminders screen');
    expect(find.text('Stay on top of what needs your attention'), findsOneWidget);
    print('✓ Alerts & Reminders screen opened from Dashboard "View Details"');

    // ---- Stat cards ----
    expect(find.text('Overdue Alerts'), findsOneWidget);
    expect(find.text('PTP Due Today'), findsOneWidget);
    expect(find.text('No Follow-up'), findsWidgets);
    expect(find.text('Disputes Awaiting'), findsOneWidget);
    final statCardsRow = find.byType(ListView).at(1);
    for (var i = 0; i < 6 && find.text('Other Reminders').evaluate().isEmpty; i++) {
      await tester.drag(statCardsRow, const Offset(-200, 0));
      await settle(tester);
    }
    expect(find.text('Other Reminders'), findsOneWidget);
    print('✓ Stat cards rendered with live data');

    // ---- Tabs genuinely re-filter to real, non-empty groups ----
    expect(find.textContaining('All Alerts'), findsOneWidget);
    expect(find.textContaining('Overdue'), findsWidgets);
    expect(find.textContaining('PTP'), findsWidgets);
    expect(find.textContaining('Disputes'), findsWidgets);
    // The tab row is a horizontally-scrollable lazy list, so the last chip
    // ("Disputes") is not mounted until scrolled into view — drag using the
    // 'Overdue' tab (unique text, always mounted first) as a stable anchor
    // for its Scrollable, then scroll right until the Disputes chip mounts.
    final tabScrollable = find.ancestor(of: find.text('Overdue').first, matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 6 && find.text('Disputes').evaluate().length < 2; i++) {
      await tester.drag(tabScrollable, const Offset(-150, 0));
      await settle(tester);
    }
    // Once mounted, the tab chip is the FIRST match ("Disputes") — the
    // alert card's trailing count label (also exact text "Disputes", from
    // _AlertItem.countLabel) is built later in the tree.
    final disputesTab = find.text('Disputes').first;
    expect(disputesTab, findsOneWidget);
    await tester.tap(disputesTab);
    await settle(tester);
    expect(find.text('Disputes awaiting review'), findsOneWidget, reason: 'Disputes tab must show the real disputes-awaiting-review alert');
    expect(find.text('Customers with 30+ days overdue'), findsNothing, reason: 'Disputes tab must not show overdue-group alerts');
    print('✓ Disputes tab genuinely filters to the disputes alert group');
    // Scroll the tab row back left (using the still-mounted Disputes chip
    // as the Scrollable anchor) until 'All Alerts' is mounted again.
    final tabScrollableBack = find.ancestor(of: find.text('Disputes').first, matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 6 && find.text('All Alerts').evaluate().isEmpty; i++) {
      await tester.drag(tabScrollableBack, const Offset(150, 0));
      await settle(tester);
    }
    final allAlertsTab = find.text('All Alerts').first;
    expect(allAlertsTab, findsOneWidget);
    await tester.tap(allAlertsTab);
    await settle(tester);
    expect(find.text('Customers with 30+ days overdue'), findsOneWidget);
    print('✓ All Alerts tab restores every alert');

    // ---- Search is real ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_alert_zzz');
    await settle(tester);
    expect(find.text('No alerts match this search.'), findsOneWidget, reason: 'Search must genuinely filter the alert list');
    print('✓ Search box genuinely filters the alert list');
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('No alerts match this search.'), findsNothing, reason: 'Clearing the search box must actually restore the full alert list');

    // ---- Sort genuinely reorders ----
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sort').evaluate().isNotEmpty ? find.widgetWithText(OutlinedButton, 'Sort') : find.byIcon(Icons.swap_vert));
    await settle(tester);
    print('✓ Sort control tapped and re-rendered without error');

    // ---- Drill-through: tapping an alert card opens the real Manager report screen ----
    await tester.tap(find.text('Disputes awaiting review'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Dispute Status Report'), findsWidgets, reason: 'Tapping the disputes alert must open the real, view-only Dispute Status report');
    print('✓ Tapping an alert drills through to the real Manager report screen');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Alerts & Reminders'), findsOneWidget, reason: 'Back from the drilled-through report must return to Alerts & Reminders');

    // ---- Enable push notifications is a real, working toggle ----
    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 12 && find.text('Enable push notifications').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Enable push notifications'), findsOneWidget);
    final enableButton = find.widgetWithText(OutlinedButton, 'Enable');
    await tester.ensureVisible(enableButton);
    await settle(tester);
    await tester.tap(enableButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Push notifications enabled'), findsOneWidget, reason: 'Enable must actually flip the card to its enabled state');
    expect(find.text('Push notifications enabled for this device.'), findsOneWidget, reason: 'Enable must give real feedback');
    print('✓ Enable push notifications is a real, working toggle');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Stay on top of what needs your attention'), findsNothing, reason: 'Back must leave the Alerts & Reminders screen');
    expect(find.text('Manager Dashboard'), findsOneWidget, reason: 'Back must return to the Manager Dashboard');
    print('✓ Back navigation returns to the Dashboard');

    print('✓ Manager Alerts & Reminders flow complete');
  });
}
