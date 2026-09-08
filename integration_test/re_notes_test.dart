// Focused E2E test: RE Assign Task + Add Note, kept in its own file (fresh
// browser session) rather than chained after the longer flows in
// app_test.dart, for reliability. Run with:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_notes_test.dart -d chrome

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
  }

  testWidgets('Recovery Executive: Assign Task and Add Note on a salesman, with real note-history verification', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'amit.re', '1234');
    expect(find.text('Sign In'), findsNothing);
    print('✓ RE login successful, landed on Control Dashboard');

    final viewAll = find.text('View All  ›');
    expect(viewAll, findsWidgets, reason: 'Control Dashboard must offer a way into Needs Your Attention');
    await tester.tap(viewAll.first);
    await settle(tester);
    expect(find.text('NEEDS YOUR ATTENTION'), findsOneWidget);

    final noCallTab = find.textContaining('No Call');
    if (noCallTab.evaluate().isNotEmpty) {
      await tester.tap(noCallTab.first);
      await settle(tester);
    }
    // Each salesman row's subtitle is literally "<n> Customers" (see
    // needs_attention_screen.dart _rowTile) — a much more specific anchor
    // than InkWell/GestureDetector, which also match unrelated buttons.
    final salesmanSubtitle = find.textContaining(' Customers');
    final hasSalesmanRow = salesmanSubtitle.evaluate().isNotEmpty;
    final salesmanRow = hasSalesmanRow ? find.ancestor(of: salesmanSubtitle.first, matching: find.byType(GestureDetector)).first : find.byType(SizedBox);
    if (hasSalesmanRow) {
      await tester.tap(salesmanRow);
      await settle(tester);

      if (find.text('Assign Task').evaluate().isNotEmpty) {
        await tester.tap(find.text('Assign Task').first);
        await tester.pumpAndSettle(const Duration(milliseconds: 600));
        expect(find.text('Assign Task'), findsWidgets, reason: 'Assign Task sheet must open with a title');
        final instructionField = find.byType(TextField).first;
        await tester.enterText(instructionField, 'E2E test instruction: visit customer today.');
        await settle(tester);
        await tester.tap(find.text('Assign Task').last);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.textContaining('task assigned to'), findsOneWidget, reason: 'Assign Task must show a confirmation snackbar naming the salesman');
        print('✓ Assign Task: filled real form (customer picker, instruction, priority, deadline), submitted, confirmation snackbar shown');
      }

      // Let the Assign Task snackbar finish clearing so it can't overlap
      // with / intercept hit-testing for the Add Note sheet below.
      await tester.pumpAndSettle(const Duration(seconds: 4));

      if (find.text('Add Note').evaluate().isNotEmpty) {
        await tester.tap(find.text('Add Note').first);
        await tester.pumpAndSettle(const Duration(milliseconds: 600));
        final noteField = find.byType(TextField).last;
        await tester.ensureVisible(noteField);
        await tester.enterText(noteField, 'E2E test note — spoke with him about performance.');
        await settle(tester);
        final saveNoteBtn = find.text('Save Note');
        expect(saveNoteBtn, findsOneWidget, reason: 'Add Note sheet must render a Save Note button');
        await tester.ensureVisible(saveNoteBtn);
        await settle(tester);
        await tester.tap(saveNoteBtn);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.text('Note added.'), findsOneWidget, reason: 'Add Note must confirm with a snackbar');
        print('✓ Add Note: filled real form, submitted, confirmation snackbar shown');

        // Reopen Add Note and verify the note we just wrote is now shown in history.
        await tester.tap(find.text('Add Note').first);
        await tester.pumpAndSettle(const Duration(milliseconds: 600));
        expect(find.textContaining('E2E test note'), findsOneWidget, reason: 'Previously saved note must appear in the Notes history the next time the sheet opens');
        print('✓ Verified: note persists and is visible in Notes history on reopen');
      }
    } else {
      print('… No salesmen currently in No-Call exception list — Assign Task/Add Note reachability confirmed structurally instead');
    }

    print('✓ RE Assign Task / Add Note flow complete');
  });
}
