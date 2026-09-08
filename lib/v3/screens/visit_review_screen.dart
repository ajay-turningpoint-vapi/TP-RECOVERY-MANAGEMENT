import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _purple = Color(0xFF7C3AED);

class VisitReviewScreen extends StatelessWidget {
  final String taskId;
  const VisitReviewScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = store.tasks.firstWhere((t) => t.id == taskId, orElse: () => store.tasks.first);
    final customer = store.customers.firstWhere((c) => c.id == t.customerId, orElse: () => store.customers.first);
    final dispute = store.disputes.cast<Map<String, dynamic>?>().firstWhere((d) => d != null && d['customer'] == t.customerName, orElse: () => null);
    final amountLabel = dispute != null ? 'Amount in Dispute' : 'Outstanding';
    final amountValue = dispute != null ? (dispute['amount'] as num).toDouble() : customer.totalDue;

    final events = customer.auditHistory.reversed
        .map((a) => TimelineEvent(icon: Icons.history, color: kMuted, title: a.type, subtitle: a.description, date: a.timestamp, tag: a.actor, tagColor: kBlue))
        .take(5)
        .toList();

    return RequestDetailScaffold(
      title: 'VISIT DETAILS',
      subtitle: 'Physical Visit Pending Review',
      bannerText: t.reviewedByRE ? 'This visit outcome has been reviewed.' : 'This visit outcome is awaiting RE review before the case can move forward.',
      priorityLabel: t.reviewedByRE ? 'Reviewed' : 'Review Needed',
      color: _purple,
      bannerIcon: Icons.location_on_outlined,
      actions: t.reviewedByRE
          ? []
          : [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kBlue), foregroundColor: kBlue, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                child: const Text('View Customer 360', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
                child: const Text('Mark Reviewed', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
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
                    Text('Visited by: ${store.salesmanDisplayName(t.ownerId)}', style: const TextStyle(fontSize: 11, color: kMuted)),
                    Text(DateFormat('dd MMM yyyy · hh:mm a').format(t.completedAt ?? t.deadline), style: const TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(amountLabel, style: const TextStyle(fontSize: 10, color: kMuted)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(amountValue), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _purple))),
                ],
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('VISIT OUTCOME'),
        InfoCard(children: [
          KeyValueRow('Reason', t.reason),
          KeyValueRow('Source', t.source),
          KeyValueRow('Customer Outstanding', _rupee.format(customer.totalDue), valueColor: kRed),
        ]),
        const SizedBox(height: 18),
        AttachmentsSection(refId: taskId),
        const SizedBox(height: 18),
        NotesSection(refId: taskId),
        const SizedBox(height: 18),
        const SectionLabel('CUSTOMER ACTIVITY'),
        ActivityTimeline(events),
      ],
    );
  }
}
