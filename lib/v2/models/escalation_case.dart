class EscalationCase {
  final String id;
  final String customerId;
  final String customerName;
  final String level; // 'L2' | 'L3' | 'L4'
  final String reason;
  final String plan;
  final String ownerId;
  final DateTime deadline;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<String> history;
  final double moneyAtRisk;

  EscalationCase({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.level,
    required this.reason,
    required this.plan,
    required this.ownerId,
    required this.deadline,
    DateTime? createdAt,
    this.resolvedAt,
    this.history = const [],
    this.moneyAtRisk = 0.0,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isOpen => resolvedAt == null;

  /// Builds an EscalationCase from the TP-RMS API's escalation JSON. The
  /// server doesn't send a denormalized customer name (only `customerId`)
  /// or a per-case history log (that's tracked via the customer's own
  /// auditHistory instead — ESCALATION_RAISED/ESCALATION_RESOLVED events)
  /// — the caller supplies the name, and a single reasonable history line
  /// is synthesized here for the same display purpose the local demo
  /// path's `history` list served.
  factory EscalationCase.fromJson(Map<String, dynamic> json, {required String customerName}) {
    final level = json['level'] as String;
    final reason = json['reason'] as String;
    final isOpen = json['isOpen'] as bool;
    return EscalationCase(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      customerName: customerName,
      level: level,
      reason: reason,
      plan: json['plan'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      // .toLocal() — see task.dart's fromJson for why this matters.
      deadline: json['deadline'] != null ? DateTime.parse(json['deadline'] as String).toLocal() : DateTime.parse(json['createdAt'] as String).toLocal(),
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      resolvedAt: isOpen ? null : DateTime.parse(json['updatedAt'] as String).toLocal(),
      history: ['Escalated to $level: $reason${isOpen ? '' : ' — Resolved'}'],
      moneyAtRisk: (json['moneyAtRisk'] as num).toDouble(),
    );
  }

  EscalationCase copyWith({
    String? level,
    String? reason,
    String? plan,
    String? ownerId,
    DateTime? deadline,
    DateTime? resolvedAt,
    List<String>? history,
    double? moneyAtRisk,
  }) {
    return EscalationCase(
      id: id,
      customerId: customerId,
      customerName: customerName,
      level: level ?? this.level,
      reason: reason ?? this.reason,
      plan: plan ?? this.plan,
      ownerId: ownerId ?? this.ownerId,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      history: history ?? this.history,
      moneyAtRisk: moneyAtRisk ?? this.moneyAtRisk,
    );
  }
}
