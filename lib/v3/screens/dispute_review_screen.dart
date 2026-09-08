import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _indigo = Color(0xFF4F46E5);

class DisputeReviewScreen extends StatelessWidget {
  final String disputeId;
  const DisputeReviewScreen({super.key, required this.disputeId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final d = store.disputes.firstWhere((d) => d['id'] == disputeId, orElse: () => store.disputes.first);
    final customer = store.customers.firstWhere((c) => c.name == d['customer'], orElse: () => store.customers.first);
    final amount = (d['amount'] as num).toDouble();
    final totalDue = (d['totalDue'] as num?)?.toDouble() ?? customer.totalDue;
    final undisputed = (totalDue - amount).clamp(0, double.infinity);
    final status = d['status'] as String;
    final isPending = status == 'Pending Approval';
    // The real server-side second-stage verification (disputeService.resolve)
    // becomes available once RE has Approved the dispute — there is no
    // separate "Awaiting Verification" transition in the real flow.
    final isAwaitingVerification = status == 'Approved';

    final events = customer.auditHistory.reversed
        .map((a) => TimelineEvent(icon: Icons.history, color: kMuted, title: a.type, subtitle: a.description, date: a.timestamp, tag: a.actor, tagColor: kBlue))
        .take(5)
        .toList();

    return RequestDetailScaffold(
      title: 'DISPUTE DETAILS',
      subtitle: 'Dispute Awaiting Review',
      bannerText: isPending
          ? 'This dispute is awaiting your approval decision.'
          : (isAwaitingVerification ? 'Resolution complete — verify against BUSY before closing.' : 'This dispute is $status.'),
      priorityLabel: isPending ? 'Needs Decision' : (isAwaitingVerification ? 'Needs Verification' : status),
      color: _indigo,
      bannerIcon: Icons.description_outlined,
      actions: isPending
          ? [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kRed), foregroundColor: kRed, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _reject(context, store, d),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: kBlue), foregroundColor: kBlue, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _needInfo(context, store, d),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Need Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _approve(context, store, d),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ),
            ]
          : (isAwaitingVerification
              ? [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: kOrange), foregroundColor: kOrange, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      try {
                        await store.resolveDispute(d['id'], 'Returned to Recovery');
                        navigator.pop();
                        showAppMessageAfter(navigator, message: 'Resolved but unpaid — amount returned to active recovery.');
                      } catch (e) {
                        showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
                      }
                    },
                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Still Unpaid → Recovery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      try {
                        await store.resolveDispute(d['id'], 'Resolved');
                        navigator.pop();
                        showAppMessageAfter(navigator, message: 'Dispute verified and resolved.');
                      } catch (e) {
                        showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
                      }
                    },
                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Verify & Resolve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ),
                ]
              : []),
      children: [
        InfoCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Disputed Amount', style: TextStyle(fontSize: 10, color: kMuted)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _indigo))),
                ],
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('DISPUTE SUMMARY'),
        InfoCard(children: [
          KeyValueRow('Total Due', _rupee.format(totalDue)),
          KeyValueRow('Disputed Amount', _rupee.format(amount), valueColor: _indigo),
          KeyValueRow('Active Recovery (Undisputed)', _rupee.format(undisputed), valueColor: kGreen),
          KeyValueRow('Reason', d['reason']),
          KeyValueRow('Status', status, valueColor: isPending ? kOrange : kMuted),
        ]),
        const SizedBox(height: 18),
        AttachmentsSection(refId: disputeId),
        const SizedBox(height: 18),
        NotesSection(refId: disputeId),
        const SizedBox(height: 18),
        const SectionLabel('CUSTOMER ACTIVITY'),
        ActivityTimeline(events),
      ],
    );
  }

  void _approve(BuildContext context, AppStore store, Map<String, dynamic> d) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
    final descController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 2));
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Dispute & Assign Resolution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: selectedSalesman,
                isExpanded: true,
                items: store.salesmen.map<DropdownMenuItem<String>>((s) => DropdownMenuItem(value: s['name'], child: Text((s['fullName'] as String?) ?? s['name'], overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) { if (v != null) setState(() => selectedSalesman = v); },
                decoration: const InputDecoration(labelText: 'Resolution Owner', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(controller: descController, decoration: const InputDecoration(hintText: 'Resolution instructions', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: deadline, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (picked != null) setState(() => deadline = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('dd MMM yyyy').format(deadline)), const Icon(Icons.calendar_today, size: 16)]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.approveDispute(d['id'], selectedSalesman, deadline, descController.text.trim());
                  navigator.pop();
                  showAppMessageAfter(navigator, message: 'Dispute approved. Resolution task created.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
                }
              },
              child: const Text('Approve', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  void _reject(BuildContext context, AppStore store, Map<String, dynamic> d) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Dispute', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: reasonController, decoration: const InputDecoration(hintText: 'Reason for rejection', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              final navigator = Navigator.of(context);
              Navigator.pop(dialogCtx);
              try {
                await store.rejectDispute(d['id'], reasonController.text.trim());
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Dispute rejected. Customer returned to recovery.');
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

  void _needInfo(BuildContext context, AppStore store, Map<String, dynamic> d) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
    final descController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 1));
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Request More Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: selectedSalesman,
                isExpanded: true,
                items: store.salesmen.map<DropdownMenuItem<String>>((s) => DropdownMenuItem(value: s['name'], child: Text((s['fullName'] as String?) ?? s['name'], overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) { if (v != null) setState(() => selectedSalesman = v); },
                decoration: const InputDecoration(labelText: 'Assign to', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(controller: descController, decoration: const InputDecoration(hintText: 'Information required', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.requestDisputeInfo(d['id'], selectedSalesman, descController.text.trim(), deadline);
                  navigator.pop();
                  showAppMessageAfter(navigator, message: 'Information requested from salesperson.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not request info: $e', isError: true);
                }
              },
              child: const Text('Request', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }
}
