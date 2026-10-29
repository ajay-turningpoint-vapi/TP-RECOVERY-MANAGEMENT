import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/services/attachment_picker.dart';
import 'package:salesman_mobile/v2/widgets/voice_translate_field.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

Color _priorityColor(String p) {
  switch (p) {
    case 'Critical':
      return kRed;
    case 'High':
      return kOrange;
    default:
      return kBlue;
  }
}

class TaskDetailsScreenV3 extends StatelessWidget {
  final AppTask task;
  const TaskDetailsScreenV3({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = store.tasks.firstWhere((x) => x.id == task.id, orElse: () => task);
    final customer = store.customers.firstWhere((c) => c.id == t.customerId, orElse: () => store.customers.first);
    final color = _priorityColor(t.priority);
    final isDone = t.status == TaskStatus.completed;

    // Dispute-linked tasks are worked from here (chat / resolve), never via
    // Record Outcome. Two kinds:
    //  - resolution task: assigned to the resolution owner → chat with RE +
    //    "Resolve Dispute".
    //  - clarification task: RE asked a question → "Answer Clarification".
    final isDisputeTask = (t.disputeId?.isNotEmpty ?? false);
    final isResolutionTask = isDisputeTask && t.reason.startsWith('DISPUTE RESOLUTION');
    final isClarification = isDisputeTask && !isResolutionTask;
    final dispute = isDisputeTask
        ? store.disputes.firstWhere((d) => d['id'] == t.disputeId, orElse: () => <String, dynamic>{})
        : const <String, dynamic>{};
    final thread = (dispute['messages'] as List?) ?? const [];

    // Dispute history only — shown just on dispute tasks; other tasks don't
    // need a customer activity feed here (full history is in Customer 360).
    String readable(String type) => type.contains('_')
        ? type.split('_').map((w) => w.isEmpty ? w : (w == 'RE' ? 'RE' : w[0] + w.substring(1).toLowerCase())).join(' ')
        : type;
    final disputeEvents = customer.auditHistory.reversed
        .where((a) => a.type.toLowerCase().contains('dispute') || a.type == 'SALESMAN_PROVIDED_CLARIFICATION' || a.type == 'RE_REQUESTED_INFORMATION')
        .map((a) => TimelineEvent(icon: Icons.history, color: kMuted, title: readable(a.type), subtitle: a.description, date: a.timestamp, tag: a.actor, tagColor: kBlue))
        .take(5)
        .toList();

    final typeLabel = isResolutionTask
        ? 'Dispute Resolution'
        : (isClarification ? 'Dispute Clarification' : taskTypeLabel(t.type));
    final typeIcon = isResolutionTask
        ? Icons.gavel_outlined
        : (isClarification ? Icons.help_outline : taskTypeIcon(t.type));

    // Deadline status text for the Task Information row.
    final now = DateTime.now();
    final dueToday = t.deadline.year == now.year && t.deadline.month == now.month && t.deadline.day == now.day;
    final overdue = !isDone && t.isOverdue;
    String dueStatus() {
      if (isDone) return 'Completed';
      if (overdue) {
        final d = now.difference(t.deadline);
        return d.inDays >= 1 ? 'Overdue by ${d.inDays} day${d.inDays == 1 ? '' : 's'}' : 'Overdue by ${d.inHours < 1 ? '${d.inMinutes} min' : '${d.inHours} hr'}';
      }
      if (dueToday) return 'Due today';
      final days = DateTime(t.deadline.year, t.deadline.month, t.deadline.day).difference(DateTime(now.year, now.month, now.day)).inDays;
      return days == 1 ? 'Due tomorrow' : 'Due in $days days';
    }
    return RequestDetailScaffold(
      showBanner: false,
      title: 'TASK DETAILS',
      subtitle: typeLabel,
      bannerText: isDone ? 'This task has been completed.' : (t.isOverdue ? 'This task is overdue — action is required.' : 'Task is on track — deadline ${DateFormat('dd MMM, hh:mm a').format(t.deadline)}.'),
      priorityLabel: isDone ? 'Completed' : (t.isOverdue ? 'Overdue' : '${t.priority} Priority'),
      color: isDone ? kGreen : (t.isOverdue ? kRed : color),
      bannerIcon: typeIcon,
      actions: (isDone
              ? const []
              : (isResolutionTask
                  ? [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF4F46E5)), foregroundColor: const Color(0xFF4F46E5), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _disputeMessage(context, store, t, thread),
                        icon: const Icon(Icons.forum_outlined, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Message RE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: kRed), foregroundColor: kRed, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _rejectDisputeAssignment(context, store, t),
                        icon: const Icon(Icons.person_off_outlined, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Wrong Owner — Reject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _resolveDispute(context, store, t),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Submit for Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                    ]
                  : isClarification
                  ? [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _answerClarification(context, store, t, thread),
                        icon: const Icon(Icons.forum_outlined, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Answer Clarification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                    ]
                  : [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        // A 3rd-No-Answer Physical Visit task hands the
                        // visit off to the RE (notes only — see
                        // _requestPhysicalVisit) instead of the salesman
                        // doing it themselves; every other task type jumps
                        // into Record Outcome as before.
                        onPressed: t.type == TaskType.physicalVisit
                            ? () => _requestPhysicalVisit(context, store, t)
                            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer, fromTaskDetails: true))),
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Take Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                    ])),
      children: [
        // Customer card — name on its own line, contact underneath, money
        // in a separate row so nothing is squeezed side by side.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                      radius: 22,
                      backgroundColor: avatarColorFor(customer.name).withValues(alpha: 0.15),
                      child: Text(initialsFor(customer.name), style: TextStyle(color: avatarColorFor(customer.name), fontWeight: FontWeight.bold, fontSize: 14))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                          child: Text(customer.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kBlue, decoration: TextDecoration.underline, height: 1.3)),
                        ),
                        const SizedBox(height: 6),
                        Text('${customer.branch} Branch', style: const TextStyle(fontSize: 11, color: kMuted)),
                        const SizedBox(height: 6),
                        CallablePhoneNumber(phoneNumber: customer.contactNumber, iconSize: 12, style: const TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: kBorder),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Outstanding', style: TextStyle(fontSize: 10.5, color: kMuted)),
                        const SizedBox(height: 4),
                        Text(_rupee.format(customer.totalOutstanding), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: kRed)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Overdue Since', style: TextStyle(fontSize: 10.5, color: kMuted)),
                        const SizedBox(height: 4),
                        Text('${customer.oldestOverdueDays} days', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: kDark)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('TASK INFORMATION'),
        InfoCard(children: [
          KeyValueRow('Task Type', typeLabel),
          KeyValueRow('Assigned To', store.salesmanDisplayName(t.ownerId)),
          KeyValueRow('Priority', t.priority, valueColor: color),
          KeyValueRow('Status', t.status.name[0].toUpperCase() + t.status.name.substring(1)),
          KeyValueRow('Source', t.source),
          // Coloured like Priority: red overdue, orange today, blue later.
          // Same colour as Priority, always.
          KeyValueRow('Deadline', '${DateFormat('dd MMM yyyy, hh:mm a').format(t.deadline)}  ·  ${dueStatus()}', valueColor: color),
          if (isDisputeTask) KeyValueRow('Disputed Amount', _rupee.format((dispute['amount'] as num?) ?? 0), valueColor: kRed),
          if (t.approvalStatus == 'Pending') KeyValueRow('Extension Requested', t.pendingDeadline != null ? DateFormat('dd MMM yyyy').format(t.pendingDeadline!) : '-', valueColor: kAmber),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('TASK DESCRIPTION'),
        _descriptionCard(friendlyTaskReason(t.reason), customer.name, color),
        // Note + evidence the RE attached when approving/rejecting — the
        // server copies these onto the follow-up task it creates here.
        if (t.note?.isNotEmpty ?? false) ...[
          const SizedBox(height: 18),
          const SectionLabel('NOTE FROM RECOVERY EXECUTIVE'),
          InfoCard(children: [Text(t.note!, style: const TextStyle(fontSize: 12.5, color: kDark))]),
        ],
        if (t.attachmentPath?.isNotEmpty ?? false) ...[
          const SizedBox(height: 18),
          const SectionLabel('EVIDENCE ATTACHMENT'),
          InfoCard(children: [TaskAttachmentThumbnail(path: t.attachmentPath!)]),
        ],
        if (isDisputeTask) ...[
          const SizedBox(height: 18),
          SectionLabel(isResolutionTask ? 'DISPUTE THREAD' : 'CLARIFICATION THREAD'),
          InfoCard(children: [
            _threadView(thread,
                emptyHint: isResolutionTask
                    ? 'Message the RE with questions or updates while resolving this dispute.'
                    : 'The RE asked for clarification on this dispute.'),
          ]),
        ],
        if (isDisputeTask && disputeEvents.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionLabel('DISPUTE ACTIVITY'),
          ActivityTimeline(disputeEvents),
        ],
      ],
    );
  }

  /// Chat bubbles for the dispute thread — the salesperson's own messages
  /// on the right (green), the RE's on the left (indigo). Messages may
  /// carry an attachment.
  Widget _threadView(List<dynamic> thread, {String? emptyHint}) {
    if (thread.isEmpty) {
      return Text(emptyHint ?? 'No messages yet.', style: const TextStyle(fontSize: 11.5, color: kMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: thread.map<Widget>((m) {
        final mine = m['authorRole'] == 'SALESPERSON';
        final c = mine ? kGreen : const Color(0xFF4F46E5);
        final att = m['attachmentPath'] as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.25))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['body'] as String, style: const TextStyle(fontSize: 12, color: kDark)),
                    if (att != null && att.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      TaskAttachmentThumbnail(path: att),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text('${mine ? 'You' : m['authorName']} · ${DateFormat('dd MMM, hh:mm a').format(m['createdAt'] as DateTime)}',
                  style: const TextStyle(fontSize: 9, color: kMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Compose a free message (optional photo) to the RE on this dispute.
  void _disputeMessage(BuildContext context, AppStore store, AppTask t, List<dynamic> thread) {
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
                const Expanded(child: Text('Message RE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kDark))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(sheetCtx)),
              ]),
              const Text('Back-and-forth on this dispute — no outcome is recorded.', style: TextStyle(fontSize: 11.5, color: kMuted)),
              const SizedBox(height: 12),
              if (thread.isNotEmpty) ...[
                ConstrainedBox(constraints: const BoxConstraints(maxHeight: 200), child: SingleChildScrollView(child: _threadView(thread))),
                const Divider(height: 20),
              ],
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
                      await store.postDisputeMessage(t.disputeId!, body: body, attachmentPath: path);
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

  /// The 3rd-No-Answer Physical Visit, handled the same way as the
  /// salesman-chosen one (Internal Action → "Physical Visit" dependency,
  /// see outcome_forms.dart's InternalActionForm): notes only, no
  /// photo/PDF — submitting hands the visit to the RE via the same
  /// 'Physical Visit Requested' outcome (customerService.applyOutcome),
  /// which supersedes this task, locks Record Outcome on Customer 360, and
  /// creates the RE's visit task.
  void _requestPhysicalVisit(BuildContext context, AppStore store, AppTask t) {
    final noteController = TextEditingController();
    bool busy = false;
    String? error;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 16, bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(child: Text('Request Physical Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kDark))),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(sheetCtx)),
              ]),
              const Text('The customer could not be reached after repeated attempts — this hands the visit to your Recovery Executive.', style: TextStyle(fontSize: 11.5, color: kMuted)),
              const SizedBox(height: 14),
              const Text('REASON FOR VISIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: kMuted)),
              const SizedBox(height: 8),
              VoiceTranslateField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.all(12),
                  hintText: 'Reason for visit…',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 11.5, color: kRed, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: busy ? null : () async {
                    final note = noteController.text.trim();
                    if (note.isEmpty) {
                      setSheet(() => error = 'A reason for the visit is required.');
                      return;
                    }
                    setSheet(() {
                      error = null;
                      busy = true;
                    });
                    final navigator = Navigator.of(context);
                    try {
                      await store.recordOutcome(t.customerId, 'Physical Visit Requested', 'Unable to Reach — Visit Requested', note);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      navigator.pop();
                      showAppMessageAfter(navigator, message: 'Visit requested — the RE will follow up and you\'ll get a follow-up call task once it\'s resolved.');
                    } catch (e) {
                      setSheet(() => busy = false);
                      showAppMessageAfter(navigator, message: 'Could not request the visit: $e', isError: true);
                    }
                  },
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _resolveDispute(BuildContext context, AppStore store, AppTask t) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Submit for Verification', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Closes this task and sends the dispute to the RE for verification against BUSY. Nothing is written off and the raised salesman is not notified until the RE verifies it.',
                style: TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 12),
            TextField(controller: noteController, maxLines: 2,
                decoration: const InputDecoration(hintText: 'Resolution note (optional)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white),
            onPressed: () async {
              final navigator = Navigator.of(context);
              try {
                await store.resolveDisputeByOwner(t.disputeId!, t.id, note: noteController.text.trim());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Submitted for RE verification.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not submit: $e', isError: true);
              }
            },
            child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _rejectDisputeAssignment(BuildContext context, AppStore store, AppTask t) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Assignment', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Closes this task and sends the dispute back to the RE for reassignment. Use this when the RE assigned this to the wrong person.',
                style: TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 12),
            TextField(controller: reasonController, maxLines: 2,
                decoration: const InputDecoration(hintText: 'Reason (required)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                showAppMessageAfter(Navigator.of(dialogCtx), message: 'A reason is required.', isError: true);
                return;
              }
              final navigator = Navigator.of(context);
              try {
                await store.rejectDisputeByOwner(t.disputeId!, t.id, reason);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Sent back to the RE for reassignment.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not reject: $e', isError: true);
              }
            },
            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _answerClarification(BuildContext context, AppStore store, AppTask t, List<dynamic> thread) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Answer Clarification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kDark))),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(sheetCtx)),
            ]),
            const Text('Your note goes back to the RE on this dispute — no outcome is recorded.', style: TextStyle(fontSize: 11.5, color: kMuted)),
            const SizedBox(height: 12),
            if (thread.isNotEmpty) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(child: _threadView(thread)),
              ),
              const Divider(height: 20),
            ],
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Type your clarification…'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: LoadingElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final body = controller.text.trim();
                  if (body.isEmpty) return;
                  final navigator = Navigator.of(context);
                  try {
                    await store.answerDisputeClarification(t.disputeId!, t.id, body);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    navigator.pop();
                    showAppMessageAfter(navigator, message: 'Clarification sent to the RE.');
                  } catch (e) {
                    showAppMessageAfter(navigator, message: 'Could not send: $e', isError: true);
                  }
                },
                child: const Text('Send to RE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

}


/// The task reason turned into plain, simple words for the salesman:
/// WHAT TO DO / WHY / AMOUNT TO COLLECT / THEN (+ NOTE). Every reason the
/// server writes on a salesman task is covered (recoveryTaskService
/// headlines, ptpService, No Answer, Customer Refused, disputes); anything
/// unknown falls back to the original text.
({String what, String why, String? amount, String? then, String? note}) plainTask(String raw, String customerName) {
  final text = raw.trim();
  final name = customerName.trim().isEmpty ? 'the customer' : customerName.trim();
  String? grab(String p) => RegExp(p, caseSensitive: false, dotAll: true).firstMatch(text)?.group(1)?.trim();
  final collect = grab(r'Collect\s+(₹\s?\d(?:[\d,]*\d)?)');
  final then = collect != null ? 'Record what the customer says.' : null;
  final low = text.toLowerCase();

  if (low.startsWith('overdue still open')) {
    return (what: 'Call $name', why: 'Payment is still overdue.', amount: collect, then: then, note: null);
  }
  if (low.contains('promise broken')) {
    return (what: 'Call $name', why: 'Customer promised to pay, but the payment did not come.', amount: collect, then: then, note: null);
  }
  if (low.contains('confirm time has passed')) {
    return (what: 'Call $name', why: 'Customer said they would confirm. That time has passed.', amount: collect, then: then, note: grab(r'Note:\s*"?(.+?)"?\.?\s*(?:Collect|$)'));
  }
  final paid = RegExp(r'—\s*(₹\s?[\d,]+)\s+received(?:\s+of\s+(₹\s?[\d,]+))?', caseSensitive: false).firstMatch(text);
  if (paid != null) {
    final why = paid.group(2) != null
        ? 'Customer paid ${paid.group(1)} of the ${paid.group(2)} promised.'
        : 'Customer paid ${paid.group(1)}.';
    return (what: 'Call $name about the rest', why: why, amount: collect, then: then, note: null);
  }
  if (low.startsWith('keep calling')) {
    return (what: 'Call $name', why: 'Nothing has been recorded for this customer yet.', amount: collect, then: then, note: null);
  }
  if (low.startsWith('previous task closed')) {
    return (what: 'Call $name', why: 'The last task was closed without recording what happened.', amount: collect, then: then, note: null);
  }
  if (low.contains('non-response threshold') || low.contains('no answer on 3 attempts')) {
    return (what: 'Visit $name', why: 'Customer did not answer 3 calls.', amount: collect, then: 'Tap Take Action to ask the RE for the visit.', note: null);
  }
  if (low.contains('no answer on the last attempt')) {
    return (what: 'Call $name again', why: 'Customer did not answer last time.', amount: collect, then: 'Record what happened on the call.', note: null);
  }
  if (low.startsWith('dispute clarification needed')) {
    return (what: 'Answer the RE\'s question', why: 'RE asks: ${grab(r':\s*(.+)$') ?? ''}', amount: null, then: 'Reply in the thread below.', note: null);
  }
  if (low.startsWith('dispute resolution')) {
    return (what: 'Sort out this dispute', why: grab(r':\s*(.+)$') ?? '', amount: null, then: 'Mark it resolved when done.', note: null);
  }
  if (low.startsWith('customer refused')) {
    final reason = grab(r'Reason:\s*(.+?)\s*(?:Notes?:|$)');
    return (
      what: 'Call $name again',
      why: reason != null && reason.isNotEmpty ? 'Customer refused to pay. Reason: $reason.' : 'Customer refused to pay.',
      amount: collect,
      then: then ?? 'Record what the customer says.',
      note: grab(r'Notes?:\s*(.+)$'),
    );
  }
  final dispute = RegExp(r'Dispute of\s+(₹\s?[\d,]+)\s+(raised|approved|rejected)', caseSensitive: false).firstMatch(text);
  if (dispute != null) {
    final amt = dispute.group(1);
    final why = switch (dispute.group(2)!.toLowerCase()) {
      'raised' => 'You raised a $amt dispute. The RE is checking it. Collect the rest.',
      'approved' => 'The RE accepted the $amt dispute. Collect the rest.',
      _ => 'The RE rejected the $amt dispute${grab(r'Reason:\s*"?(.+?)"?\.?\s*(?:Collect|$)') != null ? ' (${grab(r'Reason:\s*"?(.+?)"?\.?\s*(?:Collect|$)')})' : ''}. The full amount is due.',
    };
    return (what: 'Call $name', why: why, amount: collect, then: then, note: null);
  }
  if (low.startsWith('internal action')) {
    return (what: 'Call $name', why: 'The RE has finished the internal check. Continue collecting.', amount: collect, then: then, note: null);
  }
  if (low.startsWith('physical visit completed')) {
    return (what: 'Call $name', why: 'The RE visited the customer. See the notes in History.', amount: collect, then: then, note: null);
  }
  if (low.startsWith('physical visit could not')) {
    return (what: 'Call $name', why: 'The RE could not do the visit. See the notes in History.', amount: collect, then: then, note: null);
  }
  if (RegExp(r'^L\d escalation resolved', caseSensitive: false).hasMatch(text)) {
    return (what: 'Call $name', why: 'The escalation is closed. Start collecting again.', amount: collect, then: then, note: null);
  }
  final ptp = RegExp(r'the PTP for\s+(₹\s?[\d.,]+)', caseSensitive: false).firstMatch(text);
  if (ptp != null) {
    return (what: 'Call $name', why: 'Customer promised ${ptp.group(1)!.replaceAll(RegExp(r'\.0+$'), '')} but did not pay.', amount: collect, then: 'Get a new promise to pay.', note: null);
  }
  // Unknown wording — keep the original, minus the "Collect ₹X, …" tail
  // (shown separately below).
  final body = text.replaceAll(RegExp(r'\s*Collect\s+₹.*$', dotAll: true), '').trim();
  return (what: body.isEmpty ? 'Call $name' : body, why: '', amount: collect, then: then, note: null);
}

Widget _descriptionCard(String text, String customerName, Color accent) {
  final t = plainTask(text, customerName);
  Widget label(String l) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: kMuted)),
      );
  Widget gap() => const SizedBox(height: 10);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('WHAT TO DO'),
        Text(t.what, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kDark, height: 1.35)),
        if (t.why.isNotEmpty) ...[
          gap(),
          label('WHY'),
          Text(t.why, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: accent, height: 1.35)),
        ],
        if (t.note != null && t.note!.isNotEmpty) ...[
          gap(),
          label('NOTE'),
          Text(t.note!, style: const TextStyle(fontSize: 12.5, color: kDark, height: 1.35)),
        ],
        if (t.amount != null) ...[
          gap(),
          label('AMOUNT TO COLLECT'),
          Text(t.amount!, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: accent)),
        ],
        if (t.then != null) ...[
          gap(),
          label('THEN'),
          Text(t.then!, style: const TextStyle(fontSize: 12.5, color: kDark, height: 1.35)),
        ],
      ],
    ),
  );
}
