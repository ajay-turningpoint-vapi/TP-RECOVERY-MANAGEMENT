import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/models/outcome_edit_request.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/services/attachment_picker.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum TaskKind { realTask, visitReview, noCall, overdueTarget, dispute, ptpCorrection, outcomeEdit, ptpMissed, paymentClaim }

// overdueTarget used to be salesman-level (a "review this salesman" item
// with no specific account attached) — now customer-level, pointing at the
// underperforming salesman's actual worst overdue account (see
// re_tasks_screen.dart §5), same as every other real problem in this
// queue. noCall stays salesman-level (never generated as a real item
// today, kept for the view's own sake).
bool _isSalesmanLevel(TaskKind k) => k == TaskKind.noCall;

class UnifiedTaskDetailScreen extends StatelessWidget {
  final TaskKind kind;
  final String refId;
  const UnifiedTaskDetailScreen({super.key, required this.kind, required this.refId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (_isSalesmanLevel(kind)) {
      return _buildSalesmanView(context, store);
    }
    return _buildCustomerLevelView(context, store);
  }

  // -------------------------------------------------------------------
  // Salesman-level (No Call / Overdue Target)
  // -------------------------------------------------------------------
  Widget _buildSalesmanView(BuildContext context, AppStore store) {
    final s = store.salesmen.firstWhere((s) => s['name'] == refId, orElse: () => store.salesmen.first);
    final salesmanDisplay = (s['fullName'] as String?) ?? (s['name'] as String? ?? store.salesmanDisplayName(refId));
    final owned = store.customers.where((c) => c.assignedSalesmanId == refId).toList();
    final ownedIds = owned.map((c) => c.id).toSet();
    final ownedPtps = store.ptps.where((p) => ownedIds.contains(p.customerId)).toList();
    PromiseToPay? lastKept;
    for (final p in ownedPtps.where((p) => p.status == PtpStatus.kept)) {
      if (lastKept == null || p.promiseDate.isAfter(lastKept.promiseDate)) lastKept = p;
    }
    final avgDebtorDays = owned.isEmpty ? 0 : (owned.fold(0, (a, c) => a + c.oldestOverdueDays) / owned.length).round();
    final isNoCall = kind == TaskKind.noCall;
    final priority = isNoCall ? 'HIGH' : 'MEDIUM';
    final color = isNoCall ? kRed : kOrange;

    final notes = store.notesForItem(refId);
    final salesmanActions = <_ActionOption>[
      _ActionOption(Icons.call_outlined, kBlue, 'Contact Salesman', 'Call $refId directly for an update.', () => _contactSalesman(context, s)),
      _ActionOption(Icons.assignment_outlined, kNavy, 'Assign Task', 'Create a follow-up task tied to their top overdue customer.', () => _assignTask(context, store, s, owned)),
    ];
    final events = <TimelineEvent>[
      if (isNoCall)
        TimelineEvent(icon: Icons.phone_missed_outlined, color: kRed, title: 'No call made today', date: DateTime.now(), tag: 'High Priority', tagColor: kRed)
      else
        TimelineEvent(icon: Icons.trending_down, color: kOrange, title: 'Collection behind target', subtitle: '${s['collectionAchievedPercent']}% of ${_rupee.format(s['collectionTarget'])}', date: DateTime.now(), tag: 'Medium Priority', tagColor: kOrange),
      ...notes.map((n) => TimelineEvent(icon: Icons.sticky_note_2_outlined, color: kBlue, title: 'Note added', subtitle: n['note'], date: n['timestamp'], tag: n['author'], tagColor: kBlue)),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return RequestDetailScaffold(
      title: 'Task Details',
      subtitle: isNoCall ? 'Salesman No Call' : 'Overdue Target Review',
      bannerText: isNoCall ? 'Salesman has not connected with any overdue customer today.' : 'Salesman has not achieved today\'s collection target.',
      priorityLabel: '$priority PRIORITY',
      color: color,
      bannerIcon: isNoCall ? Icons.phone_missed_outlined : Icons.trending_down,
      actions: salesmanActions.map(_actionButton).toList(),
      children: [
        InfoCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 22, backgroundColor: avatarColorFor(salesmanDisplay).withOpacity(0.15), child: Text(initialsFor(salesmanDisplay), style: TextStyle(color: avatarColorFor(salesmanDisplay), fontWeight: FontWeight.bold))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(salesmanDisplay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
                    const SizedBox(height: 3),
                    Text('${s['customers']} Customers  ·  ${s['branch']} Branch', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                    const SizedBox(height: 2),
                    CallablePhoneNumber(phoneNumber: s['phone'] as String?, style: const TextStyle(fontSize: 10.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Overdue Amount', style: TextStyle(fontSize: 10, color: kMuted)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(s['totalOverdue']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kRed))),
                  Text('${owned.length} Overdue Customers', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('SALESMAN SUMMARY'),
        InfoCard(children: [
          KeyValueRow('Last PTP Kept', lastKept != null ? DateFormat('dd MMM yyyy').format(lastKept.promiseDate) : 'None yet'),
          KeyValueRow('PTP Kept % (MTD)', '${s['ptpKeptPercent']}%', valueColor: kRed),
          KeyValueRow('Avg Debtor Days', '$avgDebtorDays Days', valueColor: kOrange),
        ]),
        const SizedBox(height: 18),
        NotesSection(refId: refId),
        const SizedBox(height: 18),
        const SectionLabel('ACTIVITY / HISTORY'),
        ActivityTimeline(events),
      ],
    );
  }

  // Was a fake AlertDialog claiming "Calling $name at $phone…" with no
  // actual call ever placed — opens the real dialer now.
  void _contactSalesman(BuildContext context, Map<String, dynamic> s) {
    // Real Call/WhatsApp picker (see widgets/call_helper.dart), same as
    // every other phone number in the app — this used to jump straight to
    // the dialer with no WhatsApp option.
    contactActions(context, s['phone'] as String?);
  }

  void _assignTask(BuildContext context, AppStore store, Map<String, dynamic> s, List<Customer> owned) {
    if (owned.isEmpty) {
      showAppMessage(context, message: 'No customer available to attach this task to.');
      return;
    }
    owned.sort((a, b) => b.totalDue.compareTo(a.totalDue));
    final target = owned.first;
    final reasonController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 1));
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Assign Task', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Highest-priority account: ${target.name}', style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 12),
              TextField(controller: reasonController, decoration: const InputDecoration(hintText: 'Task instruction', border: OutlineInputBorder())),
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
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kNavy),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.assignManagementInstruction(target.id, s['name'], reasonController.text.trim(), deadline);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  showAppMessageAfter(navigator, message: 'Task assigned to ${(s['fullName'] as String?) ?? s['name']}.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not assign: $e', isError: true);
                }
              },
              child: const Text('Assign', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  // -------------------------------------------------------------------
  // Customer-level (real task / visit review / extension / dispute / ptp correction / outcome edit / ptp missed)
  // -------------------------------------------------------------------
  Widget _buildCustomerLevelView(BuildContext context, AppStore store) {
    late Customer customer;
    late String subtitle;
    late String bannerText;
    late String priority;
    late Color color;
    late IconData bannerIcon;
    late String description;
    late List<_ActionOption> actionOptions;
    AppTask? task;
    Map<String, dynamic>? dispute;
    PromiseToPay? ptp;
    OutcomeEditRequest? outcomeEdit;
    String? extraAttachmentPath; // evidence carried on a non-task record (payment claim, dispute…)

    switch (kind) {
      case TaskKind.realTask:
        task = store.tasks.firstWhere((t) => t.id == refId, orElse: () => store.tasks.first);
        customer = store.customers.firstWhere((c) => c.id == task!.customerId, orElse: () => store.customers.first);
        subtitle = taskTypeLabel(task.type);
        priority = task.priority == 'Critical' || task.priority == 'High' ? 'HIGH' : (task.priority == 'Normal' ? 'MEDIUM' : 'LOW');
        color = priority == 'HIGH' ? kRed : (priority == 'MEDIUM' ? kOrange : kBlue);
        bannerIcon = taskTypeIcon(task.type);
        bannerText = task.isOverdue ? 'This task is overdue — action is required.' : 'Due ${DateFormat('dd MMM, hh:mm a').format(task.deadline)}.';
        description = friendlyTaskReason(task.reason);
        if (task.type == TaskType.paymentVerification) {
          final claim = store.paymentClaims.cast<Map<String, dynamic>?>().firstWhere((p) => p != null && p['customer'] == customer.name, orElse: () => null);
          actionOptions = claim == null
              ? []
              : [
                  _ActionOption(Icons.check_circle_outline, kGreen, 'Verify Deposit', 'Reconcile ${_rupee.format(claim['amount'])} against BUSY.', () => _decideWithEvidence(context, refId: refId, title: 'Verify Deposit', accent: kGreen, submitLabel: 'Verify', action: (result) async => _verifyClaim(context, store, claim, true))),
                  _ActionOption(Icons.cancel_outlined, kRed, 'Fail Verification', 'No matching BUSY deposit found — return to recovery.', () => _decideWithEvidence(context, refId: refId, title: 'Fail Verification', accent: kRed, submitLabel: 'Fail', action: (result) async => _verifyClaim(context, store, claim, false))),
                ];
        } else if (task.type == TaskType.customerDetailCorrection) {
          actionOptions = [
            _ActionOption(Icons.edit_location_alt_outlined, kBlue, 'Update Customer Details', 'Correct contact number / address, then close this task.', () => _correctCustomerDetails(context, store, task!, customer)),
          ];
        } else if (task.type == TaskType.customerCall && task.source == 'Missed Deadline') {
          // The salesperson let their own auto-generated call task (due
          // 6 PM) lapse — this RE task (due 8 PM) exists specifically to
          // call THAT salesperson, not the customer.
          actionOptions = [
            _ActionOption(Icons.call_outlined, kBlue, 'Call Salesman', 'Find out why the scheduled call/visit was missed.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId))),
            _ActionOption(Icons.check_circle_outline, kGreen, 'Mark Done', 'Close this task out.', () => _completeTask(context, store, task!)),
          ];
        } else if (task.type == TaskType.customerCall && task.source == 'Refused Cycle') {
          // A Customer Refused case's 5-day non-response cadence just
          // cycled again with nothing recorded — alerts the RE to call the
          // salesperson. The salesperson's own reopening call task keeps
          // running independently; this doesn't touch it.
          actionOptions = [
            _ActionOption(Icons.call_outlined, kBlue, 'Call Salesman', 'A 5-day non-response cycle passed on this Customer Refused case with nothing recorded.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId))),
            _ActionOption(Icons.check_circle_outline, kGreen, 'Mark Done', 'Close this task out.', () => _completeTask(context, store, task!)),
          ];
        } else if (task.type == TaskType.financialTeamFollowUp && task.source == 'Record Outcome' && task.status != TaskStatus.completed && task.status != TaskStatus.closed) {
          // An "Internal Action" outcome — a real Approve/Reject decision,
          // not just generic complete/reschedule. Whichever way RE
          // decides, a call-customer follow-up is auto-created for the
          // salesperson (server-side).
          actionOptions = [
            _ActionOption(Icons.check_circle_outline, kGreen, 'Approve', 'This internal dependency is resolved — the salesperson gets a call-customer follow-up.', () => _approveInternalAction(context, store, task!)),
            _ActionOption(Icons.cancel_outlined, kRed, 'Reject', 'This internal action is not valid/needed — the salesperson still gets a call-customer follow-up.', () => _rejectInternalAction(context, store, task!)),
          ];
        } else {
          actionOptions = [
            _ActionOption(Icons.check_circle_outline, kGreen, 'Mark Completed', 'Close this task out.', () => _completeTask(context, store, task!)),
            _ActionOption(Icons.schedule, kBlue, 'Reschedule Deadline', 'Set a new deadline directly — RE approval is not required for RE\'s own changes.', () => _rescheduleTask(context, store, task!)),
          ];
        }
        break;
      case TaskKind.visitReview:
        task = store.tasks.firstWhere((t) => t.id == refId, orElse: () => store.tasks.first);
        customer = store.customers.firstWhere((c) => c.id == task!.customerId, orElse: () => store.customers.first);
        subtitle = 'Physical Visit — No Outcome Recorded';
        priority = 'MEDIUM';
        color = kPurple;
        bannerIcon = Icons.location_on_outlined;
        bannerText = 'The salesman closed this physical visit without recording an outcome.';
        description = friendlyTaskReason(task.reason);
        actionOptions = [
          _ActionOption(Icons.call_outlined, kBlue, 'Call Salesman', 'Ask them what happened on the visit.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId.isNotEmpty ? customer.assignedSalesmanId : task!.ownerId))),
          _ActionOption(Icons.add_task, kNavy, 'Create Task — Call Customer', 'Adds a call-customer task to the salesman\'s list for tomorrow, 9 PM.', () => _createVisitFollowUp(context, store, task!, customer)),
        ];
        break;
      case TaskKind.dispute:
        dispute = store.disputes.firstWhere((d) => d['id'] == refId, orElse: () => store.disputes.first);
        customer = store.customers.firstWhere((c) => c.name == dispute!['customer'], orElse: () => store.customers.first);
        subtitle = 'Dispute Awaiting Review';
        priority = (dispute['priority'] as String?) == 'High' ? 'HIGH' : 'MEDIUM';
        color = kIndigo;
        bannerIcon = Icons.description_outlined;
        final status = dispute['status'] as String;
        // Real server-side second-stage verification (disputeService.resolve)
        // becomes available only once the resolution owner has submitted
        // their work (status → Awaiting Verification), not as soon as the
        // RE approves.
        final needsVerification = status == 'Awaiting Verification';
        bannerText = needsVerification ? 'Resolution complete — verify against BUSY before closing.' : 'This dispute is awaiting your approval decision.';
        description = dispute['reason'];
        actionOptions = needsVerification
            ? [
                _ActionOption(Icons.verified_outlined, kGreen, 'Verify & Resolve', 'BUSY confirms payment — close the dispute.', () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.resolveDispute(dispute!['id'], 'Resolved');
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Dispute verified and resolved.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
                  }
                }),
                _ActionOption(Icons.undo, kOrange, 'Still Unpaid → Recovery', 'Return the disputed amount to active recovery.', () async {
                  final navigator = Navigator.of(context);
                  try {
                    await store.resolveDispute(dispute!['id'], 'Returned to Recovery');
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Returned to recovery.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
                  }
                }),
              ]
            : [
                _ActionOption(Icons.check_circle_outline, kGreen, 'Approve & Assign', 'Assign a resolution owner and deadline.', () => _approveDispute(context, store, dispute!)),
                _ActionOption(Icons.cancel_outlined, kRed, 'Reject', 'Dispute is not valid.', () => _rejectDispute(context, store, dispute!)),
                _ActionOption(Icons.help_outline, kBlue, 'Request Clarification', 'Ask the salesperson for more information.', () => _clarifyDispute(context, store, dispute!)),
              ];
        break;
      case TaskKind.ptpCorrection:
        ptp = store.ptps.firstWhere((p) => p.id == refId, orElse: () => store.ptps.first);
        customer = store.customers.firstWhere((c) => c.id == ptp!.customerId, orElse: () => store.customers.first);
        subtitle = 'PTP Correction Request';
        priority = 'MEDIUM';
        color = kTeal;
        bannerIcon = Icons.swap_horiz;
        bannerText = 'Salesperson requested a correction to this PTP commitment.';
        description = ptp.correctionReason ?? '-';
        actionOptions = [
          _ActionOption(Icons.check_circle_outline, kGreen, 'Approve Correction', 'Update the PTP to the requested amount/date.', () {
            _decideWithEvidence(context, refId: refId, title: 'Approve PTP Correction', accent: kGreen, submitLabel: 'Approve', action: (result) async {
              final navigator = Navigator.of(context);
              try {
                await store.approvePtpCorrection(ptp!.id);
                navigator.pop();
                showAppMessageAfter(navigator, message: 'PTP correction approved.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
              }
            });
          }),
          _ActionOption(Icons.cancel_outlined, kRed, 'Reject Correction', 'Keep the original PTP terms.', () {
            _decideWithEvidence(context, refId: refId, title: 'Reject PTP Correction', accent: kRed, submitLabel: 'Reject', action: (result) async {
              final navigator = Navigator.of(context);
              try {
                await store.rejectPtpCorrection(ptp!.id, result.note.isEmpty ? 'Not justified' : result.note);
                navigator.pop();
                showAppMessageAfter(navigator, message: 'PTP correction rejected.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
              }
            });
          }),
        ];
        break;
      case TaskKind.outcomeEdit:
        final req = store.outcomeEditRequests.firstWhere((r) => r.id == refId, orElse: () => store.outcomeEditRequests.first);
        outcomeEdit = req;
        customer = store.customers.firstWhere((c) => c.id == req.customerId, orElse: () => store.customers.first);
        subtitle = 'Outcome Edit Request';
        priority = 'LOW';
        color = kPink;
        bannerIcon = Icons.edit_note;
        bannerText = 'Salesperson requested an edit to a recorded outcome\'s values.';
        description = 'Edit ${req.outcomeKind} outcome — ${req.editReason}';
        actionOptions = [
          _ActionOption(Icons.check_circle_outline, kGreen, 'Approve Edit', 'Apply the edited values and re-run side effects.', () {
            _decideWithEvidence(context, refId: refId, title: 'Approve Outcome Edit', accent: kGreen, submitLabel: 'Approve', action: (result) async {
            final navigator = Navigator.of(context);
            try {
              await store.approveOutcomeEdit(req.id);
              navigator.pop();
              showAppMessageAfter(navigator, message: 'Outcome edit approved and applied.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
            }
            });
          }),
          _ActionOption(Icons.cancel_outlined, kRed, 'Reject Edit', 'Keep the recorded values unchanged.', () {
            _decideWithEvidence(context, refId: refId, title: 'Reject Outcome Edit', accent: kRed, submitLabel: 'Reject', action: (result) async {
            final navigator = Navigator.of(context);
            try {
              await store.rejectOutcomeEdit(req.id, result.note.isEmpty ? 'Not justified' : result.note);
              navigator.pop();
              showAppMessageAfter(navigator, message: 'Outcome edit rejected.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
            }
            });
          }),
        ];
        break;
      case TaskKind.ptpMissed:
        ptp = store.ptps.firstWhere((p) => p.id == refId, orElse: () => store.ptps.first);
        customer = store.customers.firstWhere((c) => c.id == ptp!.customerId, orElse: () => store.customers.first);
        subtitle = 'PTP Missed';
        priority = 'HIGH';
        color = kRed;
        bannerIcon = Icons.event_busy;
        bannerText = 'BUSY reconciliation found no qualifying payment for this PTP.';
        description = 'Promised ${_rupee.format(ptp.amountPromised)} on ${DateFormat('dd MMM yyyy').format(ptp.promiseDate)} — broken.';
        bannerText = 'BUSY reconciliation marked this PTP broken, and no follow-up task is open on the account.';
        actionOptions = [
          _ActionOption(Icons.add_task, kNavy, 'Create Task — Call Customer', 'Adds a call-customer task to the salesman\'s list for tomorrow, 9 PM.', () => _createCallTask(context, store, customer, 'Call customer — the PTP for ₹${ptp!.amountPromised.toStringAsFixed(0)} on "${customer.name}" was broken. Get a fresh commitment.', fallbackOwnerId: customer.assignedSalesmanId)),
          _ActionOption(Icons.person_outline, kBlue, 'View Customer 360', 'Review full PTP history, disputes and timeline.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer)))),
          _ActionOption(Icons.trending_up, kRed, 'Escalate Customer', 'Open an RE escalation case for this account.', () => _escalate(context, store, customer)),
        ];
        break;
      case TaskKind.paymentClaim:
        final claim = store.paymentClaims.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p != null && p['id'] == refId,
            orElse: () => null);
        customer = store.customers.firstWhere(
            (c) => c.id == (claim?['customerCode'] ?? ''),
            orElse: () => store.customers.isNotEmpty ? store.customers.first : customer);
        subtitle = 'Payment Already Made — Verify';
        priority = 'HIGH';
        color = kGreen;
        bannerIcon = Icons.receipt_long_outlined;
        bannerText =
            'The salesperson logged a payment the customer says they made. Check it against BUSY / with the operator, then confirm or reject — nothing moves until you do.';
        description = claim == null
            ? '-'
            : 'Claimed ${_rupee.format((claim['amount'] as num).toDouble())}'
                ' · Ref: ${claim['reference'] ?? '-'} · ${claim['date'] ?? ''}';
        extraAttachmentPath = claim?['attachmentPath'] as String?;
        actionOptions = claim == null
            ? []
            : [
                _ActionOption(Icons.check_circle_outline, kGreen, 'Confirm Payment',
                    'BUSY shows this deposit — reduce the customer\'s exposure by the amount.', () {
                  _decideWithEvidence(context, refId: refId, title: 'Confirm Payment', accent: kGreen, submitLabel: 'Confirm', action: (result) async {
                    final navigator = Navigator.of(context);
                    try {
                      await store.verifyPaymentClaim(refId, true);
                      navigator.pop();
                      showAppMessageAfter(navigator, message: 'Payment confirmed — exposure reduced.');
                    } catch (e) {
                      showAppMessageAfter(navigator, message: 'Could not confirm: $e', isError: true);
                    }
                  });
                }),
                _ActionOption(Icons.cancel_outlined, kRed, 'No Payment Found',
                    'No matching BUSY receipt — the amount stays in active recovery.', () {
                  _decideWithEvidence(context, refId: refId, title: 'Reject Payment Claim', accent: kRed, submitLabel: 'Reject', action: (result) async {
                    final navigator = Navigator.of(context);
                    try {
                      await store.verifyPaymentClaim(refId, false);
                      navigator.pop();
                      showAppMessageAfter(navigator, message: 'Claim rejected — amount stays in recovery.');
                    } catch (e) {
                      showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
                    }
                  });
                }),
              ];
        break;
      case TaskKind.overdueTarget:
        customer = store.customers.firstWhere((c) => c.id == refId, orElse: () => store.customers.first);
        subtitle = 'Underperforming Salesman — Top Account';
        priority = 'MEDIUM';
        color = kOrange;
        bannerIcon = Icons.trending_down;
        bannerText = '${store.salesmanDisplayName(customer.assignedSalesmanId)} has not achieved their collection target — this is their largest overdue account.';
        description = 'Overdue ${_rupee.format(customer.totalDue)} on ${customer.name}, ${customer.oldestOverdueDays} days overdue.';
        actionOptions = [
          _ActionOption(Icons.person_outline, kBlue, 'View Customer 360', 'Open the full account view and assign a task from there.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))), outlined: true),
          _ActionOption(Icons.call_outlined, kBlue, 'Contact Salesman', 'Call or WhatsApp the assigned salesperson about this account.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId)), outlined: true),
          _ActionOption(Icons.check_circle_outline, kGreen, 'Mark Complete', 'Clears this salesman for today. It returns tomorrow if they are still below target.', () => _dismissUnderperformance(context, store, customer.assignedSalesmanId)),
        ];
        break;
      default:
        customer = store.customers.isNotEmpty
            ? store.customers.first
            : Customer(
                id: '',
                name: '—',
                totalOutstanding: 0,
                totalDue: 0,
                oldestOverdueDays: 0,
                currentRecoveryState: '',
                primaryNextAction: '',
                reasonForAction: '',
                assignedSalesmanId: '',
              );
        subtitle = '';
        bannerText = '';
        priority = 'LOW';
        color = kMuted;
        bannerIcon = Icons.help_outline;
        description = '';
        actionOptions = [];
    }

    final overdueInvoices = customer.invoices.where((i) => (i['status'] as String).toLowerCase().contains('overdue')).length;
    final notes = store.notesForItem(refId);
    final attachments = store.attachmentsForItem(refId);
    final requestDetail = _requestDetailSection(store, kind, task: task, ptp: ptp, dispute: dispute, outcomeEdit: outcomeEdit);
    final events = customer.auditHistory.reversed
        .map((a) => TimelineEvent(icon: Icons.history, color: kMuted, title: a.type, subtitle: a.description, date: a.timestamp, tag: a.actor, tagColor: kBlue))
        .take(5)
        .toList()
      ..addAll(notes.map((n) => TimelineEvent(icon: Icons.sticky_note_2_outlined, color: kBlue, title: 'Note added', subtitle: n['note'], date: n['timestamp'], tag: n['author'], tagColor: kBlue)))
      ..sort((a, b) => b.date.compareTo(a.date));

    return RequestDetailScaffold(
      title: 'Task Details',
      subtitle: subtitle,
      bannerText: bannerText,
      priorityLabel: '$priority PRIORITY',
      color: color,
      bannerIcon: bannerIcon,
      actions: actionOptions.map(_actionButton).toList(),
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
                    CallablePhoneNumber(phoneNumber: customer.contactNumber, iconSize: 12, style: const TextStyle(fontSize: 10.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Outstanding', style: TextStyle(fontSize: 10, color: kMuted)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(customer.totalOutstanding), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kRed))),
                  Text('${customer.oldestOverdueDays} Days Overdue  ·  $overdueInvoices Invoices', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('CUSTOMER SUMMARY'),
        InfoCard(children: [
          KeyValueRow('Last Payment', customer.lastPaymentDate != null ? '${_rupee.format(customer.lastPaymentAmount ?? 0)} on ${DateFormat('dd MMM yyyy').format(customer.lastPaymentDate!)}' : 'None recorded'),
          KeyValueRow('Credit Days', '${customer.creditDays} Days'),
          KeyValueRow('Overdue Days', '${customer.oldestOverdueDays} Days', valueColor: kOrange),
          // The customer's assigned salesperson — NOT task.ownerId, which
          // for an Internal Action task is the RE the task was routed to.
          if (customer.assignedSalesmanId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 118, child: Text('Salesman', style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500))),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(store.salesmanDisplayName(customer.assignedSalesmanId),
                              textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId)),
                          child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.call, size: 16, color: kBlue)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('WHAT THE SALESPERSON RECORDED'),
        InfoCard(children: [Text(description, style: const TextStyle(fontSize: 12.5, color: kDark, height: 1.4))]),
        // Per-kind breakdown: exactly what is being requested / what
        // changed, so the RE can decide without opening another screen.
        ...requestDetail,
        // Real decision detail + evidence carried on the task itself — the
        // auto-created "call customer" follow-up after RE approves/rejects
        // a Payment Already Made / Dispute / Internal Action outcome.
        if (task != null && (task.note?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 18),
          const SectionLabel('NOTE'),
          InfoCard(children: [Text(task.note!, style: const TextStyle(fontSize: 12.5, color: kDark))]),
        ],
        if (task != null && (task.attachmentPath?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 18),
          const SectionLabel('EVIDENCE ATTACHMENT'),
          InfoCard(children: [TaskAttachmentThumbnail(path: task.attachmentPath!)]),
        ],
        if (extraAttachmentPath != null && extraAttachmentPath.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionLabel('EVIDENCE ATTACHMENT'),
          InfoCard(children: [TaskAttachmentThumbnail(path: extraAttachmentPath)]),
        ],
        // History only — new evidence/notes are captured inside the
        // Approve/Reject form (showApproveRejectForm), not here. Each
        // section is hidden entirely when it has nothing to show.
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 18),
          AttachmentsSection(refId: refId, readOnly: true),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 18),
          NotesSection(refId: refId, readOnly: true),
        ],
        if (events.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionLabel('ACTIVITY / HISTORY'),
          ActivityTimeline(events),
        ],
      ],
    );
  }

  Future<void> _completeTask(BuildContext context, AppStore store, AppTask t) async {
    // A Physical Visit is a real in-person visit — the server rejects a
    // bare completion with no photo, so ask for one up front rather than
    // letting the salesman hit the generic error.
    XFile? visitPhoto;
    if (t.type == TaskType.physicalVisit) {
      visitPhoto = await pickEvidenceFile(context);
      if (visitPhoto == null) return; // salesman cancelled the picker — don't complete
      if (!context.mounted) return;
    }
    final navigator = Navigator.of(context);
    try {
      await store.completeTask(t.id, visitPhoto: visitPhoto);
      navigator.pop();
      showAppMessageAfter(navigator, message: t.type == TaskType.financialTeamFollowUp ? 'Task completed. Customer remains in recovery until financial exposure clears.' : 'Task marked completed.');
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not complete task: $e', isError: true);
    }
  }

  void _rescheduleTask(BuildContext context, AppStore store, AppTask t) {
    DateTime newDeadline = t.deadline.add(const Duration(days: 1));
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reschedule Task Deadline', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current deadline: ${DateFormat('dd MMM, hh:mm a').format(t.deadline)}', style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: newDeadline, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (picked != null) setState(() => newDeadline = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('dd MMM yyyy').format(newDeadline)), const Icon(Icons.calendar_today, size: 16)]),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: reasonController, decoration: const InputDecoration(hintText: 'Reason', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBlue),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.rescheduleTask(t.id, reasonController.text.trim(), newDeadline);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  showAppMessageAfter(navigator, message: 'Task rescheduled.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not reschedule: $e', isError: true);
                }
              },
              child: const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _dismissUnderperformance(BuildContext context, AppStore store, String salesmanId) async {
    final navigator = Navigator.of(context);
    try {
      await store.dismissUnderperformance(salesmanId);
      navigator.pop();
      showAppMessageAfter(navigator, message: 'Marked complete for today. It will return tomorrow if ${store.salesmanDisplayName(salesmanId)} is still below target.');
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not mark complete: $e', isError: true);
    }
  }

  Future<void> _createVisitFollowUp(BuildContext context, AppStore store, AppTask t, Customer customer) =>
      _createCallTask(context, store, customer,
          'Call customer — no outcome was recorded for the physical visit on "${customer.name}".',
          fallbackOwnerId: t.ownerId);

  /// Creates a plain call-customer task for the customer's salesman, due
  /// tomorrow 9:00 PM. Used where an automatic follow-up wasn't created
  /// (visit with no outcome, a broken PTP with nothing open).
  Future<void> _createCallTask(BuildContext context, AppStore store, Customer customer, String reason,
      {String fallbackOwnerId = ''}) async {
    final navigator = Navigator.of(context);
    final salesmanId = customer.assignedSalesmanId.isNotEmpty ? customer.assignedSalesmanId : fallbackOwnerId;
    final now = DateTime.now();
    final deadline = DateTime(now.year, now.month, now.day + 1, 21); // tomorrow 9:00 PM
    try {
      await store.assignManagementInstruction(
        customer.id,
        salesmanId,
        reason,
        deadline,
        priority: 'Normal',
        taskType: 'customerCall',
      );
      navigator.pop();
      showAppMessageAfter(navigator, message: 'Call-customer task created for ${store.salesmanDisplayName(salesmanId)} — due tomorrow 9 PM.');
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not create task: $e', isError: true);
    }
  }

  Future<void> _verifyClaim(BuildContext context, AppStore store, Map<String, dynamic> claim, bool success) async {
    final navigator = Navigator.of(context);
    try {
      await store.verifyPaymentClaim(claim['id'], success);
      navigator.pop();
      showAppMessageAfter(navigator, message: success ? 'Payment verified successfully.' : 'Verification failed — customer returned to recovery.');
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not verify: $e', isError: true);
    }
  }

  void _correctCustomerDetails(BuildContext context, AppStore store, AppTask t, Customer customer) {
    final contactController = TextEditingController(text: customer.contactNumber);
    final altController = TextEditingController(text: customer.alternateContactNumber);
    final branchController = TextEditingController(text: customer.branch);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update Customer Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contact Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(controller: contactController, decoration: const InputDecoration(border: OutlineInputBorder()), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            const Text('Alternate Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(controller: altController, decoration: const InputDecoration(border: OutlineInputBorder()), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            const Text('Branch / Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(controller: branchController, decoration: const InputDecoration(border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBlue),
            onPressed: () async {
              final navigator = Navigator.of(context);
              store.updateCustomerContactDetails(
                customer.id,
                contactNumber: contactController.text.trim(),
                alternateContactNumber: altController.text.trim(),
                branch: branchController.text.trim(),
              );
              try {
                await store.completeTask(t.id);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Customer details updated and task closed.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not complete task: $e', isError: true);
              }
            },
            child: const Text('Save & Complete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _approveDispute(BuildContext context, AppStore store, Map<String, dynamic> d) {
    _decideWithEvidence(
      context,
      refId: d['id'] as String,
      title: 'Approve Dispute',
      accent: kGreen,
      submitLabel: 'Continue',
      action: (result) async => _approveDisputeAssign(context, store, d),
    );
  }

  void _approveDisputeAssign(BuildContext context, AppStore store, Map<String, dynamic> d) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
    final descController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 2));
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Dispute & Assign', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.approveDispute(d['id'], selectedSalesman, deadline, descController.text.trim());
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  navigator.pop();
                  showAppMessageAfter(navigator, message: 'Dispute approved and assigned.');
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

  void _rejectDispute(BuildContext context, AppStore store, Map<String, dynamic> d) {
    _decideWithEvidence(
      context,
      refId: d['id'] as String,
      title: 'Reject Dispute',
      accent: kRed,
      submitLabel: 'Reject',
      action: (result) async {
        final navigator = Navigator.of(context);
        try {
          await store.rejectDispute(d['id'], result.note.isEmpty ? 'Rejected' : result.note);
          navigator.pop();
          showAppMessageAfter(navigator, message: 'Dispute rejected.');
        } catch (e) {
          showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
        }
      },
    );
  }

  void _approveInternalAction(BuildContext context, AppStore store, AppTask task) {
    _decideWithEvidence(
      context,
      refId: task.id,
      title: 'Approve Internal Action',
      accent: kGreen,
      submitLabel: 'Approve',
      action: (result) async {
        final navigator = Navigator.of(context);
        try {
          await store.approveInternalAction(task.id, note: result.note.isEmpty ? null : result.note, attachmentPath: result.attachmentPath);
          navigator.pop();
          showAppMessageAfter(navigator, message: 'Internal action approved — the salesperson has a new follow-up call task.');
        } catch (e) {
          showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
        }
      },
    );
  }

  void _rejectInternalAction(BuildContext context, AppStore store, AppTask task) {
    _decideWithEvidence(
      context,
      refId: task.id,
      title: 'Reject Internal Action',
      accent: kRed,
      submitLabel: 'Reject',
      action: (result) async {
        final navigator = Navigator.of(context);
        try {
          await store.rejectInternalAction(task.id, reason: result.note.isEmpty ? null : result.note, attachmentPath: result.attachmentPath);
          navigator.pop();
          showAppMessageAfter(navigator, message: 'Internal action rejected — the salesperson has a new follow-up call task.');
        } catch (e) {
          showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
        }
      },
    );
  }

  void _clarifyDispute(BuildContext context, AppStore store, Map<String, dynamic> d) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Request Clarification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
              TextField(controller: descController, decoration: const InputDecoration(hintText: 'What information is needed?', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.requestDisputeInfo(d['id'], selectedSalesman, descController.text.trim(), deadline);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  navigator.pop();
                  showAppMessageAfter(navigator, message: 'Clarification requested.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not request clarification: $e', isError: true);
                }
              },
              child: const Text('Request', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  void _escalate(BuildContext context, AppStore store, Customer customer) {
    final nextLevel = customer.escalationLevel == 'none' || customer.escalationLevel == 'L1' ? 'L2' : (customer.escalationLevel == 'L2' ? 'L3' : 'L4');
    final planController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 2));
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Escalate to $nextLevel', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: planController, decoration: const InputDecoration(hintText: 'Plan', border: OutlineInputBorder()), maxLines: 2),
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
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kRed),
              onPressed: () async {
                if (planController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  await store.escalateCustomer(customer.id, nextLevel, 'Broken PTP', planController.text.trim(), store.currentSalesmanId, deadline);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  navigator.pop();
                  showAppMessageAfter(navigator, message: 'Escalated to $nextLevel.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not escalate: $e', isError: true);
                }
              },
              child: const Text('Escalate', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  /// Opens the attachments + notes form for an Approve/Reject decision,
  /// then runs [action] only if the RE actually submitted it. The form
  /// stores the evidence against [refId] (shown afterwards in the
  /// read-only ATTACHMENTS / NOTES sections and the activity timeline).
  Future<void> _decideWithEvidence(
    BuildContext context, {
    required String refId,
    required String title,
    required Color accent,
    required String submitLabel,
    required Future<void> Function(ApproveRejectResult result) action,
  }) async {
    final result = await showApproveRejectForm(
      context,
      refId: refId,
      title: title,
      accent: accent,
      submitLabel: submitLabel,
    );
    if (result == null) return;
    await action(result);
  }

  // Every task action is now a real button pinned to the bottom bar (see
  // RequestDetailScaffold.actions) — a destructive action (red) is an
  // outlined button, everything else is filled in its accent colour.
  // Wrapped in Loading*Button so the button itself holds a spinner for the
  // whole of o.onTap() — including, for the approve/reject flows, the gap
  // between the evidence form closing and the real network call finishing,
  // which previously had no visible feedback at all.
  Widget _actionButton(_ActionOption o) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(o.icon, size: 17),
        const SizedBox(width: 8),
        Flexible(
          child: Text(o.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
        ),
      ],
    );
    if (o.color == kRed || o.outlined) {
      return LoadingOutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: o.color,
          side: BorderSide(color: o.color, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () async => await o.onTap(),
        child: child,
      );
    }
    return LoadingElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: o.color,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () async => await o.onTap(),
      child: child,
    );
  }

  // ---- Per-kind "what is being requested" breakdown -------------------

  String _fmtVal(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v == v.roundToDouble() ? _rupee.format(v) : v.toString();
    final asDate = DateTime.tryParse(v.toString());
    if (asDate != null) return DateFormat('dd MMM yyyy, hh:mm a').format(asDate.toLocal());
    return v.toString();
  }

  Widget _diffCard(Map<String, dynamic> oldP, Map<String, dynamic> newP) {
    final keys = {...oldP.keys, ...newP.keys}.toList();
    final pretty = {
      'amount': 'Amount',
      'promiseDate': 'Promise date',
      'date': 'Date',
      'deadline': 'Deadline',
      'paymentMode': 'Payment mode',
      'reason': 'Reason',
      'reference': 'Reference',
      'claimDate': 'Claim date',
      'nextAction': 'Next action',
    };
    final rows = <Widget>[];
    for (final k in keys) {
      final o = _fmtVal(oldP[k]);
      final n = _fmtVal(newP[k]);
      final changed = o != n;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(pretty[k] ?? k, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500))),
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Text(o, style: TextStyle(fontSize: 12, color: changed ? kMuted : kDark, decoration: changed ? TextDecoration.lineThrough : null))),
                  if (changed) ...[
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 12, color: kMuted)),
                    Flexible(child: Text(n, style: const TextStyle(fontSize: 12.5, color: kGreen, fontWeight: FontWeight.bold))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ));
    }
    return InfoCard(children: rows);
  }

  List<Widget> _requestDetailSection(
    AppStore store,
    TaskKind kind, {
    AppTask? task,
    PromiseToPay? ptp,
    Map<String, dynamic>? dispute,
    OutcomeEditRequest? outcomeEdit,
  }) {
    switch (kind) {
      case TaskKind.outcomeEdit:
        if (outcomeEdit == null) return const [];
        return [
          const SizedBox(height: 18),
          const SectionLabel('REQUEST DETAILS'),
          InfoCard(children: [
            KeyValueRow('Outcome type', outcomeEdit.outcomeKind),
            KeyValueRow('Requested by', store.salesmanDisplayName(outcomeEdit.salesmanId)),
            KeyValueRow('Requested on', DateFormat('dd MMM yyyy, hh:mm a').format(outcomeEdit.requestedAt)),
            KeyValueRow('Reason given', outcomeEdit.editReason.isEmpty ? '—' : outcomeEdit.editReason),
          ]),
          const SizedBox(height: 12),
          const SectionLabel('REQUESTED CHANGE  (CURRENT → NEW)'),
          _diffCard(outcomeEdit.originalPayload, outcomeEdit.requestedPayload),
        ];
      case TaskKind.ptpCorrection:
        if (ptp == null) return const [];
        final curMode = ptp.paymentMode;
        final newMode = ptp.correctionRequestedPaymentMode ?? ptp.paymentMode;
        return [
          const SizedBox(height: 18),
          const SectionLabel('REQUESTED CORRECTION  (CURRENT → NEW)'),
          _diffCard(
            {'amount': ptp.amountPromised, 'promiseDate': ptp.promiseDate.toIso8601String(), 'paymentMode': curMode},
            {
              'amount': ptp.correctionRequestedAmount ?? ptp.amountPromised,
              'promiseDate': (ptp.correctionRequestedDate ?? ptp.promiseDate).toIso8601String(),
              'paymentMode': newMode,
            },
          ),
          const SizedBox(height: 12),
          const SectionLabel('WHY'),
          InfoCard(children: [Text(ptp.correctionReason ?? '—', style: const TextStyle(fontSize: 12.5, color: kDark, height: 1.4))]),
        ];
      case TaskKind.dispute:
        if (dispute == null) return const [];
        return [
          const SizedBox(height: 18),
          const SectionLabel('DISPUTE DETAILS'),
          InfoCard(children: [
            KeyValueRow('Disputed amount', _rupee.format((dispute['amount'] as num?) ?? 0), valueColor: kRed),
            KeyValueRow('Priority', (dispute['priority'] as String?) ?? '—'),
            KeyValueRow('Status', (dispute['status'] as String?) ?? '—'),
            if (dispute['invoiceNumber'] != null) KeyValueRow('Invoice', dispute['invoiceNumber'].toString()),
            KeyValueRow('Reason', (dispute['reason'] as String?) ?? '—'),
          ]),
        ];
      case TaskKind.ptpMissed:
        if (ptp == null) return const [];
        return [
          const SizedBox(height: 18),
          const SectionLabel('BROKEN PTP'),
          InfoCard(children: [
            KeyValueRow('Amount promised', _rupee.format(ptp.amountPromised)),
            KeyValueRow('Promised for', DateFormat('dd MMM yyyy').format(ptp.promiseDate)),
            KeyValueRow('Payment mode', ptp.paymentMode),
          ]),
        ];
      case TaskKind.realTask:
      case TaskKind.visitReview:
        if (task == null) return const [];
        return [
          const SizedBox(height: 18),
          const SectionLabel('TASK DETAILS'),
          InfoCard(children: [
            KeyValueRow('Type', taskTypeLabel(task.type)),
            KeyValueRow('Priority', task.priority),
            KeyValueRow('Deadline', DateFormat('dd MMM yyyy, hh:mm a').format(task.deadline)),
            if (task.source.isNotEmpty) KeyValueRow('Raised from', task.source),
          ]),
        ];
      default:
        return const [];
    }
  }
}

class _ActionOption {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  // FutureOr, not VoidCallback — most of these ultimately trigger a real
  // network/SQLite write (directly, or via a dialog's own submit), and the
  // shared _actionButton awaits this to hold a spinner on the button for
  // its whole duration instead of the button looking dead mid-request.
  final FutureOr<void> Function() onTap;
  // Secondary/informational actions (navigate, contact) render outlined so
  // only the one real primary action (e.g. Mark Complete) stands out as a
  // solid button — matching the rest of the app's CTA hierarchy instead of
  // stacking several equally-loud solid-color buttons.
  final bool outlined;
  _ActionOption(this.icon, this.color, this.title, this.description, this.onTap, {this.outlined = false});
}

// Task attachments render via request_detail_scaffold.dart's shared
// TaskAttachmentThumbnail (image thumbnail + PDF download-and-open).
