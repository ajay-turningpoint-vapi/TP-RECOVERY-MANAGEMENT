enum NotificationSeverity { info, actionRequired, warning, critical }

class NotificationItem {
  final String id;
  final NotificationSeverity severity;
  final String title;
  final String body;
  final String? customerId;
  final DateTime timestamp;
  final bool read;

  NotificationItem({
    required this.id,
    required this.severity,
    required this.title,
    required this.body,
    this.customerId,
    DateTime? timestamp,
    this.read = false,
  }) : timestamp = timestamp ?? DateTime.now();

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      severity: NotificationSeverity.values.byName(json['severity'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      customerId: json['customerId'] as String?,
      // .toLocal() — see task.dart's fromJson for why this matters.
      timestamp: DateTime.parse(json['createdAt'] as String).toLocal(),
      read: json['isRead'] as bool,
    );
  }

  NotificationItem copyWith({bool? read}) {
    return NotificationItem(
      id: id,
      severity: severity,
      title: title,
      body: body,
      customerId: customerId,
      timestamp: timestamp,
      read: read ?? this.read,
    );
  }
}
