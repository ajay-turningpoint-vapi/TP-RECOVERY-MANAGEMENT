import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/outcome_edit_request.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';

const _accent = Color(0xFF0EA5A4);

/// RE review of a salesperson's request to edit a recorded outcome's own
/// fields (PTP amount/date/mode, dispute amount/reason, …). Shows the
/// current values vs the requested values; approving applies them in place
/// and re-runs side effects (server: outcomeEditService.approve).
class OutcomeEditDetailScreen extends StatelessWidget {
  final String requestId;
  const OutcomeEditDetailScreen({super.key, required this.requestId});

  static const _kindLabel = {
    'PTP': 'Promise to Pay',
    'PaymentClaim': 'Payment Claim',
    'Dispute': 'Dispute',
    'FollowUp': 'Follow-up',
    'Simple': 'Call Outcome',
    'NoAnswerReplacement': 'No Answer Replacement',
  };

  String _fmt(String key, dynamic v) {
    if (v == null) return '—';
    final k = key.toLowerCase();
    if (k.contains('date') || k.contains('deadline')) {
      final d = DateTime.tryParse(v.toString());
      if (d != null) return DateFormat('dd MMM yyyy, hh:mm a').format(d.toLocal());
    }
    if (k.contains('amount')) {
      final n = num.tryParse(v.toString());
      if (n != null) return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // Only ever show the Approve/Reject decision once the real request (and
    // the customer it targets) is genuinely found — never fall back to an
    // unrelated/first request or an empty stand-in, which previously let the
    // action bar render with no information above it.
    OutcomeEditRequest? r;
    for (final x in store.outcomeEditRequests) {
      if (x.id == requestId) {
        r = x;
        break;
      }
    }
    if (r == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: kNavy,
          title: const Text('Outcome Edit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This request could not be found — it may have already been resolved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 13),
            ),
          ),
        ),
      );
    }

    Customer? customer;
    for (final c in store.customers) {
      if (c.id == r.customerId) {
        customer = c;
        break;
      }
    }
    if (customer == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: kNavy,
          title: const Text('Outcome Edit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The customer for this request could not be found.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 13),
            ),
          ),
        ),
      );
    }

    // Rebind to non-nullable locals — captured inside onPressed/onTap
    // closures below, where the analyzer can't otherwise promote a
    // null-checked local.
    final request = r;
    final cust = customer;
    final isPending = request.status == 'Pending';
    final keys = {...request.originalPayload.keys, ...request.requestedPayload.keys}.toList();

    return RequestDetailScaffold(
      title: 'OUTCOME EDIT',
      subtitle: '${_kindLabel[request.outcomeKind] ?? request.outcomeKind} — Field Edit',
      bannerText: isPending
          ? 'Salesperson requested an edit to a recorded outcome\'s values.'
          : 'This request is ${request.status}.',
      priorityLabel: isPending ? 'Needs Decision' : request.status,
      color: _accent,
      bannerIcon: Icons.edit_note,
      actions: isPending
          ? [
              LoadingOutlinedButton(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kRed, width: 1.4),
                    foregroundColor: kRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async => _reject(context, store, request.id),
                child: const Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.close, size: 17),
                  SizedBox(width: 8),
                  Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
              ),
              LoadingElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.approveOutcomeEdit(request.id);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Outcome edit approved and applied.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
                  }
                },
                child: const Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check, size: 17),
                  SizedBox(width: 8),
                  Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
              ),
            ]
          : [],
      children: [
        InfoCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                  radius: 24,
                  backgroundColor: avatarColorFor(cust.name).withOpacity(0.15),
                  child: Text(initialsFor(cust.name),
                      style: TextStyle(color: avatarColorFor(cust.name), fontSize: 15, fontWeight: FontWeight.bold))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: cust))),
                      child: Text(cust.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 13, color: kMuted),
                        const SizedBox(width: 4),
                        Text('Requested by ${store.salesmanDisplayName(request.salesmanId)}',
                            style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 13, color: kMuted),
                        const SizedBox(width: 4),
                        Text(DateFormat('dd MMM yyyy, hh:mm a').format(request.requestedAt),
                            style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 20),
        const SectionLabel('CURRENTLY RECORDED'),
        InfoCard(children: [
          if (keys.isEmpty)
            const Text('No recorded values available for this outcome.', style: TextStyle(fontSize: 12, color: kMuted))
          else
            for (final k in keys)
              KeyValueRow(_titleCase(k), _fmt(k, request.originalPayload[k]), divider: k != keys.last),
        ]),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: SectionLabel('REQUESTED EDIT')),
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _accent.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: const Text('PROPOSED CHANGE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _accent, letterSpacing: 0.3)),
            ),
          ],
        ),
        InfoCard(
          tint: _accent.withOpacity(0.04),
          borderColor: _accent.withOpacity(0.25),
          children: [
            if (keys.isEmpty)
              const Text('No field changes were included in this request.', style: TextStyle(fontSize: 12, color: kMuted))
            else
              for (final k in keys)
                if (request.originalPayload[k]?.toString() == request.requestedPayload[k]?.toString())
                  KeyValueRow(_titleCase(k), _fmt(k, request.requestedPayload[k]), divider: true)
                else
                  KeyValueRow(_titleCase(k), _fmt(k, request.requestedPayload[k]), valueColor: _accent, divider: true),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 14, color: Colors.amber.shade800),
                  const SizedBox(width: 6),
                  Text('REASON FOR EDIT',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.amber.shade900, letterSpacing: 0.4)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                request.editReason.isEmpty ? 'No reason given.' : request.editReason,
                style: TextStyle(fontSize: 13, color: Colors.amber.shade900, height: 1.4, fontStyle: request.editReason.isEmpty ? FontStyle.italic : FontStyle.normal),
              ),
            ],
          ),
        ),
        if (request.status == 'Rejected' && (request.rejectionReason ?? '').isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionLabel('REJECTION REASON'),
          InfoCard(children: [KeyValueRow('Reason', request.rejectionReason!)]),
        ],
        const SizedBox(height: 20),
        AttachmentsSection(refId: requestId),
        const SizedBox(height: 18),
        NotesSection(refId: requestId),
      ],
    );
  }

  static String _titleCase(String k) {
    final s = k.replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]}').trim();
    return s.isEmpty ? k : s[0].toUpperCase() + s.substring(1);
  }

  void _reject(BuildContext context, AppStore store, String id) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Outcome Edit', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(hintText: 'Reason', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              final screenNavigator = Navigator.of(context);
              try {
                await store.rejectOutcomeEdit(id, reasonController.text.trim());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                screenNavigator.pop();
                showAppMessageAfter(screenNavigator, message: 'Outcome edit rejected.');
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
