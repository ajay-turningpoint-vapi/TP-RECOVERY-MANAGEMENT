/// A salesperson's staged edit to a recorded outcome's own fields (PTP
/// amount/date/mode, dispute amount/reason, payment-claim amount/ref,
/// follow-up date, or a simple call outcome's reason). Nothing changes on
/// the underlying record until an RE approves — mirrors the PTP-correction
/// guarantee, generalised to every outcome type.
/// API shape: `GET /api/outcome-edits`.
class OutcomeEditRequest {
  final String id;
  final String customerId;
  final String customerName; // not server-side — resolved by the caller
  final String salesmanId;
  final String outcomeKind; // 'PTP' | 'PaymentClaim' | 'Dispute' | 'FollowUp' | 'Simple'
  final String? artifactId;
  final Map<String, dynamic> originalPayload;
  final Map<String, dynamic> requestedPayload;
  final String editReason;
  final String status; // 'Pending' | 'Approved' | 'Rejected'
  final String? rejectionReason;
  final DateTime requestedAt;

  OutcomeEditRequest({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.salesmanId,
    required this.outcomeKind,
    required this.artifactId,
    required this.originalPayload,
    required this.requestedPayload,
    required this.editReason,
    this.status = 'Pending',
    this.rejectionReason,
    DateTime? requestedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  factory OutcomeEditRequest.fromJson(Map<String, dynamic> json, {required String customerName}) {
    return OutcomeEditRequest(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      customerName: customerName,
      salesmanId: json['salesmanId'] as String,
      outcomeKind: json['outcomeKind'] as String,
      artifactId: json['artifactId'] as String?,
      originalPayload: ((json['originalPayload'] as Map?) ?? const {}).cast<String, dynamic>(),
      requestedPayload: ((json['requestedPayload'] as Map?) ?? const {}).cast<String, dynamic>(),
      editReason: json['editReason'] as String? ?? '',
      status: json['status'] as String? ?? 'Pending',
      rejectionReason: json['rejectionReason'] as String?,
      requestedAt: DateTime.parse(json['requestedAt'] as String).toLocal(),
    );
  }
}
