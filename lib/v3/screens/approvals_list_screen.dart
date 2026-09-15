import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/dispute_detail_screen.dart';
import 'package:salesman_mobile/v3/screens/ptp_correction_review_screen.dart';
import 'package:salesman_mobile/v3/screens/outcome_edit_detail_screen.dart';
import 'package:salesman_mobile/v3/screens/outcome_edit_review_screen.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class _ApprovalItem {
  final String type; // shown as a small badge
  final Color color;
  final String title;
  final String subtitle;
  final String amount;
  final bool critical;
  final VoidCallback onTap;
  _ApprovalItem({required this.type, required this.color, required this.title, required this.subtitle, required this.amount, required this.critical, required this.onTap});
}

/// Verify / fail a "Payment Already Made" claim inline — the RE's only
/// action on it (reconcile against BUSY), same as the task-detail path.
void _verifyClaimSheet(BuildContext context, AppStore store, Map<String, dynamic> claim) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${claim['customer'] ?? ''} — ${_rupee.format((claim['amount'] as num?) ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _dark)),
              const SizedBox(height: 4),
              const Text('Reconcile this claimed payment against BUSY.',
                  style: TextStyle(fontSize: 12.5, color: _muted)),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Verify Deposit'),
                onPressed: () async {
                  final rootNav = Navigator.of(context);
                  Navigator.of(sheetCtx).pop();
                  try {
                    await store.verifyPaymentClaim(claim['id'] as String, true);
                    showAppMessageAfter(rootNav, message: 'Payment verified — balance reduced.');
                  } catch (e) {
                    showAppMessageAfter(rootNav, message: 'Could not verify: $e', isError: true);
                  }
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFDC2626))),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Fail Verification'),
                onPressed: () async {
                  final rootNav = Navigator.of(context);
                  Navigator.of(sheetCtx).pop();
                  try {
                    await store.verifyPaymentClaim(claim['id'] as String, false);
                    showAppMessageAfter(rootNav, message: 'Claim failed — customer returned to recovery.');
                  } catch (e) {
                    showAppMessageAfter(rootNav, message: 'Could not verify: $e', isError: true);
                  }
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Every pending "salesperson asked for a decision" item across the app —
/// disputes awaiting review, PTP correction / outcome edit / outcome
/// correction requests, and payment-claim verifications — in one list
/// instead of several places the RE would check one at a time.
/// `onlyCritical` narrows it to items flagged high-priority or tied to an
/// escalated account; every item routes to its existing review flow.
class ApprovalsListScreen extends StatelessWidget {
  final bool onlyCritical;
  const ApprovalsListScreen({super.key, this.onlyCritical = false});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    bool customerEscalated(String customerId) {
      final c = store.customers.firstWhere((c) => c.id == customerId, orElse: () => store.customers.first);
      return c.escalationLevel != 'none';
    }

    void go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    final items = <_ApprovalItem>[];

    for (final d in store.visibleDisputes) {
      if (d['status'] != 'Pending Approval') continue;
      final priority = (d['priority'] as String?) ?? 'Medium';
      items.add(_ApprovalItem(
        type: 'DISPUTE',
        color: const Color(0xFF4F46E5),
        title: d['customer'] as String? ?? 'Unknown customer',
        subtitle: 'Dispute · ${d['reason'] ?? '-'}',
        amount: _rupee.format((d['amount'] as num?) ?? 0),
        critical: priority == 'High',
        onTap: () => go(DisputeDetailScreen(disputeId: d['id'] as String)),
      ));
    }

    for (final p in store.ptpCorrectionRequests) {
      final c = store.customers.firstWhere((c) => c.id == p.customerId, orElse: () => store.customers.first);
      items.add(_ApprovalItem(
        type: 'PTP CORRECTION',
        color: const Color(0xFF0D9488),
        title: c.name,
        subtitle: 'Requested: ${_rupee.format(p.correctionRequestedAmount ?? p.amountPromised)} on ${p.correctionRequestedDate != null ? DateFormat('dd MMM').format(p.correctionRequestedDate!) : '-'}',
        amount: _rupee.format(p.amountPromised),
        critical: customerEscalated(p.customerId),
        onTap: () => go(PtpCorrectionReviewScreen(ptpId: p.id)),
      ));
    }

    for (final r in store.pendingOutcomeEdits) {
      items.add(_ApprovalItem(
        type: 'OUTCOME EDIT',
        color: const Color(0xFFDB2777),
        title: r.customerName,
        subtitle: '${r.outcomeKind} · by ${store.salesmanDisplayName(r.salesmanId)}',
        amount: DateFormat('dd MMM yyyy').format(r.requestedAt),
        critical: customerEscalated(r.customerId),
        onTap: () => go(OutcomeEditDetailScreen(requestId: r.id)),
      ));
    }

    for (final r in store.pendingOutcomeCorrections) {
      items.add(_ApprovalItem(
        type: 'OUTCOME CORRECTION',
        color: const Color(0xFFDB2777),
        title: r.customerName,
        subtitle: 'Correction requested by ${store.salesmanDisplayName(r.salesmanId)}',
        amount: DateFormat('dd MMM yyyy').format(r.requestedAt),
        critical: customerEscalated(r.customerId),
        onTap: () => go(OutcomeEditReviewScreen(requestId: r.id)),
      ));
    }

    for (final p in store.pendingPaymentClaims) {
      final cid = '${p['customerCode']}';
      items.add(_ApprovalItem(
        type: 'PAYMENT CLAIM',
        color: const Color(0xFF16A34A),
        title: (p['customer'] as String?) ?? cid,
        subtitle: 'Payment Already Made · claimed ${p['date'] ?? ''}',
        amount: _rupee.format((p['amount'] as num?) ?? 0),
        critical: customerEscalated(cid),
        onTap: () => _verifyClaimSheet(context, store, p),
      ));
    }

    final filtered = onlyCritical ? items.where((i) => i.critical).toList() : items;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
        title: Text(onlyCritical ? 'Critical Approvals' : 'Pending Approvals', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _dark)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text('${filtered.length} item(s) awaiting a decision', style: const TextStyle(fontSize: 12, color: _muted)),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Nothing awaiting approval.', style: TextStyle(color: _muted, fontSize: 13)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: item.onTap,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(color: item.color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                            child: Text(item.type, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: item.color)),
                                          ),
                                          if (item.critical) ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.priority_high, size: 13, color: Color(0xFFDC2626)),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                                      const SizedBox(height: 3),
                                      Text(item.subtitle, style: const TextStyle(fontSize: 11, color: _muted)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(item.amount, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                                    const SizedBox(height: 4),
                                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
