import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/services/local_db.dart';
import 'package:salesman_mobile/services/pending_action.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';

const _kBlue = Color(0xFF0052CC);

String _typeLabel(String typeName) {
  final type = PendingActionType.values.firstWhere((t) => t.name == typeName, orElse: () => PendingActionType.recordOutcome);
  switch (type) {
    case PendingActionType.recordOutcome:
      return 'Record Outcome';
    case PendingActionType.ptpCorrectionRequest:
      return 'PTP Correction Requested';
    case PendingActionType.ptpCorrectionApprove:
      return 'PTP Correction Approved';
    case PendingActionType.ptpCorrectionReject:
      return 'PTP Correction Rejected';
    case PendingActionType.disputeApprove:
      return 'Dispute Approved';
    case PendingActionType.disputeReject:
      return 'Dispute Rejected';
    case PendingActionType.disputeRequestInfo:
      return 'Dispute — Info Requested';
    case PendingActionType.disputeResolve:
      return 'Dispute Resolved';
    case PendingActionType.disputeResolveByOwner:
      return 'Dispute Resolved (Owner)';
    case PendingActionType.disputeRejectByOwner:
      return 'Dispute — Wrong Owner';
    case PendingActionType.disputeMessage:
      return 'Dispute Message';
    case PendingActionType.disputeAnswer:
      return 'Dispute Clarification Answered';
    case PendingActionType.paymentClaimVerify:
      return 'Payment Claim Verified';
    case PendingActionType.taskComplete:
      return 'Task Completed';
    case PendingActionType.taskApproveEdit:
      return 'Task Extension Approved';
    case PendingActionType.taskRejectEdit:
      return 'Task Extension Rejected';
    case PendingActionType.taskReschedule:
      return 'Task Rescheduled';
    case PendingActionType.taskReassign:
      return 'Task Reassigned';
  }
}

/// Lists every action queued by AppStore's offline write queue (see
/// pending_action_queue.dart) for the signed-in user — what's still
/// waiting to sync, and anything that came back rejected (not a network
/// failure) and needs a decision. Reached by tapping the pending-sync
/// banner (sync_freeze_overlay.dart).
class PendingSyncScreen extends StatelessWidget {
  const PendingSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.pendingActions;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        title: const Text('Pending Sync'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('Nothing waiting to sync', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _PendingActionCard(action: items[i]),
            ),
    );
  }
}

class _PendingActionCard extends StatelessWidget {
  final PendingAction action;
  const _PendingActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final customer = action.relatedCustomerId == null
        ? null
        : store.customers.where((c) => c.id == action.relatedCustomerId).firstOrNull;
    final isTerminal = action.status == 'failedTerminal';
    final isRetryable = action.status == 'failedRetryable';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isTerminal ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTerminal ? Icons.error_outline_rounded : Icons.sync_rounded,
                size: 16,
                color: isTerminal ? const Color(0xFFDC2626) : _kBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_typeLabel(action.type), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
            ],
          ),
          if (customer != null) ...[
            const SizedBox(height: 6),
            Text(customer.name, style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
          ],
          const SizedBox(height: 4),
          Text(
            'Queued ${DateFormat('d MMM, h:mm a').format(action.createdAt)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          if (isTerminal && action.lastError != null) ...[
            const SizedBox(height: 8),
            Text(action.lastError!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626))),
          ],
          if (isRetryable) ...[
            const SizedBox(height: 6),
            const Text('Waiting for a connection…', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontStyle: FontStyle.italic)),
          ],
          if (isTerminal) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                LoadingTextButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await store.pendingActionQueue.discard(action.id);
                    showAppMessageAfter(navigator, message: 'Discarded');
                  },
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 4),
                LoadingElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kBlue, foregroundColor: Colors.white),
                  onPressed: () => store.pendingActionQueue.retryNow(action.id, store.currentSalesmanId),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
