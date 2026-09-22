/// Every write action the offline queue knows how to replay. One value per
/// `AppStore` write method that's been wired into the queue (see
/// pending_action_queue.dart) — the queue dispatches on this only to decide
/// whether an attachment two-step upload applies (recordOutcome); every
/// other type is a plain POST of [PendingAction]'s targetEndpoint/payload.
enum PendingActionType {
  recordOutcome,
  ptpCorrectionRequest,
  ptpCorrectionApprove,
  ptpCorrectionReject,
  disputeApprove,
  disputeReject,
  disputeRequestInfo,
  disputeResolve,
  disputeResolveByOwner,
  disputeRejectByOwner,
  disputeMessage,
  disputeAnswer,
  paymentClaimVerify,
  taskComplete,
  taskApproveEdit,
  taskRejectEdit,
  taskReschedule,
  taskReassign,
}

enum PendingActionStatus { pending, inFlight, failedRetryable, failedTerminal, synced }
