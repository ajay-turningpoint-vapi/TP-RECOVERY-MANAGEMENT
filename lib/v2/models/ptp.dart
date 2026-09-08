enum PtpStatus {
  scheduled,
  // Due date has arrived; waiting out the 1-day BUSY-receipt grace period
  // before the server's PTP verification service (folded into the nightly
  // BUSY sync) finalizes this to kept/partiallyKept/broken.
  pendingVerification,
  kept,
  partiallyKept,
  broken,
  financialSyncPending,
}

class PromiseToPay {
  final String id;
  final String customerId;
  final double amountPromised;
  final DateTime promiseDate;
  final String paymentMode;
  final PtpStatus status;
  final double? amountReceived;

  // PTP correction request (spec §20)
  final double? correctionRequestedAmount;
  final DateTime? correctionRequestedDate;
  final String? correctionReason;
  final String correctionStatus; // 'none' | 'Pending' | 'Approved' | 'Rejected'

  // Set only when status is broken — the recorded reason the promise failed
  // (spec: PTP Broken Report "Top Reasons" breakdown).
  final String? brokenReason;

  PromiseToPay({
    required this.id,
    required this.customerId,
    required this.amountPromised,
    required this.promiseDate,
    required this.paymentMode,
    this.status = PtpStatus.scheduled,
    this.amountReceived,
    this.correctionRequestedAmount,
    this.correctionRequestedDate,
    this.correctionReason,
    this.correctionStatus = 'none',
    this.brokenReason,
  });

  factory PromiseToPay.fromJson(Map<String, dynamic> json) {
    return PromiseToPay(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      amountPromised: (json['amountPromised'] as num).toDouble(),
      // .toLocal() — see task.dart's fromJson for why this matters (server
      // sends UTC, DateFormat never auto-converts).
      promiseDate: DateTime.parse(json['promiseDate'] as String).toLocal(),
      paymentMode: json['paymentMode'] as String,
      status: PtpStatus.values.byName(json['status'] as String),
      correctionRequestedAmount: (json['correctionRequestedAmount'] as num?)?.toDouble(),
      correctionRequestedDate: json['correctionRequestedDate'] != null ? DateTime.parse(json['correctionRequestedDate'] as String).toLocal() : null,
      correctionReason: json['correctionReason'] as String?,
      correctionStatus: json['correctionStatus'] as String? ?? 'none',
      amountReceived: (json['amountReceived'] as num?)?.toDouble(),
      brokenReason: json['brokenReason'] as String?,
    );
  }

  PromiseToPay copyWith({
    String? id,
    String? customerId,
    double? amountPromised,
    DateTime? promiseDate,
    String? paymentMode,
    PtpStatus? status,
    double? amountReceived,
    double? correctionRequestedAmount,
    DateTime? correctionRequestedDate,
    String? correctionReason,
    String? correctionStatus,
    String? brokenReason,
  }) {
    return PromiseToPay(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      amountPromised: amountPromised ?? this.amountPromised,
      promiseDate: promiseDate ?? this.promiseDate,
      paymentMode: paymentMode ?? this.paymentMode,
      status: status ?? this.status,
      amountReceived: amountReceived ?? this.amountReceived,
      correctionRequestedAmount: correctionRequestedAmount ?? this.correctionRequestedAmount,
      correctionRequestedDate: correctionRequestedDate ?? this.correctionRequestedDate,
      correctionReason: correctionReason ?? this.correctionReason,
      correctionStatus: correctionStatus ?? this.correctionStatus,
      brokenReason: brokenReason ?? this.brokenReason,
    );
  }
}
