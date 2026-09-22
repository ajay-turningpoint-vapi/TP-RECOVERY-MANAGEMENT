enum TaskType {
  customerCall,
  physicalVisit,
  disputeResolution,
  documentFollowUp,
  financialTeamFollowUp,
  customerDetailCorrection,
  paymentVerification,
  managementInstruction,
}

enum TaskStatus {
  pending,
  inProgress,
  completed,
  completedAwaitingVerification,
  closed,
}

/// Friendlier display text for a task's raw `reason` in specific known
/// cases where the stored string doubles as an internal matching key
/// (server-side, matched by exact equality — see customerService.js's
/// NON_CONTACT_VISIT_REASON / missedDeadlineService.js's VISIT_REASON, both
/// literally 'Non-response threshold reached') and so can't just be reworded
/// at the source without breaking that lookup. Falls through unchanged for
/// every other reason.
String friendlyTaskReason(String reason) {
  if (reason == 'Non-response threshold reached') {
    return 'No answer on 3 attempts — a Physical Visit is required now.';
  }
  return reason;
}

class AppTask {
  final String id;
  final TaskType type;
  final String customerId;
  final String customerName;
  final String ownerId;
  final DateTime deadline;
  final String priority;
  final String reason;
  final TaskStatus status;
  final String? outcome;
  final String? approvalStatus; // null, 'Pending', 'Approved'
  final String? pendingReason;
  final DateTime? pendingDeadline;
  final String? pendingPriority;
  final String source;
  final DateTime? completedAt;
  final DateTime createdAt;
  final bool reviewedByRE;
  // Real decision detail + evidence, threaded onto the task itself — e.g.
  // the auto-created "call customer" follow-up after RE approves/rejects
  // a Payment Already Made / Dispute / Internal Action outcome.
  final String? note;
  final String? attachmentPath;
  /// Set when this task is an RE dispute-clarification request — the
  /// salesperson answers from the task instead of recording an outcome.
  final String? disputeId;

  AppTask({
    required this.id,
    required this.type,
    required this.customerId,
    required this.customerName,
    required this.ownerId,
    required this.deadline,
    this.priority = 'Normal',
    required this.reason,
    this.status = TaskStatus.pending,
    this.outcome,
    this.approvalStatus,
    this.pendingReason,
    this.pendingDeadline,
    this.pendingPriority,
    this.source = 'System',
    this.completedAt,
    required this.createdAt,
    this.reviewedByRE = false,
    this.note,
    this.attachmentPath,
    this.disputeId,
  });

  bool get isOverdue => status != TaskStatus.completed && status != TaskStatus.closed && deadline.isBefore(DateTime.now());

  /// Builds an AppTask from the TP-RMS API's task JSON shape. The server
  /// doesn't send a denormalized customer name (only `customerId`), so the
  /// caller supplies it — usually resolved from an already-fetched customer
  /// list.
  factory AppTask.fromJson(Map<String, dynamic> json, {String? customerName}) {
    return AppTask(
      id: json['id'] as String,
      type: TaskType.values.byName(json['type'] as String),
      customerId: json['customerId'] as String,
      customerName: customerName ?? json['customerId'] as String,
      ownerId: json['ownerId'] as String,
      // The server sends every timestamp as a UTC ISO string — .toLocal()
      // converts it to real IST wall-clock time. Without it, DateFormat
      // renders the raw UTC fields as if they were local, showing every
      // deadline 5h30m earlier than its real IST time (confirmed empirically:
      // an 11:33 UTC / 17:03 IST deadline displayed as "11:33" everywhere).
      deadline: DateTime.parse(json['deadline'] as String).toLocal(),
      priority: json['priority'] as String? ?? 'Normal',
      reason: json['reason'] as String,
      status: TaskStatus.values.byName(json['status'] as String),
      outcome: json['outcome'] as String?,
      approvalStatus: json['approvalStatus'] as String?,
      pendingReason: json['pendingReason'] as String?,
      pendingDeadline: json['pendingDeadline'] != null ? DateTime.parse(json['pendingDeadline'] as String).toLocal() : null,
      pendingPriority: json['pendingPriority'] as String?,
      source: json['source'] as String? ?? 'System',
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String).toLocal() : null,
      // Falls back to the deadline for the rare payload that omits it
      // (never happens from the real API — taskRepository always sends
      // it — but keeps this constructor safe for any hand-built json).
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String).toLocal()
          : DateTime.parse(json['deadline'] as String).toLocal(),
      reviewedByRE: json['reviewedByRE'] as bool? ?? false,
      note: json['note'] as String?,
      attachmentPath: json['attachmentPath'] as String?,
      disputeId: json['disputeId'] as String?,
    );
  }

  AppTask copyWith({
    String? id,
    TaskType? type,
    String? customerId,
    String? customerName,
    String? ownerId,
    DateTime? deadline,
    String? priority,
    String? reason,
    TaskStatus? status,
    String? outcome,
    String? approvalStatus,
    String? pendingReason,
    DateTime? pendingDeadline,
    String? pendingPriority,
    String? source,
    DateTime? completedAt,
    DateTime? createdAt,
    bool? reviewedByRE,
    String? note,
    String? attachmentPath,
    String? disputeId,
  }) {
    return AppTask(
      id: id ?? this.id,
      type: type ?? this.type,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      ownerId: ownerId ?? this.ownerId,
      deadline: deadline ?? this.deadline,
      priority: priority ?? this.priority,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      outcome: outcome ?? this.outcome,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      pendingReason: pendingReason ?? this.pendingReason,
      pendingDeadline: pendingDeadline ?? this.pendingDeadline,
      pendingPriority: pendingPriority ?? this.pendingPriority,
      source: source ?? this.source,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      reviewedByRE: reviewedByRE ?? this.reviewedByRE,
      note: note ?? this.note,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      disputeId: disputeId ?? this.disputeId,
    );
  }
}
