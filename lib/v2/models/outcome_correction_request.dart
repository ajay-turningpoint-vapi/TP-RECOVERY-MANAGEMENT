class OutcomeCorrectionRequest {
  final String id;
  final String customerId;
  final String customerName;
  final String salesmanId;
  final String originalOutcome;
  final String originalReason;
  final String requestedOutcome;
  final String requestedReason;
  final String requestNote;
  final String status; // 'Pending' | 'Approved' | 'Rejected'
  final DateTime requestedAt;

  OutcomeCorrectionRequest({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.salesmanId,
    required this.originalOutcome,
    required this.originalReason,
    required this.requestedOutcome,
    required this.requestedReason,
    required this.requestNote,
    this.status = 'Pending',
    DateTime? requestedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  /// Builds from the TP-RMS API's `GET /api/outcome-corrections` shape.
  /// `customerName` isn't tracked server-side — resolved from the
  /// already-loaded customers list by the caller.
  factory OutcomeCorrectionRequest.fromJson(Map<String, dynamic> json, {required String customerName}) {
    return OutcomeCorrectionRequest(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      customerName: customerName,
      salesmanId: json['salesmanId'] as String,
      originalOutcome: json['originalOutcome'] as String,
      originalReason: json['originalReason'] as String,
      requestedOutcome: json['requestedOutcome'] as String,
      requestedReason: json['requestedReason'] as String,
      requestNote: json['requestNote'] as String,
      status: json['status'] as String,
      // .toLocal() — see task.dart's fromJson for why this matters.
      requestedAt: DateTime.parse(json['requestedAt'] as String).toLocal(),
    );
  }

  OutcomeCorrectionRequest copyWith({String? status}) {
    return OutcomeCorrectionRequest(
      id: id,
      customerId: customerId,
      customerName: customerName,
      salesmanId: salesmanId,
      originalOutcome: originalOutcome,
      originalReason: originalReason,
      requestedOutcome: requestedOutcome,
      requestedReason: requestedReason,
      requestNote: requestNote,
      status: status ?? this.status,
      requestedAt: requestedAt,
    );
  }
}
