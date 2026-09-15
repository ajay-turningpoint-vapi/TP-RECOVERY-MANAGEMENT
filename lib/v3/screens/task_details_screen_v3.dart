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

    final events = customer.auditHistory.reversed
        .map((a) => TimelineEvent(icon: Icons.history, color: kMuted, title: a.type, subtitle: a.description, date: a.timestamp, tag: a.actor, tagColor: kBlue))
        .take(5)
        .toList();

    final typeLabel = isResolutionTask
        ? 'Dispute Resolution'
        : (isClarification ? 'Dispute Clarification' : taskTypeLabel(t.type));
    final typeIcon = isResolutionTask
        ? Icons.gavel_outlined
        : (isClarification ? Icons.help_outline : taskTypeIcon(t.type));

    return RequestDetailScaffold(
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
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _resolveDispute(context, store, t),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Resolve Dispute', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
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
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: customer))),
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Take Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ),
                    ])),
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
                    const SizedBox(height: 2),
                    CallablePhoneNumber(phoneNumber: customer.contactNumber, iconSize: 12, style: const TextStyle(fontSize: 10.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Outstanding', style: TextStyle(fontSize: 10, color: kMuted)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(customer.totalOutstanding), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kRed))),
                  Text('${customer.oldestOverdueDays} Days Overdue', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ],
          ),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('TASK INFORMATION'),
        InfoCard(children: [
          KeyValueRow('Task Type', typeLabel),
          KeyValueRow('Assigned To', store.salesmanDisplayName(t.ownerId)),
          KeyValueRow('Priority', t.priority, valueColor: color),
          KeyValueRow('Status', t.status.name[0].toUpperCase() + t.status.name.substring(1)),
          KeyValueRow('Source', t.source),
          KeyValueRow('Deadline', DateFormat('dd MMM yyyy, hh:mm a').format(t.deadline), valueColor: (!isDone && t.isOverdue) ? kRed : kDark),
          if (t.approvalStatus == 'Pending') KeyValueRow('Extension Requested', t.pendingDeadline != null ? DateFormat('dd MMM yyyy').format(t.pendingDeadline!) : '-', valueColor: kAmber),
        ]),
        const SizedBox(height: 18),
        const SectionLabel('TASK DESCRIPTION'),
        InfoCard(children: [Text(t.reason, style: const TextStyle(fontSize: 12.5, color: kDark))]),
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
        const SizedBox(height: 18),
        const SectionLabel('CUSTOMER ACTIVITY'),
        ActivityTimeline(events),
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
                decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.25))),
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
              Row(children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () async {
                    final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (p != null) setSheet(() => picked = p);
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 15),
                  label: Text(picked == null ? 'Attach photo' : 'Photo attached', style: const TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () async {
                    final p = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
                    if (p != null) setSheet(() => picked = p);
                  },
                  icon: const Icon(Icons.photo_camera_outlined, size: 15),
                  label: const Text('Camera', style: TextStyle(fontSize: 11.5)),
                ),
              ]),
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
                      Navigator.pop(sheetCtx);
                      showAppMessage(navigator.context, message: 'Message sent.');
                    } catch (e) {
                      setSheet(() => busy = false);
                      showAppMessage(navigator.context, message: 'Could not send: $e', isError: true);
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

  void _resolveDispute(BuildContext context, AppStore store, AppTask t) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resolve Dispute', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Marks the dispute resolved and closes this task. The salesman who raised it gets a follow-up task.',
                style: TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 12),
            TextField(controller: noteController, maxLines: 2,
                decoration: const InputDecoration(hintText: 'Resolution note (optional)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white),
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(dialogCtx);
              try {
                await store.resolveDisputeByOwner(t.disputeId!, t.id, note: noteController.text.trim());
                navigator.pop();
                showAppMessageAfter(navigator, message: 'Dispute resolved.');
              } catch (e) {
                showAppMessageAfter(navigator, message: 'Could not resolve: $e', isError: true);
              }
            },
            child: const Text('Resolve', style: TextStyle(fontWeight: FontWeight.bold)),
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
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final body = controller.text.trim();
                  if (body.isEmpty) return;
                  final navigator = Navigator.of(context);
                  Navigator.pop(sheetCtx);
                  try {
                    await store.answerDisputeClarification(t.disputeId!, t.id, body);
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
