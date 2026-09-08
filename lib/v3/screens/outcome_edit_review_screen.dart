import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

const _pink = Color(0xFFDB2777);

class OutcomeEditReviewScreen extends StatelessWidget {
  final String requestId;
  const OutcomeEditReviewScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final r = store.outcomeCorrectionRequests.firstWhere((r) => r.id == requestId, orElse: () => store.outcomeCorrectionRequests.first);
    final customer = store.customers.firstWhere((c) => c.id == r.customerId, orElse: () => store.customers.first);
    final isPending = r.status == 'Pending';

    return RequestDetailScaffold(
      title: 'OUTCOME EDIT',
      subtitle: 'Correction Awaiting Review',
      bannerText: isPending ? 'Salesperson requested a correction to a recorded outcome.' : 'This request is ${r.status}.',
      priorityLabel: isPending ? 'Needs Decision' : r.status,
      color: _pink,
      bannerIcon: Icons.edit_note,
      actions: isPending
          ? [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kRed), foregroundColor: kRed, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _reject(context, store, r.id),
                child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.approveOutcomeCorrection(r.id);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Outcome correction approved.');
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
                    Text('Requested by: ${store.salesmanDisplayName(r.salesmanId)}  ·  ${DateFormat('dd MMM yyyy, hh:mm a').format(r.requestedAt)}', style: const TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('CURRENTLY RECORDED'),
        InfoCard(children: [
          KeyValueRow('Outcome', r.originalOutcome),
          KeyValueRow('Reason', r.originalReason),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('REQUESTED CORRECTION'),
        InfoCard(children: [
          KeyValueRow('Outcome', r.requestedOutcome, valueColor: _pink),
          KeyValueRow('Reason', r.requestedReason, valueColor: _pink),
          KeyValueRow('Salesperson Note', r.requestNote),
        ]),
      ],
    );
  }

  void _reject(BuildContext context, AppStore store, String id) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Outcome Correction', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: reasonController, decoration: const InputDecoration(hintText: 'Reason', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              final dialogNavigator = Navigator.of(dialogCtx);
              final screenNavigator = Navigator.of(context);
              try {
                await store.rejectOutcomeCorrection(id, reasonController.text.trim());
                dialogNavigator.pop();
                screenNavigator.pop();
                showAppMessageAfter(screenNavigator, message: 'Outcome correction rejected.');
              } catch (e) {
                showAppMessageAfter(screenNavigator, message: 'Could not reject: $e', isError: true);
              }
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
