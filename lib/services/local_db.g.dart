// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $CachedListsTable extends CachedLists
    with TableInfo<$CachedListsTable, CachedList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scopeUserIdMeta =
      const VerificationMeta('scopeUserId');
  @override
  late final GeneratedColumn<String> scopeUserId = GeneratedColumn<String>(
      'scope_user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastFetchedAtMeta =
      const VerificationMeta('lastFetchedAt');
  @override
  late final GeneratedColumn<DateTime> lastFetchedAt =
      GeneratedColumn<DateTime>('last_fetched_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, scopeUserId, json, lastFetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_lists';
  @override
  VerificationContext validateIntegrity(Insertable<CachedList> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('scope_user_id')) {
      context.handle(
          _scopeUserIdMeta,
          scopeUserId.isAcceptableOrUnknown(
              data['scope_user_id']!, _scopeUserIdMeta));
    } else if (isInserting) {
      context.missing(_scopeUserIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('last_fetched_at')) {
      context.handle(
          _lastFetchedAtMeta,
          lastFetchedAt.isAcceptableOrUnknown(
              data['last_fetched_at']!, _lastFetchedAtMeta));
    } else if (isInserting) {
      context.missing(_lastFetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key, scopeUserId};
  @override
  CachedList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedList(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      scopeUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scope_user_id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      lastFetchedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_fetched_at'])!,
    );
  }

  @override
  $CachedListsTable createAlias(String alias) {
    return $CachedListsTable(attachedDatabase, alias);
  }
}

class CachedList extends DataClass implements Insertable<CachedList> {
  final String key;
  final String scopeUserId;
  final String json;
  final DateTime lastFetchedAt;
  const CachedList(
      {required this.key,
      required this.scopeUserId,
      required this.json,
      required this.lastFetchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['scope_user_id'] = Variable<String>(scopeUserId);
    map['json'] = Variable<String>(json);
    map['last_fetched_at'] = Variable<DateTime>(lastFetchedAt);
    return map;
  }

  CachedListsCompanion toCompanion(bool nullToAbsent) {
    return CachedListsCompanion(
      key: Value(key),
      scopeUserId: Value(scopeUserId),
      json: Value(json),
      lastFetchedAt: Value(lastFetchedAt),
    );
  }

  factory CachedList.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedList(
      key: serializer.fromJson<String>(json['key']),
      scopeUserId: serializer.fromJson<String>(json['scopeUserId']),
      json: serializer.fromJson<String>(json['json']),
      lastFetchedAt: serializer.fromJson<DateTime>(json['lastFetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'scopeUserId': serializer.toJson<String>(scopeUserId),
      'json': serializer.toJson<String>(json),
      'lastFetchedAt': serializer.toJson<DateTime>(lastFetchedAt),
    };
  }

  CachedList copyWith(
          {String? key,
          String? scopeUserId,
          String? json,
          DateTime? lastFetchedAt}) =>
      CachedList(
        key: key ?? this.key,
        scopeUserId: scopeUserId ?? this.scopeUserId,
        json: json ?? this.json,
        lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      );
  CachedList copyWithCompanion(CachedListsCompanion data) {
    return CachedList(
      key: data.key.present ? data.key.value : this.key,
      scopeUserId:
          data.scopeUserId.present ? data.scopeUserId.value : this.scopeUserId,
      json: data.json.present ? data.json.value : this.json,
      lastFetchedAt: data.lastFetchedAt.present
          ? data.lastFetchedAt.value
          : this.lastFetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedList(')
          ..write('key: $key, ')
          ..write('scopeUserId: $scopeUserId, ')
          ..write('json: $json, ')
          ..write('lastFetchedAt: $lastFetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, scopeUserId, json, lastFetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedList &&
          other.key == this.key &&
          other.scopeUserId == this.scopeUserId &&
          other.json == this.json &&
          other.lastFetchedAt == this.lastFetchedAt);
}

class CachedListsCompanion extends UpdateCompanion<CachedList> {
  final Value<String> key;
  final Value<String> scopeUserId;
  final Value<String> json;
  final Value<DateTime> lastFetchedAt;
  final Value<int> rowid;
  const CachedListsCompanion({
    this.key = const Value.absent(),
    this.scopeUserId = const Value.absent(),
    this.json = const Value.absent(),
    this.lastFetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedListsCompanion.insert({
    required String key,
    required String scopeUserId,
    required String json,
    required DateTime lastFetchedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        scopeUserId = Value(scopeUserId),
        json = Value(json),
        lastFetchedAt = Value(lastFetchedAt);
  static Insertable<CachedList> custom({
    Expression<String>? key,
    Expression<String>? scopeUserId,
    Expression<String>? json,
    Expression<DateTime>? lastFetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (scopeUserId != null) 'scope_user_id': scopeUserId,
      if (json != null) 'json': json,
      if (lastFetchedAt != null) 'last_fetched_at': lastFetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedListsCompanion copyWith(
      {Value<String>? key,
      Value<String>? scopeUserId,
      Value<String>? json,
      Value<DateTime>? lastFetchedAt,
      Value<int>? rowid}) {
    return CachedListsCompanion(
      key: key ?? this.key,
      scopeUserId: scopeUserId ?? this.scopeUserId,
      json: json ?? this.json,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (scopeUserId.present) {
      map['scope_user_id'] = Variable<String>(scopeUserId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (lastFetchedAt.present) {
      map['last_fetched_at'] = Variable<DateTime>(lastFetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedListsCompanion(')
          ..write('key: $key, ')
          ..write('scopeUserId: $scopeUserId, ')
          ..write('json: $json, ')
          ..write('lastFetchedAt: $lastFetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingActionsTable extends PendingActions
    with TableInfo<$PendingActionsTable, PendingAction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _targetEndpointMeta =
      const VerificationMeta('targetEndpoint');
  @override
  late final GeneratedColumn<String> targetEndpoint = GeneratedColumn<String>(
      'target_endpoint', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _attachmentLocalPathMeta =
      const VerificationMeta('attachmentLocalPath');
  @override
  late final GeneratedColumn<String> attachmentLocalPath =
      GeneratedColumn<String>('attachment_local_path', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _uploadedAttachmentPathMeta =
      const VerificationMeta('uploadedAttachmentPath');
  @override
  late final GeneratedColumn<String> uploadedAttachmentPath =
      GeneratedColumn<String>('uploaded_attachment_path', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _attemptCountMeta =
      const VerificationMeta('attemptCount');
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
      'attempt_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>('last_attempt_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scopeUserIdMeta =
      const VerificationMeta('scopeUserId');
  @override
  late final GeneratedColumn<String> scopeUserId = GeneratedColumn<String>(
      'scope_user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _relatedCustomerIdMeta =
      const VerificationMeta('relatedCustomerId');
  @override
  late final GeneratedColumn<String> relatedCustomerId =
      GeneratedColumn<String>('related_customer_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        payloadJson,
        targetEndpoint,
        attachmentLocalPath,
        uploadedAttachmentPath,
        createdAt,
        attemptCount,
        lastAttemptAt,
        lastError,
        status,
        scopeUserId,
        relatedCustomerId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_actions';
  @override
  VerificationContext validateIntegrity(Insertable<PendingAction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('target_endpoint')) {
      context.handle(
          _targetEndpointMeta,
          targetEndpoint.isAcceptableOrUnknown(
              data['target_endpoint']!, _targetEndpointMeta));
    } else if (isInserting) {
      context.missing(_targetEndpointMeta);
    }
    if (data.containsKey('attachment_local_path')) {
      context.handle(
          _attachmentLocalPathMeta,
          attachmentLocalPath.isAcceptableOrUnknown(
              data['attachment_local_path']!, _attachmentLocalPathMeta));
    }
    if (data.containsKey('uploaded_attachment_path')) {
      context.handle(
          _uploadedAttachmentPathMeta,
          uploadedAttachmentPath.isAcceptableOrUnknown(
              data['uploaded_attachment_path']!, _uploadedAttachmentPathMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
          _attemptCountMeta,
          attemptCount.isAcceptableOrUnknown(
              data['attempt_count']!, _attemptCountMeta));
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('scope_user_id')) {
      context.handle(
          _scopeUserIdMeta,
          scopeUserId.isAcceptableOrUnknown(
              data['scope_user_id']!, _scopeUserIdMeta));
    } else if (isInserting) {
      context.missing(_scopeUserIdMeta);
    }
    if (data.containsKey('related_customer_id')) {
      context.handle(
          _relatedCustomerIdMeta,
          relatedCustomerId.isAcceptableOrUnknown(
              data['related_customer_id']!, _relatedCustomerIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingAction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingAction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      targetEndpoint: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}target_endpoint'])!,
      attachmentLocalPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}attachment_local_path']),
      uploadedAttachmentPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}uploaded_attachment_path']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      attemptCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempt_count'])!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_attempt_at']),
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      scopeUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scope_user_id'])!,
      relatedCustomerId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}related_customer_id']),
    );
  }

  @override
  $PendingActionsTable createAlias(String alias) {
    return $PendingActionsTable(attachedDatabase, alias);
  }
}

class PendingAction extends DataClass implements Insertable<PendingAction> {
  /// Client-generated UUID — doubles as the idempotency key sent to the
  /// server (see server/src/middleware/idempotency.js), so a retry after a
  /// lost response replays the original result instead of re-executing.
  final String id;
  final String type;
  final String payloadJson;
  final String targetEndpoint;
  final String? attachmentLocalPath;
  final String? uploadedAttachmentPath;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final String status;
  final String scopeUserId;
  final String? relatedCustomerId;
  const PendingAction(
      {required this.id,
      required this.type,
      required this.payloadJson,
      required this.targetEndpoint,
      this.attachmentLocalPath,
      this.uploadedAttachmentPath,
      required this.createdAt,
      required this.attemptCount,
      this.lastAttemptAt,
      this.lastError,
      required this.status,
      required this.scopeUserId,
      this.relatedCustomerId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['payload_json'] = Variable<String>(payloadJson);
    map['target_endpoint'] = Variable<String>(targetEndpoint);
    if (!nullToAbsent || attachmentLocalPath != null) {
      map['attachment_local_path'] = Variable<String>(attachmentLocalPath);
    }
    if (!nullToAbsent || uploadedAttachmentPath != null) {
      map['uploaded_attachment_path'] =
          Variable<String>(uploadedAttachmentPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['status'] = Variable<String>(status);
    map['scope_user_id'] = Variable<String>(scopeUserId);
    if (!nullToAbsent || relatedCustomerId != null) {
      map['related_customer_id'] = Variable<String>(relatedCustomerId);
    }
    return map;
  }

  PendingActionsCompanion toCompanion(bool nullToAbsent) {
    return PendingActionsCompanion(
      id: Value(id),
      type: Value(type),
      payloadJson: Value(payloadJson),
      targetEndpoint: Value(targetEndpoint),
      attachmentLocalPath: attachmentLocalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentLocalPath),
      uploadedAttachmentPath: uploadedAttachmentPath == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAttachmentPath),
      createdAt: Value(createdAt),
      attemptCount: Value(attemptCount),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      status: Value(status),
      scopeUserId: Value(scopeUserId),
      relatedCustomerId: relatedCustomerId == null && nullToAbsent
          ? const Value.absent()
          : Value(relatedCustomerId),
    );
  }

  factory PendingAction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingAction(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      targetEndpoint: serializer.fromJson<String>(json['targetEndpoint']),
      attachmentLocalPath:
          serializer.fromJson<String?>(json['attachmentLocalPath']),
      uploadedAttachmentPath:
          serializer.fromJson<String?>(json['uploadedAttachmentPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      status: serializer.fromJson<String>(json['status']),
      scopeUserId: serializer.fromJson<String>(json['scopeUserId']),
      relatedCustomerId:
          serializer.fromJson<String?>(json['relatedCustomerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'targetEndpoint': serializer.toJson<String>(targetEndpoint),
      'attachmentLocalPath': serializer.toJson<String?>(attachmentLocalPath),
      'uploadedAttachmentPath':
          serializer.toJson<String?>(uploadedAttachmentPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'status': serializer.toJson<String>(status),
      'scopeUserId': serializer.toJson<String>(scopeUserId),
      'relatedCustomerId': serializer.toJson<String?>(relatedCustomerId),
    };
  }

  PendingAction copyWith(
          {String? id,
          String? type,
          String? payloadJson,
          String? targetEndpoint,
          Value<String?> attachmentLocalPath = const Value.absent(),
          Value<String?> uploadedAttachmentPath = const Value.absent(),
          DateTime? createdAt,
          int? attemptCount,
          Value<DateTime?> lastAttemptAt = const Value.absent(),
          Value<String?> lastError = const Value.absent(),
          String? status,
          String? scopeUserId,
          Value<String?> relatedCustomerId = const Value.absent()}) =>
      PendingAction(
        id: id ?? this.id,
        type: type ?? this.type,
        payloadJson: payloadJson ?? this.payloadJson,
        targetEndpoint: targetEndpoint ?? this.targetEndpoint,
        attachmentLocalPath: attachmentLocalPath.present
            ? attachmentLocalPath.value
            : this.attachmentLocalPath,
        uploadedAttachmentPath: uploadedAttachmentPath.present
            ? uploadedAttachmentPath.value
            : this.uploadedAttachmentPath,
        createdAt: createdAt ?? this.createdAt,
        attemptCount: attemptCount ?? this.attemptCount,
        lastAttemptAt:
            lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,
        lastError: lastError.present ? lastError.value : this.lastError,
        status: status ?? this.status,
        scopeUserId: scopeUserId ?? this.scopeUserId,
        relatedCustomerId: relatedCustomerId.present
            ? relatedCustomerId.value
            : this.relatedCustomerId,
      );
  PendingAction copyWithCompanion(PendingActionsCompanion data) {
    return PendingAction(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      targetEndpoint: data.targetEndpoint.present
          ? data.targetEndpoint.value
          : this.targetEndpoint,
      attachmentLocalPath: data.attachmentLocalPath.present
          ? data.attachmentLocalPath.value
          : this.attachmentLocalPath,
      uploadedAttachmentPath: data.uploadedAttachmentPath.present
          ? data.uploadedAttachmentPath.value
          : this.uploadedAttachmentPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      status: data.status.present ? data.status.value : this.status,
      scopeUserId:
          data.scopeUserId.present ? data.scopeUserId.value : this.scopeUserId,
      relatedCustomerId: data.relatedCustomerId.present
          ? data.relatedCustomerId.value
          : this.relatedCustomerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingAction(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('targetEndpoint: $targetEndpoint, ')
          ..write('attachmentLocalPath: $attachmentLocalPath, ')
          ..write('uploadedAttachmentPath: $uploadedAttachmentPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('status: $status, ')
          ..write('scopeUserId: $scopeUserId, ')
          ..write('relatedCustomerId: $relatedCustomerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      type,
      payloadJson,
      targetEndpoint,
      attachmentLocalPath,
      uploadedAttachmentPath,
      createdAt,
      attemptCount,
      lastAttemptAt,
      lastError,
      status,
      scopeUserId,
      relatedCustomerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingAction &&
          other.id == this.id &&
          other.type == this.type &&
          other.payloadJson == this.payloadJson &&
          other.targetEndpoint == this.targetEndpoint &&
          other.attachmentLocalPath == this.attachmentLocalPath &&
          other.uploadedAttachmentPath == this.uploadedAttachmentPath &&
          other.createdAt == this.createdAt &&
          other.attemptCount == this.attemptCount &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError &&
          other.status == this.status &&
          other.scopeUserId == this.scopeUserId &&
          other.relatedCustomerId == this.relatedCustomerId);
}

class PendingActionsCompanion extends UpdateCompanion<PendingAction> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> payloadJson;
  final Value<String> targetEndpoint;
  final Value<String?> attachmentLocalPath;
  final Value<String?> uploadedAttachmentPath;
  final Value<DateTime> createdAt;
  final Value<int> attemptCount;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastError;
  final Value<String> status;
  final Value<String> scopeUserId;
  final Value<String?> relatedCustomerId;
  final Value<int> rowid;
  const PendingActionsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.targetEndpoint = const Value.absent(),
    this.attachmentLocalPath = const Value.absent(),
    this.uploadedAttachmentPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.status = const Value.absent(),
    this.scopeUserId = const Value.absent(),
    this.relatedCustomerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingActionsCompanion.insert({
    required String id,
    required String type,
    required String payloadJson,
    required String targetEndpoint,
    this.attachmentLocalPath = const Value.absent(),
    this.uploadedAttachmentPath = const Value.absent(),
    required DateTime createdAt,
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    required String status,
    required String scopeUserId,
    this.relatedCustomerId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        payloadJson = Value(payloadJson),
        targetEndpoint = Value(targetEndpoint),
        createdAt = Value(createdAt),
        status = Value(status),
        scopeUserId = Value(scopeUserId);
  static Insertable<PendingAction> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? payloadJson,
    Expression<String>? targetEndpoint,
    Expression<String>? attachmentLocalPath,
    Expression<String>? uploadedAttachmentPath,
    Expression<DateTime>? createdAt,
    Expression<int>? attemptCount,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastError,
    Expression<String>? status,
    Expression<String>? scopeUserId,
    Expression<String>? relatedCustomerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (targetEndpoint != null) 'target_endpoint': targetEndpoint,
      if (attachmentLocalPath != null)
        'attachment_local_path': attachmentLocalPath,
      if (uploadedAttachmentPath != null)
        'uploaded_attachment_path': uploadedAttachmentPath,
      if (createdAt != null) 'created_at': createdAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (status != null) 'status': status,
      if (scopeUserId != null) 'scope_user_id': scopeUserId,
      if (relatedCustomerId != null) 'related_customer_id': relatedCustomerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingActionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String>? payloadJson,
      Value<String>? targetEndpoint,
      Value<String?>? attachmentLocalPath,
      Value<String?>? uploadedAttachmentPath,
      Value<DateTime>? createdAt,
      Value<int>? attemptCount,
      Value<DateTime?>? lastAttemptAt,
      Value<String?>? lastError,
      Value<String>? status,
      Value<String>? scopeUserId,
      Value<String?>? relatedCustomerId,
      Value<int>? rowid}) {
    return PendingActionsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      targetEndpoint: targetEndpoint ?? this.targetEndpoint,
      attachmentLocalPath: attachmentLocalPath ?? this.attachmentLocalPath,
      uploadedAttachmentPath:
          uploadedAttachmentPath ?? this.uploadedAttachmentPath,
      createdAt: createdAt ?? this.createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      status: status ?? this.status,
      scopeUserId: scopeUserId ?? this.scopeUserId,
      relatedCustomerId: relatedCustomerId ?? this.relatedCustomerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (targetEndpoint.present) {
      map['target_endpoint'] = Variable<String>(targetEndpoint.value);
    }
    if (attachmentLocalPath.present) {
      map['attachment_local_path'] =
          Variable<String>(attachmentLocalPath.value);
    }
    if (uploadedAttachmentPath.present) {
      map['uploaded_attachment_path'] =
          Variable<String>(uploadedAttachmentPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (scopeUserId.present) {
      map['scope_user_id'] = Variable<String>(scopeUserId.value);
    }
    if (relatedCustomerId.present) {
      map['related_customer_id'] = Variable<String>(relatedCustomerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingActionsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('targetEndpoint: $targetEndpoint, ')
          ..write('attachmentLocalPath: $attachmentLocalPath, ')
          ..write('uploadedAttachmentPath: $uploadedAttachmentPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('status: $status, ')
          ..write('scopeUserId: $scopeUserId, ')
          ..write('relatedCustomerId: $relatedCustomerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $CachedListsTable cachedLists = $CachedListsTable(this);
  late final $PendingActionsTable pendingActions = $PendingActionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedLists, pendingActions];
}

typedef $$CachedListsTableCreateCompanionBuilder = CachedListsCompanion
    Function({
  required String key,
  required String scopeUserId,
  required String json,
  required DateTime lastFetchedAt,
  Value<int> rowid,
});
typedef $$CachedListsTableUpdateCompanionBuilder = CachedListsCompanion
    Function({
  Value<String> key,
  Value<String> scopeUserId,
  Value<String> json,
  Value<DateTime> lastFetchedAt,
  Value<int> rowid,
});

class $$CachedListsTableFilterComposer
    extends Composer<_$LocalDb, $CachedListsTable> {
  $$CachedListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scopeUserId => $composableBuilder(
      column: $table.scopeUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastFetchedAt => $composableBuilder(
      column: $table.lastFetchedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedListsTableOrderingComposer
    extends Composer<_$LocalDb, $CachedListsTable> {
  $$CachedListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scopeUserId => $composableBuilder(
      column: $table.scopeUserId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastFetchedAt => $composableBuilder(
      column: $table.lastFetchedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$CachedListsTableAnnotationComposer
    extends Composer<_$LocalDb, $CachedListsTable> {
  $$CachedListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get scopeUserId => $composableBuilder(
      column: $table.scopeUserId, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get lastFetchedAt => $composableBuilder(
      column: $table.lastFetchedAt, builder: (column) => column);
}

class $$CachedListsTableTableManager extends RootTableManager<
    _$LocalDb,
    $CachedListsTable,
    CachedList,
    $$CachedListsTableFilterComposer,
    $$CachedListsTableOrderingComposer,
    $$CachedListsTableAnnotationComposer,
    $$CachedListsTableCreateCompanionBuilder,
    $$CachedListsTableUpdateCompanionBuilder,
    (CachedList, BaseReferences<_$LocalDb, $CachedListsTable, CachedList>),
    CachedList,
    PrefetchHooks Function()> {
  $$CachedListsTableTableManager(_$LocalDb db, $CachedListsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> scopeUserId = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<DateTime> lastFetchedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedListsCompanion(
            key: key,
            scopeUserId: scopeUserId,
            json: json,
            lastFetchedAt: lastFetchedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String scopeUserId,
            required String json,
            required DateTime lastFetchedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedListsCompanion.insert(
            key: key,
            scopeUserId: scopeUserId,
            json: json,
            lastFetchedAt: lastFetchedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedListsTableProcessedTableManager = ProcessedTableManager<
    _$LocalDb,
    $CachedListsTable,
    CachedList,
    $$CachedListsTableFilterComposer,
    $$CachedListsTableOrderingComposer,
    $$CachedListsTableAnnotationComposer,
    $$CachedListsTableCreateCompanionBuilder,
    $$CachedListsTableUpdateCompanionBuilder,
    (CachedList, BaseReferences<_$LocalDb, $CachedListsTable, CachedList>),
    CachedList,
    PrefetchHooks Function()>;
typedef $$PendingActionsTableCreateCompanionBuilder = PendingActionsCompanion
    Function({
  required String id,
  required String type,
  required String payloadJson,
  required String targetEndpoint,
  Value<String?> attachmentLocalPath,
  Value<String?> uploadedAttachmentPath,
  required DateTime createdAt,
  Value<int> attemptCount,
  Value<DateTime?> lastAttemptAt,
  Value<String?> lastError,
  required String status,
  required String scopeUserId,
  Value<String?> relatedCustomerId,
  Value<int> rowid,
});
typedef $$PendingActionsTableUpdateCompanionBuilder = PendingActionsCompanion
    Function({
  Value<String> id,
  Value<String> type,
  Value<String> payloadJson,
  Value<String> targetEndpoint,
  Value<String?> attachmentLocalPath,
  Value<String?> uploadedAttachmentPath,
  Value<DateTime> createdAt,
  Value<int> attemptCount,
  Value<DateTime?> lastAttemptAt,
  Value<String?> lastError,
  Value<String> status,
  Value<String> scopeUserId,
  Value<String?> relatedCustomerId,
  Value<int> rowid,
});

class $$PendingActionsTableFilterComposer
    extends Composer<_$LocalDb, $PendingActionsTable> {
  $$PendingActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get targetEndpoint => $composableBuilder(
      column: $table.targetEndpoint,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get attachmentLocalPath => $composableBuilder(
      column: $table.attachmentLocalPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uploadedAttachmentPath => $composableBuilder(
      column: $table.uploadedAttachmentPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scopeUserId => $composableBuilder(
      column: $table.scopeUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get relatedCustomerId => $composableBuilder(
      column: $table.relatedCustomerId,
      builder: (column) => ColumnFilters(column));
}

class $$PendingActionsTableOrderingComposer
    extends Composer<_$LocalDb, $PendingActionsTable> {
  $$PendingActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get targetEndpoint => $composableBuilder(
      column: $table.targetEndpoint,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get attachmentLocalPath => $composableBuilder(
      column: $table.attachmentLocalPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uploadedAttachmentPath => $composableBuilder(
      column: $table.uploadedAttachmentPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scopeUserId => $composableBuilder(
      column: $table.scopeUserId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get relatedCustomerId => $composableBuilder(
      column: $table.relatedCustomerId,
      builder: (column) => ColumnOrderings(column));
}

class $$PendingActionsTableAnnotationComposer
    extends Composer<_$LocalDb, $PendingActionsTable> {
  $$PendingActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<String> get targetEndpoint => $composableBuilder(
      column: $table.targetEndpoint, builder: (column) => column);

  GeneratedColumn<String> get attachmentLocalPath => $composableBuilder(
      column: $table.attachmentLocalPath, builder: (column) => column);

  GeneratedColumn<String> get uploadedAttachmentPath => $composableBuilder(
      column: $table.uploadedAttachmentPath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get scopeUserId => $composableBuilder(
      column: $table.scopeUserId, builder: (column) => column);

  GeneratedColumn<String> get relatedCustomerId => $composableBuilder(
      column: $table.relatedCustomerId, builder: (column) => column);
}

class $$PendingActionsTableTableManager extends RootTableManager<
    _$LocalDb,
    $PendingActionsTable,
    PendingAction,
    $$PendingActionsTableFilterComposer,
    $$PendingActionsTableOrderingComposer,
    $$PendingActionsTableAnnotationComposer,
    $$PendingActionsTableCreateCompanionBuilder,
    $$PendingActionsTableUpdateCompanionBuilder,
    (
      PendingAction,
      BaseReferences<_$LocalDb, $PendingActionsTable, PendingAction>
    ),
    PendingAction,
    PrefetchHooks Function()> {
  $$PendingActionsTableTableManager(_$LocalDb db, $PendingActionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<String> targetEndpoint = const Value.absent(),
            Value<String?> attachmentLocalPath = const Value.absent(),
            Value<String?> uploadedAttachmentPath = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<DateTime?> lastAttemptAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> scopeUserId = const Value.absent(),
            Value<String?> relatedCustomerId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingActionsCompanion(
            id: id,
            type: type,
            payloadJson: payloadJson,
            targetEndpoint: targetEndpoint,
            attachmentLocalPath: attachmentLocalPath,
            uploadedAttachmentPath: uploadedAttachmentPath,
            createdAt: createdAt,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            status: status,
            scopeUserId: scopeUserId,
            relatedCustomerId: relatedCustomerId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            required String payloadJson,
            required String targetEndpoint,
            Value<String?> attachmentLocalPath = const Value.absent(),
            Value<String?> uploadedAttachmentPath = const Value.absent(),
            required DateTime createdAt,
            Value<int> attemptCount = const Value.absent(),
            Value<DateTime?> lastAttemptAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            required String status,
            required String scopeUserId,
            Value<String?> relatedCustomerId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingActionsCompanion.insert(
            id: id,
            type: type,
            payloadJson: payloadJson,
            targetEndpoint: targetEndpoint,
            attachmentLocalPath: attachmentLocalPath,
            uploadedAttachmentPath: uploadedAttachmentPath,
            createdAt: createdAt,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            status: status,
            scopeUserId: scopeUserId,
            relatedCustomerId: relatedCustomerId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingActionsTableProcessedTableManager = ProcessedTableManager<
    _$LocalDb,
    $PendingActionsTable,
    PendingAction,
    $$PendingActionsTableFilterComposer,
    $$PendingActionsTableOrderingComposer,
    $$PendingActionsTableAnnotationComposer,
    $$PendingActionsTableCreateCompanionBuilder,
    $$PendingActionsTableUpdateCompanionBuilder,
    (
      PendingAction,
      BaseReferences<_$LocalDb, $PendingActionsTable, PendingAction>
    ),
    PendingAction,
    PrefetchHooks Function()>;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$CachedListsTableTableManager get cachedLists =>
      $$CachedListsTableTableManager(_db, _db.cachedLists);
  $$PendingActionsTableTableManager get pendingActions =>
      $$PendingActionsTableTableManager(_db, _db.pendingActions);
}
