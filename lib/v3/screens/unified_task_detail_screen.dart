import 'dart:async';
import 'package:flutter/material.dart';
import 'package:salesman_mobile/v3/screens/task_details_screen_v3.dart' show plainTask;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/services/attachment_picker.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum TaskKind { realTask, visitReview, noCall, overdueTarget, dispute, ptpCorrection, ptpMissed, paymentClaim }

// overdueTarget used to be salesman-level (a "review this salesman" item
// with no specific account attached) — now customer-level, pointing at the
// underperforming salesman's actual worst overdue account (see
// re_tasks_screen.dart §5), same as every other real problem in this
// queue. noCall stays salesman-level (never generated as a real item
// today, kept for the view's own sake).
/// Default RE review deadline for anything a salesman raises (dispute, PTP
/// correction, outcome edit, payment claim): 9 PM the day it was raised.
DateTime _reviewDeadlineFor(DateTime raisedOn) => DateTime(raisedOn.year, raisedOn.month, raisedOn.day, 21);

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

  /// Used only when a task's customer isn't in store.customers anymore
  /// (e.g. paid off / closed and dropped out of BUSY's feed — see
  /// customerRepository's ACTIVE_FILTER). Built from the task's OWN stored
  /// fields, which stay accurate regardless — never substitutes a
  /// different, unrelated customer the way `orElse: () => store.customers.first`
  /// used to.
  /// Stand-in when a request's customer isn't in the active list (removed
  /// from BUSY) — shows that request's own id/name, never another customer.
  Customer _placeholderCustomer(String id, String name) => Customer(
        id: id,
        name: name,
        totalOutstanding: 0,
        totalDue: 0,
        oldestOverdueDays: 0,
        currentRecoveryState: '',
        primaryNextAction: '',
        reasonForAction: '',
        assignedSalesmanId: '',
      );

  Customer _taskCustomerFallback(AppTask t) {
    return Customer(
      id: t.customerId,
      name: t.customerName,
      totalOutstanding: 0,
      totalDue: 0,
      oldestOverdueDays: 0,
      currentRecoveryState: '',
      primaryNextAction: '',
      reasonForAction: '',
      assignedSalesmanId: t.ownerId,
    );
  }

  Widget _notFoundScaffold(BuildContext context, String message) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kNavy,
        title: const Text('Task Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 48, color: kMuted),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: kMuted)),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      ),
    );
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

    final salesmanActions = <_ActionOption>[
      _ActionOption(Icons.call_outlined, kBlue, 'Contact Salesman', 'Call $refId directly for an update.', () => _contactSalesman(context, s)),
      _ActionOption(Icons.assignment_outlined, kNavy, 'Assign Task', 'Create a follow-up task tied to their top overdue customer.', () => _assignTask(context, store, s, owned)),
    ];

    return RequestDetailScaffold(
      title: 'Task Details',
      subtitle: isNoCall ? 'Salesman No Call' : 'Overdue Target Review',
      bannerText: isNoCall ? 'Salesman made no calls today.' : 'Salesman is behind today\'s collection target.',
      priorityLabel: '$priority PRIORITY',
      color: color,
      bannerIcon: isNoCall ? Icons.phone_missed_outlined : Icons.trending_down,
      actions: salesmanActions.map(_actionButton).toList(),
      children: [
        InfoCard(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 22, backgroundColor: avatarColorFor(salesmanDisplay).withValues(alpha: 0.15), child: Text(initialsFor(salesmanDisplay), style: TextStyle(color: avatarColorFor(salesmanDisplay), fontWeight: FontWeight.bold))),
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
        TodoCallout(isNoCall
            ? 'Call $salesmanDisplay and ask why no calls were made, or tap Assign Task.'
            : 'Call $salesmanDisplay about their collections, or tap Assign Task.'),
        const SizedBox(height: 18),
        NotesSection(refId: refId),
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
    XFile? attachmentFile;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Assign Task', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: attachmentFile != null ? kGreen : null),
                  onPressed: () async {
                    final file = await pickEvidenceFile(context);
                    if (file != null) setState(() => attachmentFile = file);
                  },
                  icon: Icon(attachmentFile != null ? Icons.check : Icons.attach_file),
                  label: Text(attachmentFile != null ? 'Attached: ${attachmentFile!.name}' : 'Attach Image / PDF (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kNavy),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                try {
                  String? attachmentPath;
                  if (attachmentFile != null) {
                    final bytes = await attachmentFile!.readAsBytes();
                    attachmentPath = await store.apiClient
                        .uploadAttachment(bytes, filename: attachmentFile!.name, contentType: attachmentFile!.mimeType ?? 'image/jpeg');
                  }
                  await store.assignManagementInstruction(target.id, s['name'], reasonController.text.trim(), deadline, attachmentPath: attachmentPath);
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
    // A task can legitimately be missing from store.tasks by the time this
    // screen opens (synced data moved on since the list that linked here
    // was built). `.firstWhere(..., orElse: () => store.tasks.first)` used
    // to silently substitute a COMPLETELY unrelated task as a stand-in —
    // wrong customer, wrong salesman, wrong "what the salesperson
    // recorded" text, all internally consistent with each other and so
    // looking entirely plausible, which is exactly what makes it
    // dangerous: an RE could act on the wrong account without any sign
    // something was off. Show an honest "not found" screen instead.
    if ((kind == TaskKind.realTask || kind == TaskKind.visitReview) &&
        !store.tasks.any((t) => t.id == refId)) {
      return _notFoundScaffold(context, 'This task could not be found anymore — it may have already been resolved, reassigned, or removed.');
    }
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
    DateTime? dueDate; // shown in the Due bar; null (e.g. overdueTarget) hides it
    String? extraAttachmentPath; // evidence carried on a non-task record (payment claim, dispute…)

    switch (kind) {
      case TaskKind.realTask:
        task = store.tasks.firstWhere((t) => t.id == refId, orElse: () => store.tasks.first);
        customer = store.customers.firstWhere((c) => c.id == task!.customerId, orElse: () => _taskCustomerFallback(task!));
        // Fire-and-forget: if the customer wasn't found above (inactive —
        // see _taskCustomerFallback's doc comment), fetch the real one.
        // Resolves after this build finishes; notifyListeners then
        // rebuilds with the real name/salesman/phone in place of the
        // placeholder.
        store.ensureCustomerLoaded(task.customerId);
        subtitle = taskTypeLabel(task.type);
        priority = task.priority == 'Critical' || task.priority == 'High' ? 'HIGH' : (task.priority == 'Normal' ? 'MEDIUM' : 'LOW');
        color = priority == 'HIGH' ? kRed : (priority == 'MEDIUM' ? kOrange : kBlue);
        bannerIcon = taskTypeIcon(task.type);
        // The due date/time and "Overdue by …" live in the Due strip below
        // the banner — the banner itself only says what state the task is
        // in, so the deadline isn't printed three times on one screen.
        final isDoneTask = task.status == TaskStatus.completed || task.status == TaskStatus.closed;
        bannerText = isDoneTask
            ? 'Completed${task.completedAt != null ? ' on ${DateFormat('dd MMM yyyy, hh:mm a').format(task.completedAt!)}' : ''}${(task.outcome?.trim().isNotEmpty ?? false) ? ' — ${task.outcome!.trim()}' : '.'}'
            : (task.isOverdue ? 'This task is overdue — action is required.' : 'Open — action required by the due date below.');
        // A finished task is not "overdue" — no Due strip for it.
        dueDate = isDoneTask ? null : task.deadline;
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
        } else if (task.type == TaskType.physicalVisit && task.source == 'Record Outcome') {
          // Salesman-requested visit (Internal Action → "Physical Visit",
          // see customerService.applyOutcome) — distinct from the
          // 3rd-No-Answer physicalVisit task, which is owned by the
          // salesperson and never reaches this RE-only screen with this
          // source. Closing it requires BOTH a photo and notes
          // (taskService.completeTask enforces this server-side too).
          actionOptions = [
            _ActionOption(Icons.check_circle_outline, kGreen, 'Complete Visit', 'Attach a photo and notes from the visit — both required.', () => _completeVisit(context, store, task!)),
            _ActionOption(Icons.cancel_outlined, kRed, 'Reject Visit', 'Could not carry out the visit — a reason is required.', () => _rejectVisit(context, store, task!)),
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
        // A completed/closed task is history, not a request waiting on
        // the RE — none of the branches above check this, so every
        // action (Mark Completed, Call Salesman, Approve/Reject, …) was
        // still offered on a task that's already done, as if it still
        // needed a decision. Override to no actions here rather than
        // threading the check through each branch above.
        if (task.status == TaskStatus.completed || task.status == TaskStatus.closed) {
          actionOptions = [];
        }
        break;
      case TaskKind.visitReview:
        task = store.tasks.firstWhere((t) => t.id == refId, orElse: () => store.tasks.first);
        customer = store.customers.firstWhere((c) => c.id == task!.customerId, orElse: () => _taskCustomerFallback(task!));
        store.ensureCustomerLoaded(task.customerId);
        subtitle = 'Physical Visit — No Outcome Recorded';
        priority = 'MEDIUM';
        color = kPurple;
        bannerIcon = Icons.location_on_outlined;
        bannerText = 'The salesman closed this physical visit without recording an outcome.';
        dueDate = task.deadline;
        description = friendlyTaskReason(task.reason);
        actionOptions = [
          _ActionOption(Icons.call_outlined, kBlue, 'Call Salesman', 'Ask them what happened on the visit.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId.isNotEmpty ? customer.assignedSalesmanId : task!.ownerId))),
          _ActionOption(Icons.add_task, kNavy, 'Create Task — Call Customer', 'Adds a call-customer task to the salesman\'s list for tomorrow, 9 PM.', () => _createVisitFollowUp(context, store, task!, customer)),
        ];
        break;
      case TaskKind.dispute:
        dispute = store.disputes.firstWhere((d) => d['id'] == refId, orElse: () => store.disputes.first);
        customer = store.customers.firstWhere((c) => c.id == '${dispute!['customerCode']}', orElse: () => _placeholderCustomer('${dispute!['customerCode']}', '${dispute['customer']}'));
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
        dueDate = _reviewDeadlineFor((dispute['raisedDate'] as DateTime?) ?? DateTime.now());
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
        customer = store.customers.firstWhere((c) => c.id == ptp!.customerId, orElse: () => _placeholderCustomer(ptp!.customerId, ptp.customerId));
        subtitle = 'PTP Correction Request';
        priority = 'MEDIUM';
        color = kTeal;
        bannerIcon = Icons.swap_horiz;
        bannerText = 'Salesperson requested a correction to this PTP commitment.';
        dueDate = _reviewDeadlineFor(ptp.correctionRequestedDate ?? ptp.promiseDate);
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
      case TaskKind.ptpMissed:
        ptp = store.ptps.firstWhere((p) => p.id == refId, orElse: () => store.ptps.first);
        customer = store.customers.firstWhere((c) => c.id == ptp!.customerId, orElse: () => _placeholderCustomer(ptp!.customerId, ptp.customerId));
        subtitle = 'PTP Missed';
        dueDate = ptp.promiseDate;
        priority = 'HIGH';
        color = kRed;
        bannerIcon = Icons.event_busy;
        bannerText = 'BUSY reconciliation found no qualifying payment for this PTP.';
        description = 'Promised ${_rupee.format(ptp.amountPromised)} for ${DateFormat('dd MMM').format(ptp.promiseDate)} (${ptp.paymentMode}) — not paid.';
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
            orElse: () => _placeholderCustomer('${claim?['customerCode'] ?? ''}', '${claim?['customer'] ?? 'Customer'}'));
        subtitle = 'Payment Already Made — Verify';
        priority = 'HIGH';
        color = kGreen;
        bannerIcon = Icons.receipt_long_outlined;
        bannerText = 'Salesman says the customer has paid.';
        dueDate = _reviewDeadlineFor((claim?['claimDateRaw'] as DateTime?) ?? DateTime.now());
        // Just the claimed amount — the salesman is already shown
        // separately as "Salesman" below, and a real reference (when the
        // salesperson gave one) shows as its own line via claim['reference'].
        description = claim == null ? '-' : 'Claimed ${_rupee.format((claim['amount'] as num).toDouble())}';
        final claimReference = (claim?['reference'] as String?);
        if (claimReference != null && claimReference.isNotEmpty) {
          description += '\nReference: $claimReference';
        }
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
        customer = store.customers.firstWhere((c) => c.id == refId, orElse: () => _placeholderCustomer(refId, refId));
        subtitle = 'Underperforming Salesman — Top Account';
        priority = 'MEDIUM';
        color = kOrange;
        bannerIcon = Icons.trending_down;
        bannerText = '${store.salesmanDisplayName(customer.assignedSalesmanId)} has not achieved their collection target — this is their largest overdue account.';
        description = 'Overdue ${_rupee.format(customer.totalDue)} on ${customer.name}, ${customer.oldestOverdueDays} days overdue.';
        actionOptions = [
          _ActionOption(Icons.person_outline, kBlue, 'View Customer 360', 'Open the full account view and assign a task from there.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))), outlined: true),
          _ActionOption(Icons.call_outlined, kBlue, 'Contact Salesman', 'Call or WhatsApp the assigned salesperson about this account.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId)), outlined: true),
          _ActionOption(Icons.check_circle_outline, kGreen, 'Mark Complete', 'Clears this salesman for the rest of this month. It returns on the 1st of next month if they are still below target.', () => _dismissUnderperformance(context, store, customer.assignedSalesmanId)),
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

    final notes = store.notesForItem(refId);
    final attachments = store.attachmentsForItem(refId);
    final requestDetail = _requestDetailSection(store, kind, task: task, ptp: ptp, dispute: dispute);

    final taskClosed = task != null && (task.status == TaskStatus.completed || task.status == TaskStatus.closed);
    // Same rule as Customer 360's RE button ("TASK ALREADY EXISTS"): a
    // customer with an open task gets no second one from the broken-PTP /
    // visit-review screens (SHIVA MISTRY PERSONAL, 24 Oct).
    final customerHasOpenTask = store.tasks.any((t) =>
        t.customerId == customer.id &&
        t.id != task?.id &&
        t.status != TaskStatus.completed &&
        t.status != TaskStatus.closed);
    if (customerHasOpenTask && (kind == TaskKind.ptpMissed || kind == TaskKind.visitReview)) {
      actionOptions = actionOptions.where((a) => !a.title.startsWith('Create Task')).toList();
    }
    return RequestDetailScaffold(
      title: 'Task Details',
      subtitle: subtitle,
      bannerText: bannerText,
      priorityLabel: '$priority PRIORITY',
      color: color,
      bannerIcon: bannerIcon,
      // Same clean header as the salesman's Task Details — no coloured
      // banner / due strip; the deadline lives in Task Information below.
      showBanner: false,
      actions: actionOptions.map(_actionButton).toList(),
      children: [
        // Customer card — avatar on the left; row 1: name (wraps by whole
        // words) + Outstanding; row 2: branch + phone.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar with the branch underneath it.
              SizedBox(
                width: 72,
                child: Column(
                  children: [
                    CircleAvatar(
                        radius: 22,
                        backgroundColor: avatarColorFor(customer.name).withValues(alpha: 0.15),
                        child: Text(initialsFor(customer.name), style: TextStyle(color: avatarColorFor(customer.name), fontWeight: FontWeight.bold, fontSize: 14))),
                    const SizedBox(height: 6),
                    Text(customer.branch,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 10.5, color: kMuted, height: 1.2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                            child: Text(customer.name,
                                softWrap: true,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kBlue, decoration: TextDecoration.underline, height: 1.3)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Outstanding', style: TextStyle(fontSize: 10.5, color: kMuted)),
                            const SizedBox(height: 2),
                            Text(_rupee.format(customer.totalOutstanding), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: kRed)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Wrap, not Row: two phone numbers ("7202940640,9375922678")
                    // drop to the next line instead of overflowing.
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CallablePhoneNumber(phoneNumber: customer.contactNumber, iconSize: 12, style: const TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('TASK INFORMATION'),
        InfoCard(children: [
          KeyValueRow('Task Type', subtitle),
          KeyValueRow('Priority', priority[0] + priority.substring(1).toLowerCase(), valueColor: color),
          KeyValueRow('Status', task == null ? 'Pending' : (task.status.name[0].toUpperCase() + task.status.name.substring(1))),
          if (dueDate != null)
            KeyValueRow('Deadline', '${DateFormat('dd MMM yyyy, hh:mm a').format(dueDate)}  ·  ${_dueStatus(dueDate, taskClosed)}', valueColor: color),
        ]),
        ..._recordedSection(context, store, task, description, customer),
        // "To do" sits right below what was recorded / why this task exists.
        const SizedBox(height: 18),
        TodoCallout(
          taskClosed
              ? 'Nothing to do. This task is closed.'
              : (customerHasOpenTask && (kind == TaskKind.ptpMissed || kind == TaskKind.visitReview))
                  ? 'A task is already open for this customer. Check it in Tasks — no new task needed.'
                  : _todoFor(store, customer, task: task, dispute: dispute),
          done: taskClosed,
        ),
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
      showAppMessageAfter(navigator, message: 'Marked complete for this month. It will return on the 1st of next month if ${store.salesmanDisplayName(salesmanId)} is still below target.');
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
                initialValue: selectedSalesman,
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
                initialValue: selectedSalesman,
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
    bool requireNote = false,
    bool requirePhoto = false,
    bool allowPdf = true,
  }) async {
    final result = await showApproveRejectForm(
      context,
      refId: refId,
      title: title,
      accent: accent,
      submitLabel: submitLabel,
      requireNote: requireNote,
      requirePhoto: requirePhoto,
      allowPdf: allowPdf,
    );
    if (result == null) return;
    await action(result);
  }

  void _completeVisit(BuildContext context, AppStore store, AppTask task) {
    _decideWithEvidence(
      context,
      refId: task.id,
      title: 'Complete Visit',
      accent: kGreen,
      submitLabel: 'Complete',
      requireNote: true,
      requirePhoto: true,
      allowPdf: false,
      action: (result) async {
        final navigator = Navigator.of(context);
        try {
          await store.completeTaskWithEvidence(task.id, note: result.note, attachmentPath: result.attachmentPath);
          navigator.pop();
          showAppMessageAfter(navigator, message: 'Visit completed — the salesperson has a new follow-up call task.');
        } catch (e) {
          showAppMessageAfter(navigator, message: 'Could not complete: $e', isError: true);
        }
      },
    );
  }

  void _rejectVisit(BuildContext context, AppStore store, AppTask task) {
    _decideWithEvidence(
      context,
      refId: task.id,
      title: 'Reject Visit',
      accent: kRed,
      submitLabel: 'Reject',
      requireNote: true,
      allowPdf: false,
      action: (result) async {
        final navigator = Navigator.of(context);
        try {
          await store.rejectTaskVisit(task.id, reason: result.note, attachmentPath: result.attachmentPath);
          navigator.pop();
          showAppMessageAfter(navigator, message: 'Visit rejected — the salesperson has a new follow-up call task.');
        } catch (e) {
          showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
        }
      },
    );
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

  /// "Customer refused to commit — call again. Reason: Other Notes: …" /
  /// "Details: Updated Ledger Required" / "Dispute Raised — Reason: x,
  /// Amt: ₹1000" → labelled rows, so the RE reads fields, not a run-on line.
  List<(String, String)> _recordedRows(String text) {
    final re = RegExp(r'\b(Reason|Notes?|Details?|Amt|Amount|Ref|Date|Time|Contact)\s*:\s*', caseSensitive: false);
    final ms = re.allMatches(text).toList();
    String clean(String v) => v.trim().replaceAll(RegExp(r'^[\s,—\-–]+|[\s,—\-–]+$'), '').trim();
    final rows = <(String, String)>[];
    final lead = clean(ms.isEmpty ? text : text.substring(0, ms.first.start));
    if (lead.isNotEmpty) rows.add(('Summary', lead));
    for (var i = 0; i < ms.length; i++) {
      final raw = ms[i].group(1)!.toLowerCase();
      final label = raw.startsWith('amt') || raw == 'amount'
          ? 'Amount'
          : raw.startsWith('note')
              ? 'Notes'
              : raw.startsWith('detail')
                  ? 'Details'
                  : raw == 'ref'
                      ? 'Reference'
                      : raw[0].toUpperCase() + raw.substring(1);
      final v = clean(text.substring(ms[i].end, i + 1 < ms.length ? ms[i + 1].start : text.length));
      if (v.isNotEmpty) rows.add((label, v));
    }
    return rows;
  }

  /// Which salesman outcome raised this task (null = a system task).
  String? _outcomeLabel(AppTask t) {
    if (t.type == TaskType.financialTeamFollowUp && t.source == 'Record Outcome') return 'Internal Action';
    if (t.type == TaskType.physicalVisit && t.source == 'Record Outcome') return 'Physical Visit Requested';
    if (t.type == TaskType.paymentVerification) return 'Payment Already Made';
    switch (t.source) {
      case 'Customer Refused':
        return 'Unable / Refused to Pay';
      case 'No Answer':
        return 'No Answer';
      case 'Dispute Review':
        return 'Dispute';
      case 'Record Outcome':
        return 'Recorded Outcome';
    }
    return null;
  }

  /// "Overdue by 2 days" / "Due today" / "Due in 3 days" / "Completed".
  static String _dueStatus(DateTime due, bool closed) {
    if (closed) return 'Completed';
    final now = DateTime.now();
    if (due.isBefore(now)) {
      final d = now.difference(due);
      return d.inDays >= 1 ? 'Overdue by ${d.inDays} day${d.inDays == 1 ? '' : 's'}' : 'Overdue by ${d.inHours < 1 ? '${d.inMinutes} min' : '${d.inHours} hr'}';
    }
    final days = DateTime(due.year, due.month, due.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    return days == 0 ? 'Due today' : days == 1 ? 'Due tomorrow' : 'Due in $days days';
  }

  /// One short, plain line for the Summary — e.g. "Missed the scheduled
  /// call on 23 Oct, 06:00 PM." Null keeps the original text.
  String? _shortSummary(AppTask? task, String description, Customer customer) {
    if (task == null) return null;
    if (task.source == 'Missed Deadline') {
      final m = RegExp(r'scheduled (call|physical visit|visit) \(due (\d{1,2})/(\d{1,2})/(\d{4}),\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*([ap]m)', caseSensitive: false).firstMatch(description);
      if (m == null) return 'Missed the scheduled call.';
      var h = int.parse(m.group(5)!);
      final pm = m.group(7)!.toLowerCase() == 'pm';
      if (pm && h < 12) h += 12;
      if (!pm && h == 12) h = 0;
      final when = DateTime(int.parse(m.group(4)!), int.parse(m.group(3)!), int.parse(m.group(2)!), h, int.parse(m.group(6)!));
      return 'Missed the scheduled ${m.group(1)!.toLowerCase()} on ${DateFormat('dd MMM, hh:mm a').format(when)}.';
    }
    if (task.source == 'Refused Cycle') return 'Customer refused to pay. 5 more days passed with no update.';
    if (task.type == TaskType.financialTeamFollowUp) return null;
    final why = plainTask(description, customer.name).why;
    return why.isEmpty ? null : why;
  }

  List<Widget> _recordedSection(BuildContext context, AppStore store, AppTask? task, String description, Customer customer) {
    var rows = _recordedRows(description);
    final short = _shortSummary(task, description, customer);
    if (short != null) {
      rows = [('Summary', short), ...rows.where((r) => r.$1 != 'Summary')];
      // Missed-deadline / refused-cycle text has nothing else worth showing.
      if (task?.source == 'Missed Deadline' || task?.source == 'Refused Cycle') rows = [('Summary', short)];
    }
    final outcome = task == null ? null : _outcomeLabel(task);
    // Non-task requests (dispute, PTP correction, claim…) are always the
    // salesman's own submission.
    final title = outcome != null || task == null ? 'WHAT THE SALESMAN RECORDED' : 'WHY THIS TASK EXISTS';
    return [
      const SizedBox(height: 18),
      SectionLabel(title),
      InfoCard(children: [
        // The customer's current salesman — name plus a phone icon only;
        // tapping it opens the Call / WhatsApp chooser (contactActions).
        if (customer.assignedSalesmanId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const SizedBox(width: 120, child: Text('Salesman', style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500))),
                Expanded(
                  child: Text(store.salesmanDisplayName(customer.assignedSalesmanId),
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: kBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.call, size: 16, color: kBlue),
                  ),
                ),
              ],
            ),
          ),
        if (outcome != null) KeyValueRow('Outcome', outcome, valueColor: kBlue),
        for (final (k, v) in rows)
          k == 'Summary' || k == 'Notes' || k == 'Details'
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k, style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(v, style: const TextStyle(fontSize: 12.5, color: kDark, height: 1.4)),
                    ],
                  ),
                )
              : KeyValueRow(k, v),
        if (task != null) ...[
          // Only these tasks are created at the moment the salesman records
          // the outcome; the rest are raised later by the system (e.g. the
          // visit after a 3rd No Answer), so their time is the task's own.
          KeyValueRow(
              (task.source == 'Record Outcome' || task.source == 'Customer Refused' || task.type == TaskType.paymentVerification)
                  ? 'Recorded on'
                  : 'Task created on',
              DateFormat('dd MMM yyyy, hh:mm a').format(task.createdAt)),
        ],
      ]),
    ];
  }

  /// What the RE does next — one plain sentence, shown in the coloured
  /// header banner ("To do: …"), naming the button(s) at the bottom (same
  /// branches as the actionOptions in build()).
  String _whatToDo(AppStore store, AppTask task, Customer customer) {
    final sm = store.salesmanDisplayName(customer.assignedSalesmanId);
    if (task.type == TaskType.paymentVerification) return 'Check the payment in BUSY, then tap Verify Deposit or Fail Verification.';
    if (task.type == TaskType.customerDetailCorrection) return 'Correct the customer\'s phone or address, then tap Update Customer Details.';
    if (task.type == TaskType.customerCall && task.source == 'Missed Deadline') return 'Call $sm and ask them to record an outcome, then tap Mark Done.';
    if (task.type == TaskType.customerCall && task.source == 'Refused Cycle') return 'Call $sm about this customer, then tap Mark Done.';
    if (task.type == TaskType.physicalVisit && task.source == 'Record Outcome') return 'Visit the customer, then tap Complete Visit or Reject Visit.';
    if (task.type == TaskType.financialTeamFollowUp && task.source == 'Record Outcome') return 'Solve the salesman\'s issue, then tap Approve or Reject.';
    if (task.ownerId != store.currentSalesmanId) {
      return task.isOverdue
          ? 'Call $sm and ask them to record an outcome.'
          : 'Nothing now. $sm must finish this by ${DateFormat('dd MMM, hh:mm a').format(task.deadline)}.';
    }
    return 'Do this task, then tap Mark Completed.';
  }

  /// The "To do" sentence for every customer-level task kind.
  String _todoFor(AppStore store, Customer customer, {AppTask? task, Map<String, dynamic>? dispute}) {
    final sm = store.salesmanDisplayName(customer.assignedSalesmanId);
    switch (kind) {
      case TaskKind.realTask:
        return task == null ? 'Review this task.' : _whatToDo(store, task, customer);
      case TaskKind.visitReview:
        return 'Call $sm and ask what happened on the visit.';
      case TaskKind.dispute:
        return (dispute?['status'] == 'Awaiting Verification')
            ? 'Check BUSY, then tap Verify & Resolve or Still Unpaid.'
            : 'Check the dispute, then tap Approve & Assign or Reject.';
      case TaskKind.ptpCorrection:
        return 'Check the new PTP details, then tap Approve Correction or Reject Correction.';
      case TaskKind.ptpMissed:
        return 'The promise was broken. Tap Create Task — Call Customer.';
      case TaskKind.paymentClaim:
        return 'Check this payment in BUSY, then tap Confirm Payment or No Payment Found.';
      case TaskKind.overdueTarget:
        return 'Call $sm about this account, then tap Mark Complete.';
      default:
        return 'Review the details below.';
    }
  }

  List<Widget> _requestDetailSection(
    AppStore store,
    TaskKind kind, {
    AppTask? task,
    PromiseToPay? ptp,
    Map<String, dynamic>? dispute,
  }) {
    switch (kind) {
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
        // Already said in one line in the Summary above.
        return const [];
      case TaskKind.realTask:
      case TaskKind.visitReview:
        // Type, priority and deadline are in the header/banner/Due strip;
        // source and created-on are inside the "recorded" section.
        return const [];
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
