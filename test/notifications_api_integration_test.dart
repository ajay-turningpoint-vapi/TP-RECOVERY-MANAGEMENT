// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the notifications domain being migrated off BusySimulator:
// notifications are now populated only via _refreshNotificationsFromApi
// (loginWithApi), and markNotificationRead/markAllNotificationsRead are
// API-only. Server-side creation is async (BullMQ worker off an escalation
// raise — see notificationWorker.js), so this test polls via re-login
// until the notification lands rather than assuming it's instant.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/notification_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  Future<NotificationItem> waitForNotification(AppStore store, String username, bool Function(NotificationItem) predicate) async {
    for (var i = 0; i < 20; i++) {
      await store.loginWithApi(username, '1234');
      final match = store.notifications.where(predicate);
      if (match.isNotEmpty) return match.first;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Timed out waiting for notification to be delivered by the worker');
  }

  test('an RE escalation queues a real notification that the salesperson can read and mark as read via the API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.escalateCustomer('C3', 'L2', 'Test escalation for notifications', 'Call daily', 'mahesh', DateTime.now().add(const Duration(days: 1)));

    final salesperson = AppStore();
    final notification = await waitForNotification(salesperson, 'mahesh', (n) => n.customerId == 'C3' && !n.read);
    expect(notification.severity, NotificationSeverity.warning);

    await salesperson.markNotificationRead(notification.id);
    final after = salesperson.notifications.firstWhere((n) => n.id == notification.id);
    expect(after.read, isTrue);
  });

  test('mark-all-read clears unreadNotificationCount via the API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.escalateCustomer('C5', 'L1', 'Second test escalation', 'Plan', 'rahul', DateTime.now().add(const Duration(days: 1)));

    final salesperson = AppStore();
    await waitForNotification(salesperson, 'rahul', (n) => n.customerId == 'C5' && !n.read);
    expect(salesperson.unreadNotificationCount, greaterThan(0));

    await salesperson.markAllNotificationsRead();
    expect(salesperson.unreadNotificationCount, 0);
  });

  test('a user cannot mark another user\'s notification as read — real 403 surfaces as a catchable error', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.escalateCustomer('C4', 'L1', 'Third test escalation', 'Plan', 'rahul', DateTime.now().add(const Duration(days: 1)));

    final rahul = AppStore();
    final notification = await waitForNotification(rahul, 'rahul', (n) => n.customerId == 'C4' && !n.read);

    final mahesh = AppStore();
    await mahesh.loginWithApi('mahesh', '1234');
    expect(() => mahesh.markNotificationRead(notification.id), throwsA(anything));
  });
}
