class AuditEvent {
  final DateTime timestamp;
  final String description;
  final String type;
  final String actor;
  final String? previousState;
  final String? newState;
  final String source;
  // The server-assigned filename for an uploaded evidence photo (e.g. a
  // call screenshot) — see ApiClient.attachmentUrl / uploadAttachment and
  // server/src/routes/attachmentRoutes.js. Null for the overwhelming
  // majority of audit events, which have no attached evidence.
  final String? attachmentPath;

  AuditEvent({
    required this.timestamp,
    required this.description,
    required this.type,
    this.actor = 'System',
    this.previousState,
    this.newState,
    this.source = 'App',
    this.attachmentPath,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      // .toLocal() — see task.dart's fromJson for why this matters.
      timestamp: DateTime.parse(json['occurredAt'] as String).toLocal(),
      description: json['description'] as String,
      type: json['type'] as String,
      actor: json['actor'] as String? ?? 'System',
      previousState: json['previousState'] as String?,
      newState: json['newState'] as String?,
      source: json['source'] as String? ?? 'App',
      attachmentPath: json['attachmentPath'] as String?,
    );
  }
}

class Customer {
  final String id;
  final String name;
  final double totalOutstanding;
  final double totalDue;
  final int oldestOverdueDays;
  final String? activePtpDetails;
  final String currentRecoveryState;
  final String primaryNextAction;
  final String reasonForAction;
  final String assignedSalesmanId;
  final String contactNumber;
  final String alternateContactNumber;
  final List<AuditEvent> auditHistory;
  
  // New Financial Fields
  final double? lastPaymentAmount;
  final DateTime? lastPaymentDate;
  final double creditLimit;
  final double availableLimit;
  final int creditDays;
  final Map<String, double> agingBuckets;
  final List<Map<String, dynamic>> invoices;

  // BUSY-sourced fields (SALESPERSON's "Customers" nav — see
  // busyCustomerService.js on the server). Null/zero for RMS-sourced
  // customers (RE/Management), which don't carry this data.
  final String? address;
  final String? gstNo;
  final double futureDue;
  final int? maxDaysOverdue;
  final String? outstandingStatus;
  final double age0_30;
  final double age31_60;
  final double age61_90;
  final double age90Plus;

  // RE / control-layer fields
  final String escalationLevel; // 'none' | 'L1' | 'L2' | 'L3' | 'L4'
  final bool ownerMappingRequired;
  final bool hasValidNextAction;
  final DateTime financialFreshness;
  final int? creditHealthScore; // null => Insufficient History
  final Map<String, num>? creditHealthComponents; // server-computed breakdown, RMS-06
  final double disputedAmount;
  final String branch;
  final String customerCategory; // e.g. Carpenter, Contractor, End Customer, Builder, Distributor
  final int noAnswerAttempts; // real server-tracked count (customerService.recordOutcome's No Answer threshold)
  // When this row was last written server-side. NOT a safe "was this
  // customer's outcome recorded today" signal on its own — the daily BUSY
  // sync (customerAgeingSync/customerInvoiceSync) rewrites every synced
  // customer's row once a day regardless of whether the salesperson
  // touched them, so updatedAt gets bumped for the whole portfolio right
  // along with it. For anything date-sensitive ("was this done today"),
  // use AppStore.recoveryDoneTodayCustomerIds instead — grounded in the
  // real audit trail (a Record-Outcome-sourced event today), which a
  // sync's unrelated writes can't fool. Kept here only as raw data.
  final DateTime? updatedAt;

  /// True when the last thing recorded for this customer was "No Answer"
  /// and nothing since has replaced it — the one recovery state Record
  /// Outcome locks on the customer screen (see Customer360Screen's
  /// `isLocked`): the salesman must go through Today's Recovery Tasks'
  /// "Edit Recorded Outcome" to erase it and record what really happened
  /// (see customerService.recordOutcome's `replacingNoAnswer` branch).
  bool get isPendingNoAnswerEdit =>
      currentRecoveryState == 'Action Required' &&
      primaryNextAction == 'Call Customer' &&
      reasonForAction == 'No Answer';

  String get creditHealthBand {
    if (creditHealthScore == null) return 'Insufficient History';
    final s = creditHealthScore!;
    if (s >= 85) return 'Low Risk';
    if (s >= 70) return 'Moderate';
    if (s >= 50) return 'High';
    return 'Critical';
  }

  Customer({
    required this.id,
    required this.name,
    required this.totalOutstanding,
    required this.totalDue,
    required this.oldestOverdueDays,
    this.activePtpDetails,
    required this.currentRecoveryState,
    required this.primaryNextAction,
    required this.reasonForAction,
    required this.assignedSalesmanId,
    this.contactNumber = '9876543210',
    this.alternateContactNumber = '9876543211',
    this.auditHistory = const [],
    this.lastPaymentAmount,
    this.lastPaymentDate,
    this.creditLimit = 0.0,
    this.availableLimit = 0.0,
    this.creditDays = 30,
    this.agingBuckets = const {},
    this.invoices = const [],
    this.address,
    this.gstNo,
    this.futureDue = 0.0,
    this.maxDaysOverdue,
    this.outstandingStatus,
    this.age0_30 = 0.0,
    this.age31_60 = 0.0,
    this.age61_90 = 0.0,
    this.age90Plus = 0.0,
    this.escalationLevel = 'none',
    this.ownerMappingRequired = false,
    this.hasValidNextAction = true,
    DateTime? financialFreshness,
    this.creditHealthScore,
    this.creditHealthComponents,
    this.disputedAmount = 0.0,
    this.branch = 'Turning Point',
    this.customerCategory = 'End Customer',
    this.noAnswerAttempts = 0,
    this.updatedAt,
  }) : financialFreshness = financialFreshness ?? DateTime.now();

  /// Builds a Customer from either the RMS `GET /api/customers[/:id]`
  /// response shape (RECOVERY_EXECUTIVE/MANAGEMENT) or the BUSY-sourced
  /// shape (SALESPERSON — see server/src/services/busyCustomerService.js).
  /// The two shapes barely overlap, so every RMS-only field is optional
  /// here with a sensible default rather than a required cast — a BUSY
  /// response has no `oldestOverdueDays`/`currentRecoveryState`/etc., and
  /// must not crash parsing.
  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      name: json['name'] as String,
      totalOutstanding: (json['totalOutstanding'] as num?)?.toDouble() ?? 0.0,
      // BUSY's detail response calls this `overdueAmount` (more accurate
      // name for what it is) rather than RMS's `totalDue` — same "Overdue
      // Amount" UI slot, so both keys map onto the same field here rather
      // than touching every existing c.totalDue reference in the app.
      totalDue: (json['totalDue'] as num?)?.toDouble() ?? (json['overdueAmount'] as num?)?.toDouble() ?? 0.0,
      oldestOverdueDays: json['oldestOverdueDays'] as int? ?? 0,
      currentRecoveryState: json['currentRecoveryState'] as String? ?? '',
      primaryNextAction: json['primaryNextAction'] as String? ?? '',
      reasonForAction: json['reasonForAction'] as String? ?? '',
      assignedSalesmanId: json['assignedSalesmanId'] as String? ?? '',
      // BUSY's `mobile` maps onto the same "contact number" the UI already
      // displays — no separate BUSY-specific phone widget needed.
      contactNumber: json['contactNumber'] as String? ?? json['mobile'] as String? ?? '',
      alternateContactNumber: json['alternateContactNumber'] as String? ?? '',
      auditHistory: (json['auditHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      invoices: (json['invoices'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      lastPaymentAmount: (json['lastPaymentAmount'] as num?)?.toDouble(),
      lastPaymentDate: json['lastPaymentDate'] != null ? DateTime.tryParse(json['lastPaymentDate'] as String)?.toLocal() : null,
      creditLimit: (json['creditLimit'] as num?)?.toDouble() ?? 0.0,
      availableLimit: (json['availableLimit'] as num?)?.toDouble() ?? 0.0,
      creditDays: json['creditDays'] as int? ?? 30,
      address: json['address'] as String?,
      gstNo: json['gstNo'] as String?,
      futureDue: (json['futureDue'] as num?)?.toDouble() ?? 0.0,
      maxDaysOverdue: json['maxDaysOverdue'] as int?,
      outstandingStatus: json['outstandingStatus'] as String?,
      age0_30: ((json['ageingBuckets'] as Map<String, dynamic>?)?['age0_30'] as num?)?.toDouble() ?? 0.0,
      age31_60: ((json['ageingBuckets'] as Map<String, dynamic>?)?['age31_60'] as num?)?.toDouble() ?? 0.0,
      age61_90: ((json['ageingBuckets'] as Map<String, dynamic>?)?['age61_90'] as num?)?.toDouble() ?? 0.0,
      age90Plus: ((json['ageingBuckets'] as Map<String, dynamic>?)?['age90Plus'] as num?)?.toDouble() ?? 0.0,
      escalationLevel: json['escalationLevel'] as String? ?? 'none',
      ownerMappingRequired: json['ownerMappingRequired'] as bool? ?? false,
      hasValidNextAction: json['hasValidNextAction'] as bool? ?? true,
      creditHealthScore: json['creditHealthScore'] as int?,
      creditHealthComponents: (json['creditHealthComponents'] as Map<String, dynamic>?)?.cast<String, num>(),
      disputedAmount: (json['disputedAmount'] as num?)?.toDouble() ?? 0.0,
      branch: json['branch'] as String? ?? 'Turning Point',
      noAnswerAttempts: json['noAnswerAttempts'] as int? ?? 0,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      // Was never actually parsed from the server response — every
      // customer silently fell back to DateTime.now(), so the RE's
      // "Financials synced ..." badge always read "just now" no matter how
      // stale the BUSY data actually was. Real value now comes from
      // customerRepository.mapCustomer's financialFreshness field
      // (busy_last_synced_at, falling back to updated_at).
      financialFreshness: json['financialFreshness'] != null
          ? DateTime.tryParse(json['financialFreshness'] as String)?.toLocal()
          : null,
    );
  }

  Customer copyWith({
    String? id,
    String? name,
    double? totalOutstanding,
    double? totalDue,
    int? oldestOverdueDays,
    String? activePtpDetails,
    String? currentRecoveryState,
    String? primaryNextAction,
    String? reasonForAction,
    String? assignedSalesmanId,
    List<AuditEvent>? auditHistory,
    double? lastPaymentAmount,
    DateTime? lastPaymentDate,
    double? creditLimit,
    double? availableLimit,
    int? creditDays,
    Map<String, double>? agingBuckets,
    List<Map<String, dynamic>>? invoices,
    String? address,
    String? gstNo,
    double? futureDue,
    int? maxDaysOverdue,
    String? outstandingStatus,
    double? age0_30,
    double? age31_60,
    double? age61_90,
    double? age90Plus,
    String? escalationLevel,
    bool? ownerMappingRequired,
    bool? hasValidNextAction,
    DateTime? financialFreshness,
    int? creditHealthScore,
    bool clearCreditHealthScore = false,
    double? disputedAmount,
    String? branch,
    String? customerCategory,
    String? contactNumber,
    String? alternateContactNumber,
    int? noAnswerAttempts,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      totalOutstanding: totalOutstanding ?? this.totalOutstanding,
      totalDue: totalDue ?? this.totalDue,
      oldestOverdueDays: oldestOverdueDays ?? this.oldestOverdueDays,
      activePtpDetails: activePtpDetails ?? this.activePtpDetails,
      currentRecoveryState: currentRecoveryState ?? this.currentRecoveryState,
      primaryNextAction: primaryNextAction ?? this.primaryNextAction,
      reasonForAction: reasonForAction ?? this.reasonForAction,
      assignedSalesmanId: assignedSalesmanId ?? this.assignedSalesmanId,
      contactNumber: contactNumber ?? this.contactNumber,
      alternateContactNumber: alternateContactNumber ?? this.alternateContactNumber,
      auditHistory: auditHistory ?? this.auditHistory,
      lastPaymentAmount: lastPaymentAmount ?? this.lastPaymentAmount,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
      creditLimit: creditLimit ?? this.creditLimit,
      availableLimit: availableLimit ?? this.availableLimit,
      creditDays: creditDays ?? this.creditDays,
      agingBuckets: agingBuckets ?? this.agingBuckets,
      invoices: invoices ?? this.invoices,
      address: address ?? this.address,
      gstNo: gstNo ?? this.gstNo,
      futureDue: futureDue ?? this.futureDue,
      maxDaysOverdue: maxDaysOverdue ?? this.maxDaysOverdue,
      outstandingStatus: outstandingStatus ?? this.outstandingStatus,
      age0_30: age0_30 ?? this.age0_30,
      age31_60: age31_60 ?? this.age31_60,
      age61_90: age61_90 ?? this.age61_90,
      age90Plus: age90Plus ?? this.age90Plus,
      escalationLevel: escalationLevel ?? this.escalationLevel,
      ownerMappingRequired: ownerMappingRequired ?? this.ownerMappingRequired,
      hasValidNextAction: hasValidNextAction ?? this.hasValidNextAction,
      financialFreshness: financialFreshness ?? this.financialFreshness,
      creditHealthScore: clearCreditHealthScore ? null : (creditHealthScore ?? this.creditHealthScore),
      disputedAmount: disputedAmount ?? this.disputedAmount,
      branch: branch ?? this.branch,
      customerCategory: customerCategory ?? this.customerCategory,
      noAnswerAttempts: noAnswerAttempts ?? this.noAnswerAttempts,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
