import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

Color _priorityColor(String p) {
  switch (p) {
    case 'Critical':
      return kRed;
    case 'High':
      return kOrange;
    default:
      return kBlue;
  }
}

class TaskDetailsScreenV3 extends StatelessWidget {
  final AppTask task;
  const TaskDetailsScreenV3({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = store.tasks.firstWhere((x) => x.id == task.id, orElse: () => task);
    final customer = store.customers.firstWhere((c) => c.id == t.customerId, orElse: () => store.customers.first);
    final color = _priorityColor(t.priority);
    final isDone = t.status == TaskStatus.completed;
    final needsReview = isDone && t.type == TaskType.physicalVisit && !t.reviewedByRE;

    final events = customer.auditHistory.reversed
        .map((a) => TimelineEvent(icon: Icons.history, color: kMuted, title: a.type, subtitle: a.description, date: a.timestamp, tag: a.actor, tagColor: kBlue))
        .take(5)
        .toList();

    return RequestDetailScaffold(
      title: 'TASK DETAILS',
      subtitle: taskTypeLabel(t.type),
      bannerText: needsReview
          ? 'This visit outcome is awaiting RE review before the case can move forward.'
          : (isDone ? 'This task has been completed.' : (t.isOverdue ? 'This task is overdue — action is required.' : 'Task is on track — deadline ${DateFormat('dd MMM, hh:mm a').format(t.deadline)}.')),
      priorityLabel: isDone ? 'Completed' : (t.isOverdue ? 'Overdue' : '${t.priority} Priority'),
      color: isDone ? kGreen : (t.isOverdue ? kRed : color),
      bannerIcon: taskTypeIcon(t.type),
      actions: needsReview
          ? [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kBlue), foregroundColor: kBlue, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                icon: const Icon(Icons.person_outline, size: 16),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('View Customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.reviewPhysicalVisit(t.id);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Visit outcome reviewed.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not review: $e', isError: true);
                  }
                },
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Mark Reviewed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ),
            ]
          : (isDone
              ? const []
              : [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Take Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ),
                ]),
      children: [
        InfoCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 22, backgroundColor: avatarColorFor(customer.name).withOpacity(0.15), child: Text(initialsFor(customer.name), style: TextStyle(color: avatarColorFor(customer.name), fontWeight: FontWeight.bold))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                      child: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kBlue, decoration: TextDecoration.underline)),
                    ),
                    const SizedBox(height: 3),
                    Text('${customer.branch} Branch', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                    const SizedBox(height: 2),
                    CallablePhoneNumber(phoneNumber: customer.contactNumber, iconSize: 12, style: const TextStyle(fontSize: 10.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Outstanding', style: TextStyle(fontSize: 10, color: kMuted)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(customer.totalOutstanding), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kRed))),
                  Text('${customer.oldestOverdueDays} Days Overdue', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('TASK INFORMATION'),
        InfoCard(children: [
          KeyValueRow('Task Type', taskTypeLabel(t.type)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 118, child: Text('Assigned To', style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500))),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(store.salesmanDisplayName(t.ownerId),
                            textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => contactActions(context, store.salesmanPhone(t.ownerId)),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.call, size: 16, color: kBlue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          KeyValueRow('Priority', t.priority, valueColor: color),
          KeyValueRow('Status', t.status.name[0].toUpperCase() + t.status.name.substring(1)),
          KeyValueRow('Source', t.source),
          KeyValueRow('Deadline', DateFormat('dd MMM yyyy, hh:mm a').format(t.deadline), valueColor: (!isDone && t.isOverdue) ? kRed : kDark),
          if (t.approvalStatus == 'Pending') KeyValueRow('Extension Requested', t.pendingDeadline != null ? DateFormat('dd MMM yyyy').format(t.pendingDeadline!) : '-', valueColor: kAmber),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('TASK DESCRIPTION'),
        InfoCard(children: [Text(t.reason, style: const TextStyle(fontSize: 12.5, color: kDark))]),
        const SizedBox(height: 18),
        const SectionLabel('CUSTOMER ACTIVITY'),
        ActivityTimeline(events),
      ],
    );
  }

}
