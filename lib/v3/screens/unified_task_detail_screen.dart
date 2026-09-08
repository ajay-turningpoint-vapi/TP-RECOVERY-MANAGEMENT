import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum TaskKind { realTask, visitReview, taskExtension, noCall, overdueTarget, dispute, ptpCorrection, outcomeEdit, ptpMissed }

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
      actions: const [],
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
        _requiredActionSection(context, store, [
          _ActionOption(Icons.call_outlined, kBlue, 'Contact Salesman', 'Call $refId directly for an update.', () => _contactSalesman(context, s)),
          _ActionOption(Icons.assignment_outlined, kNavy, 'Assign Task to Salesman', 'Create a follow-up task tied to their top overdue customer.', () => _assignTask(context, store, s, owned)),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kNavy),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.assignManagementInstruction(target.id, s['name'], reasonController.text.trim(), deadline);
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

    switch (kind) {
      case TaskKind.realTask:
        task = store.tasks.firstWhere((t) => t.id == refId, orElse: () => store.tasks.first);
        customer = store.customers.firstWhere((c) => c.id == task!.customerId, orElse: () => store.customers.first);
        subtitle = taskTypeLabel(task.type);
        priority = task.priority == 'Critical' || task.priority == 'High' ? 'HIGH' : (task.priority == 'Normal' ? 'MEDIUM' : 'LOW');
        color = priority == 'HIGH' ? kRed : (priority == 'MEDIUM' ? kOrange : kBlue);
        bannerIcon = taskTypeIcon(task.type);
        bannerText = task.isOverdue ? 'This task is overdue — action is required.' : 'Due ${DateFormat('dd MMM, hh:mm a').format(task.deadline)}.';
        description = task.reason;
        if (task.type == TaskType.paymentVerification) {
          final claim = store.paymentClaims.cast<Map<String, dynamic>?>().firstWhere((p) => p != null && p['customer'] == customer.name, orElse: () => null);
          actionOptions = claim == null
              ? []
              : [
                  _ActionOption(Icons.check_circle_outline, kGreen, 'Verify Deposit', 'Reconcile ${_rupee.format(claim['amount'])} against BUSY.', () => _verifyClaim(context, store, claim, true)),
                  _ActionOption(Icons.cancel_outlined, kRed, 'Fail Verification', 'No matching BUSY deposit found — return to recovery.', () => _verifyClaim(context, store, claim, false)),
                ];
        } else if (task.type == TaskType.customerDetailCorrection) {
          actionOptions = [
            _ActionOption(Icons.edit_location_alt_outlined, kBlue, 'Update Customer Details', 'Correct contact number / address, then close this task.', () => _correctCustomerDetails(context, store, task!, customer)),
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
        subtitle = 'Physical Visit Review';
        priority = 'MEDIUM';
        color = kPurple;
        bannerIcon = Icons.location_on_outlined;
        bannerText = 'This visit outcome is awaiting RE review before the case can move forward.';
        description = task.reason;
        actionOptions = [
          _ActionOption(Icons.fact_check_outlined, kPurple, 'Mark Reviewed', 'Confirm you have reviewed this visit outcome.', () => _reviewVisit(context, store, task!)),
          _ActionOption(Icons.person_outline, kBlue, 'View Customer 360', 'Open the full customer investigation view.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer)))),
        ];
        break;
      case TaskKind.taskExtension:
        task = store.tasks.firstWhere((t) => t.id == refId, orElse: () => store.tasks.first);
        customer = store.customers.firstWhere((c) => c.id == task!.customerId, orElse: () => store.customers.first);
        subtitle = 'Task Extension Request';
        priority = 'MEDIUM';
        color = kAmber;
        bannerIcon = Icons.schedule;
        bannerText = 'Salesperson requested a deadline extension.';
        description = task.pendingReason ?? task.reason;
        actionOptions = [
          _ActionOption(Icons.check_circle_outline, kGreen, 'Approve Extension', 'Deadline moves to ${task.pendingDeadline != null ? DateFormat('dd MMM').format(task.pendingDeadline!) : '-'}.', () async {
            final navigator = Navigator.of(context);
            try {
              await store.approveTaskEdit(task!.id);
              navigator.pop();
              showAppMessageAfter(navigator, message: 'Extension approved.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
            }
          }),
          _ActionOption(Icons.cancel_outlined, kRed, 'Reject Extension', 'Original deadline stays authoritative.', () async {
            final navigator = Navigator.of(context);
            try {
              await store.rejectTaskEdit(task!.id);
              navigator.pop();
              showAppMessageAfter(navigator, message: 'Extension rejected.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
            }
          }),
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
        // becomes available once RE has Approved the dispute.
        final needsVerification = status == 'Approved';
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
          _ActionOption(Icons.check_circle_outline, kGreen, 'Approve Correction', 'Update the PTP to the requested amount/date.', () async {
            final navigator = Navigator.of(context);
            try {
              await store.approvePtpCorrection(ptp!.id);
              navigator.pop();
              showAppMessageAfter(navigator, message: 'PTP correction approved.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
            }
          }),
          _ActionOption(Icons.cancel_outlined, kRed, 'Reject Correction', 'Keep the original PTP terms.', () async {
            final navigator = Navigator.of(context);
            try {
              await store.rejectPtpCorrection(ptp!.id, 'Not justified');
              navigator.pop();
              showAppMessageAfter(navigator, message: 'PTP correction rejected.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
            }
          }),
        ];
        break;
      case TaskKind.outcomeEdit:
        final req = store.outcomeEditRequests.firstWhere((r) => r.id == refId, orElse: () => store.outcomeEditRequests.first);
        customer = store.customers.firstWhere((c) => c.id == req.customerId, orElse: () => store.customers.first);
        subtitle = 'Outcome Edit Request';
        priority = 'LOW';
        color = kPink;
        bannerIcon = Icons.edit_note;
        bannerText = 'Salesperson requested an edit to a recorded outcome\'s values.';
        description = 'Edit ${req.outcomeKind} outcome — ${req.editReason}';
        actionOptions = [
          _ActionOption(Icons.check_circle_outline, kGreen, 'Approve Edit', 'Apply the edited values and re-run side effects.', () async {
            final navigator = Navigator.of(context);
            try {
              await store.approveOutcomeEdit(req.id);
              navigator.pop();
              showAppMessageAfter(navigator, message: 'Outcome edit approved and applied.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
            }
          }),
          _ActionOption(Icons.cancel_outlined, kRed, 'Reject Edit', 'Keep the recorded values unchanged.', () async {
            final navigator = Navigator.of(context);
            try {
              await store.rejectOutcomeEdit(req.id, 'Not justified');
              navigator.pop();
              showAppMessageAfter(navigator, message: 'Outcome edit rejected.');
            } catch (e) {
              showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
            }
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
        actionOptions = [
          _ActionOption(Icons.person_outline, kBlue, 'View Customer 360', 'Review full PTP history, disputes and timeline.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer)))),
          _ActionOption(Icons.trending_up, kRed, 'Escalate Customer', 'Open an RE escalation case for this account.', () => _escalate(context, store, customer)),
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
          _ActionOption(Icons.person_outline, kBlue, 'View Customer 360', 'Open the full account view and assign a task from there.', () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer)))),
          _ActionOption(Icons.call_outlined, kBlue, 'Contact Salesman', 'Call or WhatsApp the assigned salesperson about this account.', () => contactActions(context, store.salesmanPhone(customer.assignedSalesmanId))),
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
      actions: const [],
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
          if (task != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 118, child: Text('Owner', style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500))),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(store.salesmanDisplayName(task.ownerId),
                              textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => contactActions(context, store.salesmanPhone(task!.ownerId)),
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
        const SectionLabel('TASK DESCRIPTION'),
        InfoCard(children: [Text(description, style: const TextStyle(fontSize: 12.5, color: kDark))]),
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
          InfoCard(children: [_TaskAttachmentThumbnail(path: task.attachmentPath!)]),
        ],
        const SizedBox(height: 18),
        _requiredActionSection(context, store, actionOptions),
        const SizedBox(height: 18),
        // Every item in the Tasks screen can now carry a note + attachment
        // — was previously limited to just 3 of the 9 kinds.
        AttachmentsSection(refId: refId),
        const SizedBox(height: 18),
        NotesSection(refId: refId),
        const SizedBox(height: 18),
        const SectionLabel('ACTIVITY / HISTORY'),
        ActivityTimeline(events),
      ],
    );
  }

  Future<void> _completeTask(BuildContext context, AppStore store, AppTask t) async {
    final navigator = Navigator.of(context);
    try {
      await store.completeTask(t.id);
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBlue),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.rescheduleTask(t.id, reasonController.text.trim(), newDeadline);
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

  Future<void> _reviewVisit(BuildContext context, AppStore store, AppTask t) async {
    final navigator = Navigator.of(context);
    try {
      await store.reviewPhysicalVisit(t.id);
      navigator.pop();
      showAppMessageAfter(navigator, message: 'Visit outcome reviewed.');
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not review: $e', isError: true);
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBlue),
            onPressed: () async {
              final navigator = Navigator.of(context);
              store.updateCustomerContactDetails(
                customer.id,
                contactNumber: contactController.text.trim(),
                alternateContactNumber: altController.text.trim(),
                branch: branchController.text.trim(),
              );
              Navigator.pop(dialogCtx);
              try {
                await store.completeTask(t.id);
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.approveDispute(d['id'], selectedSalesman, deadline, descController.text.trim());
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
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Dispute', style: TextStyle(fontWeight: FontWeight.bold)),
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
                await store.rejectDispute(d['id'], reasonController.text.trim());
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Dispute rejected.');
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

  void _approveInternalAction(BuildContext context, AppStore store, AppTask task) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Internal Action', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Note (optional) — what was resolved', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(dialogCtx);
              try {
                await store.approveInternalAction(task.id, note: noteController.text.trim());
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Internal action approved — the salesperson has a new follow-up call task.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
              }
            },
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _rejectInternalAction(BuildContext context, AppStore store, AppTask task) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Internal Action', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Reason (optional)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(dialogCtx);
              try {
                await store.rejectInternalAction(task.id, reason: reasonController.text.trim());
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Internal action rejected — the salesperson has a new follow-up call task.');
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

  void _clarifyDispute(BuildContext context, AppStore store, Map<String, dynamic> d) {
    String selectedSalesman = store.salesmen.isNotEmpty ? store.salesmen.first['name'] as String : '';
    final descController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 1));
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kOrange),
              onPressed: () async {
                if (descController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.requestDisputeInfo(d['id'], selectedSalesman, descController.text.trim(), deadline);
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kRed),
              onPressed: () async {
                if (planController.text.trim().isEmpty) return;
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  await store.escalateCustomer(customer.id, nextLevel, 'Broken PTP', planController.text.trim(), store.currentSalesmanId, deadline);
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

  Widget _requiredActionSection(BuildContext context, AppStore store, List<_ActionOption> options) {
    if (options.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('REQUIRED ACTION'),
        ...options.map((o) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: o.onTap,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: o.color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(o.icon, size: 16, color: o.color)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
                            Text(o.description, style: const TextStyle(fontSize: 10.5, color: kMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: kMuted),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

}

class _ActionOption {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;
  _ActionOption(this.icon, this.color, this.title, this.description, this.onTap);
}

/// A small tap-to-enlarge thumbnail for a task's own `attachmentPath` —
/// same pattern as customer_360_screen.dart's attachment thumbnail. The
/// attachments endpoint requires auth, which Image.network doesn't send
/// by default, so headers are passed explicitly.
class _TaskAttachmentThumbnail extends StatelessWidget {
  final String path;
  const _TaskAttachmentThumbnail({required this.path});

  @override
  Widget build(BuildContext context) {
    final apiClient = context.read<AppStore>().apiClient;
    final url = apiClient.attachmentUrl(path);
    final headers = apiClient.attachmentAuthHeaders;

    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              InteractiveViewer(minScale: 0.5, maxScale: 4, child: Image.network(url, headers: headers, fit: BoxFit.contain)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, headers: headers, height: 90, width: 90, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                  height: 90,
                  width: 90,
                  color: kBg,
                  child: const Icon(Icons.broken_image_outlined, color: kMuted),
                )),
      ),
    );
  }
}
