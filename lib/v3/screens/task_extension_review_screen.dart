import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

const _amber = Color(0xFFB45309);

class TaskExtensionReviewScreen extends StatelessWidget {
  final String taskId;
  const TaskExtensionReviewScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = store.tasks.firstWhere((t) => t.id == taskId, orElse: () => store.tasks.first);
    final customer = store.customers.firstWhere((c) => c.id == t.customerId, orElse: () => store.customers.first);
    final isPending = t.approvalStatus == 'Pending';

    return RequestDetailScaffold(
      title: 'TASK EXTENSION',
      subtitle: 'Deadline Change Awaiting Review',
      bannerText: isPending ? 'Salesperson requested a task deadline extension.' : 'This request is ${t.approvalStatus}.',
      priorityLabel: isPending ? 'Needs Decision' : (t.approvalStatus ?? '-'),
      color: _amber,
      bannerIcon: Icons.schedule,
      actions: isPending
          ? [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kRed), foregroundColor: kRed, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.rejectTaskEdit(t.id);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Extension request rejected. Original deadline stands.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
                  }
                },
                child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.approveTaskEdit(t.id);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Extension approved. Deadline updated.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
                  }
                },
                child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]
          : [],
      children: [
        InfoCard(children: [
          Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: avatarColorFor(customer.name).withOpacity(0.15), child: Text(initialsFor(customer.name), style: TextStyle(color: avatarColorFor(customer.name), fontSize: 15, fontWeight: FontWeight.bold))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                      child: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kBlue, decoration: TextDecoration.underline)),
                    ),
                    const SizedBox(height: 4),
                    Text('${taskTypeLabel(t.type)} · Owner: ${store.salesmanDisplayName(t.ownerId)}', style: const TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('AUTHORITATIVE DEADLINE (until approved)'),
        InfoCard(children: [
          KeyValueRow('Current Deadline', DateFormat('dd MMM yyyy, hh:mm a').format(t.deadline)),
          KeyValueRow('Priority', t.priority),
          KeyValueRow('Reason', t.reason),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('REQUESTED CHANGE'),
        InfoCard(children: [
          KeyValueRow('New Deadline', t.pendingDeadline != null ? DateFormat('dd MMM yyyy, hh:mm a').format(t.pendingDeadline!) : '-', valueColor: _amber),
          KeyValueRow('New Priority', t.pendingPriority ?? t.priority, valueColor: _amber),
          KeyValueRow('Reason for Change', t.pendingReason ?? '-'),
        ]),
        const SizedBox(height: 18),
        AttachmentsSection(refId: taskId),
        const SizedBox(height: 18),
        NotesSection(refId: taskId),
      ],
    );
  }
}
