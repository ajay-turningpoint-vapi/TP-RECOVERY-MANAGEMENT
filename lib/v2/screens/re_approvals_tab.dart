import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/v3/screens/dispute_detail_screen.dart';

class ReApprovalsTab extends StatefulWidget {
  const ReApprovalsTab({super.key});

  @override
  State<ReApprovalsTab> createState() => _ReApprovalsTabState();
}

class _ReApprovalsTabState extends State<ReApprovalsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    // Tab badge covers both dispute sub-states that need an RE decision —
    // matches AppStore.disputeNeedsReActionStatuses. 'Pending Approval'
    // alone used to make this badge (and the tab's own list) silently
    // undercount the moment a resolution owner submitted their work.
    final pendingDisputes = store.visibleDisputes.where((d) => AppStore.disputeNeedsReActionStatuses.contains(d['status'])).toList();
    final pendingClaims = store.paymentClaims.where((p) => p['status'] == 'Awaiting Verification' || p['status'] == 'Sync Pending').toList();
    final pendingPtpCorrections = store.ptpCorrectionRequests;
    final pendingOutcomeEdits = store.pendingOutcomeEdits;

    return Column(
      children: [
        // Tab Bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF0052CC),
            unselectedLabelColor: const Color(0xFF5A6B87),
            indicatorColor: const Color(0xFF0052CC),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'PTP Corrections (${pendingPtpCorrections.length})'),
              Tab(text: 'Outcome Edits (${pendingOutcomeEdits.length})'),
              Tab(text: 'Disputes (${pendingDisputes.length})'),
              Tab(text: 'Payments (${pendingClaims.length})'),
            ],
          ),
        ),
        // Tab View
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPtpCorrectionsList(pendingPtpCorrections, store),
              _buildOutcomeEditsList(pendingOutcomeEdits, store),
              _buildDisputesList(store.visibleDisputes, store),
              _buildClaimsList(pendingClaims, store),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPtpCorrectionsList(List ptps, AppStore store) {
    if (ptps.isEmpty) {
      return const Center(
        child: Text('No pending PTP correction requests.', style: TextStyle(color: Color(0xFF5A6B87))),
      );
    }
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ptps.length,
      itemBuilder: (ctx, i) {
        final p = ptps[i];
        final customer = store.customers.firstWhere((c) => c.id == p.customerId, orElse: () => store.customers.first);
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48))),
              const SizedBox(height: 12),
              const Text('ORIGINAL PTP', style: TextStyle(fontSize: 10, color: Color(0xFF5A6B87), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text('${fmt.format(p.amountPromised)}  •  ${DateFormat('dd MMM, hh:mm a').format(p.promiseDate)}', style: const TextStyle(fontSize: 13, color: Colors.grey, decoration: TextDecoration.lineThrough)),
              const SizedBox(height: 12),
              const Text('REQUESTED EDIT', style: TextStyle(fontSize: 10, color: Color(0xFF5A6B87), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text('${fmt.format(p.correctionRequestedAmount ?? p.amountPromised)}  •  ${p.correctionRequestedDate != null ? DateFormat('dd MMM, hh:mm a').format(p.correctionRequestedDate!) : '-'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
              const SizedBox(height: 8),
              Text('Reason: ${p.correctionReason ?? '-'}', style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LoadingOutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE53935)),
                        foregroundColor: const Color(0xFFE53935),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await store.rejectPtpCorrection(p.id, 'Not justified');
                          showAppMessageAfter(navigator, message: 'PTP correction rejected.');
                        } catch (e) {
                          showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
                        }
                      },
                      child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LoadingElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF388E3C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await store.approvePtpCorrection(p.id);
                          showAppMessageAfter(navigator, message: 'PTP correction approved.');
                        } catch (e) {
                          showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
                        }
                      },
                      child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutcomeEditsList(List requests, AppStore store) {
    if (requests.isEmpty) {
      return const Center(
        child: Text('No pending outcome edit requests.', style: TextStyle(color: Color(0xFF5A6B87))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (ctx, i) {
        final r = requests[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(r.customerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48)))),
                  Text('by ${store.salesmanDisplayName(r.salesmanId)}', style: const TextStyle(fontSize: 11, color: Color(0xFF5A6B87))),
                ],
              ),
              const SizedBox(height: 12),
              const Text('CURRENTLY RECORDED', style: TextStyle(fontSize: 10, color: Color(0xFF5A6B87), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text('${r.outcomeKind} outcome', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              Text(_payloadSummary(r.originalPayload), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              const Text('REQUESTED EDIT', style: TextStyle(fontSize: 10, color: Color(0xFF5A6B87), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(_payloadSummary(r.requestedPayload), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
              const SizedBox(height: 8),
              Text('Reason: ${r.editReason}', style: const TextStyle(fontSize: 11, color: Color(0xFF5A6B87), fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LoadingOutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE53935)),
                        foregroundColor: const Color(0xFFE53935),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await store.rejectOutcomeEdit(r.id, 'Not justified');
                          showAppMessageAfter(navigator, message: 'Outcome edit rejected.');
                        } catch (e) {
                          showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
                        }
                      },
                      child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LoadingElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF388E3C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await store.approveOutcomeEdit(r.id);
                          showAppMessageAfter(navigator, message: 'Outcome edit approved and applied.');
                        } catch (e) {
                          showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
                        }
                      },
                      child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisputesList(List<Map<String, dynamic>> allDisputes, AppStore store) {
    final pendingDisputes = allDisputes.where((d) => d['status'] == 'Pending Approval').toList();
    // A resolution owner's submitted claim — needs an RE decision (Verify
    // & Resolve / Still Unpaid → Recovery), but that's a fuller flow than
    // this tab's inline Approve/Reject buttons support, so it gets its own
    // section with a "Review" button through to the real dispute screen
    // instead of pretending Approve/Reject apply here too.
    final awaitingVerification = allDisputes.where((d) => d['status'] == 'Awaiting Verification').toList();
    final resolvedDisputes = allDisputes.where((d) => !AppStore.disputeNeedsReActionStatuses.contains(d['status'])).toList();
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pendingDisputes.isNotEmpty) ...[
          const Text('AWAITING RE APPROVAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A6B87), letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...pendingDisputes.map((d) => _buildDisputeItemCard(d, store, fmt, isPending: true)),
        ] else if (awaitingVerification.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: Text('No pending disputes.', style: TextStyle(color: Color(0xFF5A6B87)))),
          ),

        if (awaitingVerification.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('NEEDS VERIFICATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A6B87), letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...awaitingVerification.map((d) => _buildVerificationItemCard(context, d, fmt)),
        ],

        if (resolvedDisputes.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('OTHER DISPUTES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A6B87), letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...resolvedDisputes.map((d) => _buildDisputeItemCard(d, store, fmt, isPending: false)),
        ],
      ],
    );
  }

  /// A resolution owner's submitted claim — tapping through opens the full
  /// dispute screen (Verify & Resolve / Still Unpaid → Recovery), which
  /// this tab's own inline Approve/Reject/Need Info buttons don't cover.
  Widget _buildVerificationItemCard(BuildContext context, Map<String, dynamic> d, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF57C00).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(d['customer'] as String? ?? 'Unknown customer',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48))),
              ),
              const SizedBox(width: 8),
              Text(fmt.format(d['amount']), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF57C00), fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Reason: ${d['reason']}', style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
          const SizedBox(height: 6),
          const Text('Status: Awaiting Verification', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF57C00))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0052CC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DisputeDetailScreen(disputeId: d['id'] as String))),
              child: const Text('Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisputeItemCard(Map<String, dynamic> d, AppStore store, NumberFormat fmt, {required bool isPending}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Expanded + ellipsis: a long real customer name (e.g. "RITESH
              // BHAI MEHTA # CETKO CHEMICAL (R)") left the amount with no
              // room in an unconstrained Row and overflowed off-screen.
              Expanded(
                child: Text(d['customer'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48))),
              ),
              const SizedBox(width: 8),
              Text(fmt.format(d['amount']), style: TextStyle(fontWeight: FontWeight.bold, color: isPending ? const Color(0xFFE53935) : Colors.green, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Reason: ${d['reason']}', style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
          const SizedBox(height: 6),
          Text('Status: ${d['status']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPending ? const Color(0xFFF57C00) : Colors.green)),
          if (isPending) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF388E3C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _showApproveDisputeDialog(context, store, d),
                    child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _showRejectDisputeDialog(context, store, d),
                    child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0052CC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _showRequestInfoDialog(context, store, d),
                    child: const Text('Need Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showApproveDisputeDialog(BuildContext context, AppStore store, Map<String, dynamic> dispute) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
    final descController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 2));

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Approve Dispute & Assign Resolution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Resolution Agent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSalesman,
                    isExpanded: true,
                    // s['name'] is really the salesman's user id (used
                    // throughout the app to match Customer.assignedSalesmanId
                    // / Task.ownerId) — real display name is s['fullName'].
                    // Showing the raw id here overflowed the dialog and was
                    // meaningless to a real RE picking a real colleague.
                    items: store.salesmen
                        .map<DropdownMenuItem<String>>((s) => DropdownMenuItem<String>(
                              value: s['name'],
                              child: Text((s['fullName'] as String?) ?? s['name'], overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedSalesman = val;
                        });
                      }
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Resolution Instructions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Issue credit note / replace goods',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Resolution Deadline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                          const Icon(Icons.calendar_today, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                LoadingElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0052CC)),
                  onPressed: () async {
                    if (descController.text.trim().isEmpty) return;
                    final navigator = Navigator.of(context);
                    try {
                      await store.approveDispute(
                        dispute['id'],
                        selectedSalesman,
                        selectedDate,
                        descController.text.trim(),
                      );
                      // Pop only on success — stays open (button spinning) while
                      // the request is in flight, so a slow connection never
                      // looks like a dead button and can't be double-tapped.
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      showAppMessageAfter(navigator, message: 'Dispute approved. Resolution task created!');
                    } catch (e) {
                      showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
                    }
                  },
                  child: const Text('Approve', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showRejectDisputeDialog(BuildContext context, AppStore store, Map<String, dynamic> dispute) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Dispute', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reason for Rejection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Invalid discount claim',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.rejectDispute(dispute['id'], reasonController.text.trim());
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  showAppMessageAfter(navigator, message: 'Dispute rejected. Customer returned to recovery.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
                }
              },
              child: const Text('Reject', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    );
  }

  void _showRequestInfoDialog(BuildContext context, AppStore store, Map<String, dynamic> dispute) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
    final descController = TextEditingController();
    // A clarification is needed now, so this must land in the salesperson's
    // Today's Tasks by default — RE can still push it out via the date
    // picker below. Matches disputeService.js's own defaultCallDeadline()
    // (today 9 PM, or tomorrow 9 PM if already past that).
    final now = DateTime.now();
    DateTime selectedDate = now.hour >= 21
        ? DateTime(now.year, now.month, now.day + 1, 21)
        : DateTime(now.year, now.month, now.day, 21);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Request More Dispute Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Assign Info Gathering To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSalesman,
                    isExpanded: true,
                    // s['name'] is really the salesman's user id (used
                    // throughout the app to match Customer.assignedSalesmanId
                    // / Task.ownerId) — real display name is s['fullName'].
                    // Showing the raw id here overflowed the dialog and was
                    // meaningless to a real RE picking a real colleague.
                    items: store.salesmen
                        .map<DropdownMenuItem<String>>((s) => DropdownMenuItem<String>(
                              value: s['name'],
                              child: Text((s['fullName'] as String?) ?? s['name'], overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedSalesman = val;
                        });
                      }
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Information Required Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Upload damaged goods invoice copy',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Deadline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                          const Icon(Icons.calendar_today, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                LoadingElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF57C00)),
                  onPressed: () async {
                    if (descController.text.trim().isEmpty) return;
                    final navigator = Navigator.of(context);
                    try {
                      await store.requestDisputeInfo(
                        dispute['id'],
                        selectedSalesman,
                        descController.text.trim(),
                        selectedDate,
                      );
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      showAppMessageAfter(navigator, message: 'Information requested. Info gathering task created.');
                    } catch (e) {
                      showAppMessageAfter(navigator, message: 'Could not request info: $e', isError: true);
                    }
                  },
                  child: const Text('Request Info', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildClaimsList(List<Map<String, dynamic>> claims, AppStore store) {
    if (claims.isEmpty) {
      return const Center(
        child: Text('No payment claims awaiting verification.', style: TextStyle(color: Color(0xFF5A6B87))),
      );
    }

    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: claims.length,
      itemBuilder: (ctx, i) {
        final c = claims[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded + ellipsis: same real-customer-name overflow
                  // fix as the dispute card above — a long name plus the
                  // "SYNC PENDING" chip left the amount no room.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: Text(c['customer'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48)))),
                        if (c['status'] == 'Sync Pending') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
                            child: const Text('SYNC PENDING', style: TextStyle(color: Color(0xFFE53935), fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(fmt.format(c['amount']), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF388E3C), fontSize: 15)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Txn Ref: ${c['reference']} • Date: ${c['date']}', style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LoadingOutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE53935)),
                        foregroundColor: const Color(0xFFE53935),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await store.verifyPaymentClaim(c['id'], false);
                          showAppMessageAfter(navigator, message: 'Payment claim marked Failed.');
                        } catch (e) {
                          showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
                        }
                      },
                      child: const Text('Fail Verification', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LoadingElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF388E3C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        try {
                          await store.verifyPaymentClaim(c['id'], true);
                          showAppMessageAfter(navigator, message: 'Payment verified successfully!');
                        } catch (e) {
                          showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
                        }
                      },
                      child: const Text('Verify Deposit', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _payloadSummary(Map<String, dynamic> m) =>
      m.entries.map((e) => '${e.key}: ${e.value}').join('  ·  ');
}
