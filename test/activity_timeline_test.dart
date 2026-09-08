// Verifies the shared ActivityTimeline widget (lib/v3/screens/
// request_detail_scaffold.dart), used across Task Details, Dispute Review,
// Visit Review, and RE's Unified Task Detail screens, genuinely renders a
// real date AND time for every history entry — not just the description
// and actor. TimelineEvent always carried a `date` field, but the widget
// previously never rendered it anywhere.
//
// A direct widget test (rather than a full app E2E test) is used here
// deliberately: this is a pure "does this widget render this string" check
// with no store/navigation involvement, and is both faster and immune to
// the flutter_test ListView-scrolling/Scrollable-targeting flakiness seen
// when reaching this same widget through several layers of app navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';

void main() {
  testWidgets('ActivityTimeline renders a real formatted date and time for every event', (tester) async {
    final event = TimelineEvent(
      icon: Icons.history,
      color: Colors.blue,
      title: 'RE_APPROVED_TASK_EDIT',
      subtitle: 'Ramesh Kumar approved the task extension.',
      date: DateTime(2026, 8, 24, 15, 45),
      tag: 'Ramesh Kumar',
      tagColor: Colors.blue,
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActivityTimeline([event]))));

    expect(find.text('RE_APPROVED_TASK_EDIT'), findsOneWidget);
    expect(find.text('Ramesh Kumar approved the task extension.'), findsOneWidget);
    expect(find.text(DateFormat('dd MMM yyyy, hh:mm a').format(event.date)), findsOneWidget, reason: 'The event date/time must be genuinely rendered on screen, not just carried as unused data');
  });

  testWidgets('ActivityTimeline renders a distinct date/time for each of multiple events', (tester) async {
    final events = [
      TimelineEvent(icon: Icons.history, color: Colors.blue, title: 'RE_APPROVED_DISPUTE', date: DateTime(2026, 8, 20, 9, 5), tag: 'RE', tagColor: Colors.blue),
      TimelineEvent(icon: Icons.history, color: Colors.green, title: 'PAYMENT_CLAIM_VERIFIED', date: DateTime(2026, 8, 22, 18, 30), tag: 'RE', tagColor: Colors.green),
    ];

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActivityTimeline(events))));

    expect(find.text('20 Aug 2026, 09:05 AM'), findsOneWidget);
    expect(find.text('22 Aug 2026, 06:30 PM'), findsOneWidget);
  });
}
