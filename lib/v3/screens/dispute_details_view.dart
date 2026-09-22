import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/services/attachment_picker.dart';

final _rupee =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _navy = Color(0xFF1B2B48);
const _blue = Color(0xFF2563EB);
const _indigo = Color(0xFF4F46E5);

class DisputeDetailsView extends StatelessWidget {
  final String disputeId;
  final VoidCallback onBack;
  final VoidCallback onApproveAssign;
  final VoidCallback onDecided;
  const DisputeDetailsView(
      {super.key,
      required this.disputeId,
      required this.onBack,
      required this.onApproveAssign,
      required this.onDecided});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final d = store.disputes.firstWhere((d) => d['id'] == disputeId,
        orElse: () => store.disputes.first);
    final customer = store.customers.firstWhere((c) => c.name == d['customer'],
        orElse: () => store.customers.first);
    final amount = (d['amount'] as num).toDouble();
    final totalDue = (d['totalDue'] as num?)?.toDouble() ?? customer.totalDue;
    final undisputed = (totalDue - amount).clamp(0, double.infinity);
    final status = d['status'] as String;
    final isPending = status == 'Pending Approval';
    // Real server-side second-stage verification (disputeService.resolve)
    // becomes available only once the resolution owner has submitted their
    // work (status → Awaiting Verification) — NOT as soon as the RE
    // approves. This is the primary Disputes tab, so it's the natural
    // place to reach it (an Awaiting Verification dispute is not reachable
    // from the Needs Attention or RE Tasks screens, which only ever list
    // Pending Approval disputes).
    final needsVerification = status == 'Awaiting Verification';
    // The resolution owner declined the assignment (rejectByOwner clears
    // resolutionOwner but leaves status Approved) — RE must pick someone
    // else via the same Approve & Assign flow used at Pending Approval.
    final needsReassignment = status == 'Approved' && (d['resolutionOwner'] as String?) == null;
    // Both are really internal user ids (assignedSalesmanId / the RE's
    // chosen resolutionOwner from the approve dialog) — resolved to real,
    // readable names once here since neither is ever used again as an id.
    final raisedBy = customer.assignedSalesmanId.isEmpty
        ? (d['raisedBy'] as String? ?? 'Unassigned')
        : store.salesmanDisplayName(customer.assignedSalesmanId);
    final resolutionOwner = (d['resolutionOwner'] as String?) != null ? store.salesmanDisplayName(d['resolutionOwner'] as String) : null;
    final deadline = d['deadline'] as DateTime?;
    final department = d['department'] as String?;

    // This view is swapped in-place inside DisputesTab (itself already
    // hosted inside ReScaffoldV3's own Scaffold via an IndexedStack), rather
    // than pushed as a new route — so it must NOT wrap its content in a
    // second, competing Scaffold(appBar:, bottomNavigationBar:). Nesting a
    // full Scaffold inside another Scaffold's body here left the AppBar and
    // body content unrendered, with only the button row visible (a real,
    // confirmed rendering bug, not a testing artifact — the outer Scaffold's
    // own real estate does not correctly propagate through a second nested
    // Scaffold in this position). A plain Column reproducing the same visual
    // header/footer avoids the nesting entirely.
    return Container(
      color: kBg,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: _navy),
                          onPressed: onBack),
                    ),
                    const Text('DISPUTE DETAILS',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _navy)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: kOrange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(
                                (d['statusDetail'] ?? status)
                                    .toString()
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: kOrange)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InfoCard(children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                                radius: 22,
                                backgroundColor: avatarColorFor(customer.name)
                                    .withOpacity(0.15),
                                child: Text(initialsFor(customer.name),
                                    style: TextStyle(
                                        color: avatarColorFor(customer.name),
                                        fontWeight: FontWeight.bold))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => Customer360Screen(
                                                customer: customer))),
                                    child: Text(customer.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: _blue,
                                            decoration:
                                                TextDecoration.underline)),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                      'Customer ID: ${d['customerCode']}  ·  Invoice: ${(d['invoice'] as String?) ?? 'No invoice'}',
                                      style: const TextStyle(
                                          fontSize: 10.5, color: kMuted)),
                                  Text('${customer.branch} Branch',
                                      style: const TextStyle(
                                          fontSize: 10.5, color: kMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _statBox(
                                  Icons.account_balance_wallet_outlined,
                                  _blue,
                                  'Dispute Amount',
                                  _rupee.format(amount))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _statBox(
                                  Icons.savings_outlined,
                                  kGreen,
                                  'Undisputed Amount',
                                  _rupee.format(undisputed))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                              child: _statBox(Icons.person_outline, _indigo,
                                  'Raised By', raisedBy)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _statBox(
                                  Icons.event_outlined,
                                  kOrange,
                                  'Raised On',
                                  DateFormat('dd MMM yyyy, hh:mm a')
                                      .format(d['raisedDate']))),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const SectionLabel('DISPUTE SUMMARY'),
                      InfoCard(children: [
                        KeyValueRow('Reason', d['reason']),
                        const KeyValueRow('Impact',
                            'Recovery on disputed amount is paused after approval; undisputed amount continues normal recovery.'),
                      ]),
                      if ((d['attachmentPath'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 18),
                        const SectionLabel('EVIDENCE FROM SALESMAN'),
                        InfoCard(children: [TaskAttachmentThumbnail(path: d['attachmentPath'] as String)]),
                      ],
                      if ((needsVerification || ((d['messages'] as List?) ?? const []).isNotEmpty)) ...[
                        const SizedBox(height: 18),
                        SectionLabel(needsVerification ? 'DISPUTE THREAD' : 'CLARIFICATION THREAD'),
                        InfoCard(children: [
                          _clarificationThread(((d['messages'] as List?) ?? const [])),
                          if (needsVerification) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: _indigo), foregroundColor: _indigo),
                                onPressed: () => _sendMessage(context, store, d),
                                icon: const Icon(Icons.reply, size: 15),
                                label: const Text('Message resolution owner', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ]),
                      ],
                      const SizedBox(height: 18),
                      const SectionLabel('RESOLUTION PLAN'),
                      InfoCard(children: [
                        KeyValueRow('Resolution Owner',
                            resolutionOwner ?? 'Pending assignment',
                            valueColor:
                                resolutionOwner != null ? kDark : kMuted),
                        KeyValueRow(
                            'Deadline',
                            deadline != null
                                ? DateFormat('dd MMM yyyy, hh:mm a')
                                    .format(deadline)
                                : 'Not set',
                            valueColor: deadline != null ? kDark : kMuted),
                        KeyValueRow(
                            'Internal Department', department ?? 'Not assigned',
                            valueColor: department != null ? kDark : kMuted),
                      ]),
                      const SizedBox(height: 18),
                      const SectionLabel('TIMELINE'),
                      ActivityTimeline(_buildTimeline(d, raisedBy, resolutionOwner)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isPending)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: kBorder))),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: kRed),
                                foregroundColor: kRed,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onPressed: () => _reject(context, store, d),
                            child: const Text('Reject',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: _blue),
                                foregroundColor: _blue,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onPressed: () => _clarify(context, store, d),
                            child: const Text('Clarify',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _blue,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onPressed: onApproveAssign,
                            child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Approve & Assign',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (needsReassignment)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: kBorder))),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: onApproveAssign,
                      child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Reassign Resolution Owner', style: TextStyle(fontWeight: FontWeight.bold))),
                    ),
                  ),
                ),
              ),
            ),
          if (needsVerification)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: kBorder))),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Row(
                      children: [
                        Expanded(
                          child: LoadingOutlinedButton(
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: kOrange),
                                foregroundColor: kOrange,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () => _resolve(context, store, d, 'Returned to Recovery'),
                            child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Still Unpaid → Recovery', style: TextStyle(fontWeight: FontWeight.bold))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LoadingElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: kGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () => _resolve(context, store, d, 'Resolved'),
                            child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Verify & Resolve', style: TextStyle(fontWeight: FontWeight.bold))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, AppStore store, Map<String, dynamic> d, String outcome) async {
    final navigator = Navigator.of(context);
    try {
      await store.resolveDispute(d['id'], outcome);
      onDecided();
      showAppMessageAfter(navigator, message: outcome == 'Resolved' ? 'Dispute verified and resolved.' : 'Resolved but unpaid — amount returned to active recovery.');
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
    }
  }

  List<TimelineEvent> _buildTimeline(Map<String, dynamic> d, String raisedBy, String? resolutionOwnerName) {
    final events = <TimelineEvent>[
      TimelineEvent(
          icon: Icons.report_gmailerrorred,
          color: _blue,
          title: 'Dispute raised by salesman',
          subtitle: raisedBy,
          date: d['raisedDate'],
          tag: DateFormat('dd MMM, hh:mm a').format(d['raisedDate']),
          tagColor: kMuted),
    ];
    final resolutionOwner = d['resolutionOwner'] as String?;
    if (resolutionOwner != null) {
      events.add(TimelineEvent(
          icon: Icons.person_add_alt,
          color: kGreen,
          title: 'Resolution owner assigned',
          subtitle: resolutionOwnerName ?? resolutionOwner,
          date: (d['assignedAt'] as DateTime?) ?? d['lastUpdated'],
          tag: 'Approved',
          tagColor: kGreen));
    }
    if (d['status'] == 'Rejected' && d['rejectionReason'] != null) {
      events.add(TimelineEvent(
          icon: Icons.cancel_outlined,
          color: kRed,
          title: 'Dispute rejected',
          subtitle: d['rejectionReason'],
          date: d['lastUpdated'],
          tag: 'Rejected',
          tagColor: kRed));
    }
    if (d['status'] == 'Need More Information' &&
        d['infoRequestNote'] != null) {
      events.add(TimelineEvent(
          icon: Icons.help_outline,
          color: kOrange,
          title: 'Additional info requested',
          subtitle: d['infoRequestNote'],
          date: d['lastUpdated'],
          tag: 'Awaiting Info',
          tagColor: kOrange));
    }
    if (resolutionOwner == null && d['status'] == 'Pending Approval') {
      events.add(TimelineEvent(
          icon: Icons.hourglass_empty,
          color: kOrange,
          title: 'Awaiting RE review',
          subtitle: 'Pending your decision',
          date: d['lastUpdated'],
          tag: 'Pending',
          tagColor: kOrange));
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  Widget _statBox(IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
      child: Row(
        children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 9.5, color: kMuted)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: color))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// RE-question / salesman-answer bubbles for the back-and-forth
  /// clarification thread (populated via the "Clarify" action → salesman
  /// answers from their linked task).
  Widget _clarificationThread(List messages) {
    if (messages.isEmpty) {
      return const Text('No messages yet.', style: TextStyle(fontSize: 11.5, color: kMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: messages.map<Widget>((m) {
        final isAnswer = m['authorRole'] == 'SALESPERSON';
        final c = isAnswer ? kGreen : _indigo;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment:
                isAnswer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(isAnswer ? 'Salesman' : 'RE',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c)),
              const SizedBox(height: 2),
              Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: c.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.withOpacity(0.25))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['body'] as String, style: const TextStyle(fontSize: 12, color: kDark)),
                    if ((m['attachmentPath'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      TaskAttachmentThumbnail(path: m['attachmentPath'] as String),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                  '${m['authorName']} · ${DateFormat('dd MMM, hh:mm a').format(m['createdAt'] as DateTime)}',
                  style: const TextStyle(fontSize: 9, color: kMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Same bottom-sheet shape as the resolution owner's "Message RE" —
  /// text plus an optional photo/PDF attachment on the RE's side of the
  /// same dispute thread (see task_details_screen_v3.dart's
  /// _disputeMessage, which the resolution owner uses to reply).
  void _sendMessage(BuildContext context, AppStore store, Map<String, dynamic> d) {
    final controller = TextEditingController();
    XFile? picked;
    bool busy = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(child: Text('Message resolution owner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navy))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(sheetCtx)),
              ]),
              const Text('Back-and-forth on this dispute — no decision is recorded.', style: TextStyle(fontSize: 11.5, color: kMuted)),
              const SizedBox(height: 12),
              TextField(controller: controller, maxLines: 3, autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Type a message…')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : () async {
                  final p = await pickEvidenceFile(sheetCtx);
                  if (p != null) setSheet(() => picked = p);
                },
                icon: Icon(picked == null ? Icons.attach_file : Icons.check, size: 15),
                label: Text(picked == null ? 'Attach photo or PDF' : 'Attached: ${picked!.name}', style: const TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: busy ? null : () async {
                    final body = controller.text.trim();
                    if (body.isEmpty) return;
                    setSheet(() => busy = true);
                    final navigator = Navigator.of(context);
                    try {
                      String? path;
                      if (picked != null) {
                        final b = await picked!.readAsBytes();
                        path = await store.apiClient.uploadAttachment(b, filename: picked!.name, contentType: picked!.mimeType ?? 'image/jpeg');
                      }
                      await store.postDisputeMessage(d['id'], body: body, attachmentPath: path);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      showAppMessageAfter(navigator, message: 'Message sent.');
                    } catch (e) {
                      setSheet(() => busy = false);
                      showAppMessageAfter(navigator, message: 'Could not send: $e', isError: true);
                    }
                  },
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
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
        title: const Text('Reject Dispute',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(
                hintText: 'Reason for rejection',
                border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              final navigator = Navigator.of(context);
              try {
                await store.rejectDispute(d['id'], reasonController.text.trim());
                onDecided();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
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

  void _clarify(BuildContext context, AppStore store, Map<String, dynamic> d) {
    // Default to the salesman who raised the dispute (the customer's
    // assigned salesperson) — not whoever sorts first alphabetically.
    final raiserId = store.customers
        .firstWhere((c) => c.name == d['customer'], orElse: () => store.customers.first)
        .assignedSalesmanId;
    final inRoster = store.salesmen.any((s) => s['name'] == raiserId);
    String selectedSalesman = inRoster
        ? raiserId
        : (store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '');
    final descController = TextEditingController();
    // A clarification is needed now, so this must land in the salesperson's
    // Today's Tasks, not tomorrow's — matches disputeService.js's own
    // defaultCallDeadline() fallback (today, unless already past 9 PM).
    final now = DateTime.now();
    DateTime deadline = now.hour >= 21
        ? DateTime(now.year, now.month, now.day + 1, 21)
        : DateTime(now.year, now.month, now.day, 21);
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Request Clarification',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: selectedSalesman,
                isExpanded: true,
                items: store.salesmen
                    .map<DropdownMenuItem<String>>((s) => DropdownMenuItem(
                        value: s['name'], child: Text((s['fullName'] as String?) ?? s['name'], overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => selectedSalesman = v);
                },
                decoration: const InputDecoration(
                    labelText: 'Assign to', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                      hintText: 'What information is needed?',
                      border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.requestDisputeInfo(d['id'], selectedSalesman,
                      descController.text.trim(), deadline);
                  onDecided();
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  showAppMessageAfter(navigator, message: 'Clarification requested from salesperson.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not request clarification: $e', isError: true);
                }
              },
              child:
                  const Text('Request', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }
}
