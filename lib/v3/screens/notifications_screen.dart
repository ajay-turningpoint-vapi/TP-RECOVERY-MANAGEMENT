import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/notification_item.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/five_pm_control_screen.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Color _severityColor(NotificationSeverity s) {
    switch (s) {
      case NotificationSeverity.critical:
        return const Color(0xFFDC2626);
      case NotificationSeverity.warning:
        return const Color(0xFFEA580C);
      case NotificationSeverity.actionRequired:
        return const Color(0xFF2563EB);
      case NotificationSeverity.info:
        return const Color(0xFF64748B);
    }
  }

  String _severityLabel(NotificationSeverity s) {
    switch (s) {
      case NotificationSeverity.critical:
        return 'CRITICAL';
      case NotificationSeverity.warning:
        return 'WARNING';
      case NotificationSeverity.actionRequired:
        return 'ACTION REQUIRED';
      case NotificationSeverity.info:
        return 'INFO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = [...store.notifications]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _dark)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              try {
                await store.markAllNotificationsRead();
              } catch (e) {
                showAppMessageAfter(navigator, message: '$e', isError: true);
              }
            },
            child: const Text('Mark all read', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '5 PM Control history',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FivePmControlScreen())),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('No notifications.', style: TextStyle(color: _muted)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final list = ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                final n = items[i];
                final color = _severityColor(n.severity);
                return GestureDetector(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    try {
                      await store.markNotificationRead(n.id);
                    } catch (e) {
                      showAppMessageAfter(navigator, message: '$e', isError: true);
                    }
                    if (n.customerId != null) {
                      final c = store.customers.firstWhere((c) => c.id == n.customerId, orElse: () => store.customers.first);
                      navigator.push(MaterialPageRoute(builder: (_) => Customer360Screen(customer: c)));
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: n.read ? Colors.white : color.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: n.read ? _border : color.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text(_severityLabel(n.severity), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                                  ),
                                  const Spacer(),
                                  Text(DateFormat('dd MMM, hh:mm a').format(n.timestamp), style: const TextStyle(fontSize: 10, color: _muted)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                              const SizedBox(height: 2),
                              Text(n.body, style: const TextStyle(fontSize: 12, color: _muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                  },
                );
                if (constraints.maxWidth > 600) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: list,
                    ),
                  );
                }
                return list;
              },
            ),
    );
  }
}
