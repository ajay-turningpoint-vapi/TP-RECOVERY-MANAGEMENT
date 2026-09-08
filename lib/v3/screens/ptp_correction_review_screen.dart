import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _teal = Color(0xFF0D9488);

class PtpCorrectionReviewScreen extends StatelessWidget {
  final String ptpId;
  const PtpCorrectionReviewScreen({super.key, required this.ptpId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final p = store.ptps.firstWhere((p) => p.id == ptpId, orElse: () => store.ptps.first);
    final customer = store.customers.firstWhere((c) => c.id == p.customerId, orElse: () => store.customers.first);
    final isPending = p.correctionStatus == 'Pending';

    return RequestDetailScaffold(
      title: 'PTP CORRECTION',
      subtitle: 'Correction Awaiting Review',
      bannerText: isPending ? 'Salesperson requested a correction to this PTP commitment.' : 'This correction request is ${p.correctionStatus}.',
      priorityLabel: isPending ? 'Needs Decision' : p.correctionStatus,
      color: _teal,
      bannerIcon: Icons.swap_horiz,
      actions: isPending
          ? [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kRed), foregroundColor: kRed, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _reject(context, store, p.id),
                child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.approvePtpCorrection(p.id);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'PTP correction approved.');
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
                    Text('Salesman: ${store.salesmanDisplayName(customer.assignedSalesmanId)}', style: const TextStyle(fontSize: 11, color: kMuted)),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('ORIGINAL PTP'),
        InfoCard(children: [
          KeyValueRow('Amount', _rupee.format(p.amountPromised)),
          KeyValueRow('Date', DateFormat('dd MMM yyyy, hh:mm a').format(p.promiseDate)),
          KeyValueRow('Payment Mode', p.paymentMode),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('REQUESTED CORRECTION'),
        InfoCard(children: [
          KeyValueRow('Amount', _rupee.format(p.correctionRequestedAmount ?? p.amountPromised), valueColor: _teal),
          KeyValueRow('Date', p.correctionRequestedDate != null ? DateFormat('dd MMM yyyy, hh:mm a').format(p.correctionRequestedDate!) : '-', valueColor: _teal),
          KeyValueRow('Reason', p.correctionReason ?? '-'),
        ]),
        const SizedBox(height: 18),
        AttachmentsSection(refId: ptpId),
        const SizedBox(height: 18),
        NotesSection(refId: ptpId),
      ],
    );
  }

  void _reject(BuildContext context, AppStore store, String id) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject PTP Correction', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: reasonController, decoration: const InputDecoration(hintText: 'Reason', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              final navigator = Navigator.of(context);
              Navigator.pop(dialogCtx);
              try {
                await store.rejectPtpCorrection(id, reasonController.text.trim());
                navigator.pop();
                showAppMessageAfter(navigator, message: 'PTP correction rejected.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
              }
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
