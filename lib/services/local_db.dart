import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_db.g.dart';

/// One row per (list key, logged-in user) — the last-known-good snapshot of
/// a whole API list/object response, as raw JSON text. Reuses the existing
/// `fromJson` factories on read instead of hand-mapping columns, so this
/// table never needs a schema change when a model gains a field.
///
/// `key` is one of: customers, tasks, ptps, disputes, paymentClaims,
/// escalations, salesmen, notifications, dashboardReport, trends, identity
/// ('identity' holds the last successful `getMe()` response — see
/// AppStore.restoreSession's offline fallback).
class CachedLists extends Table {
  TextColumn get key => text()();
  TextColumn get scopeUserId => text()();
  TextColumn get json => text()();
  DateTimeColumn get lastFetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key, scopeUserId};
}

/// The offline write queue — one row per action a salesperson/RE took that
/// failed on a network error and is waiting to sync. See
/// lib/services/pending_action_queue.dart for the enqueue/flush engine;
/// this table is just the durable store, so a queued action survives an
/// app restart before it ever gets a chance to flush.
class PendingActions extends Table {
  /// Client-generated UUID — doubles as the idempotency key sent to the
  /// server (see server/src/middleware/idempotency.js), so a retry after a
  /// lost response replays the original result instead of re-executing.
  TextColumn get id => text()();
  TextColumn get type => text()(); // PendingActionType.name
  TextColumn get payloadJson => text()();
  TextColumn get targetEndpoint => text()();
  // Set when this action carries a screenshot/PDF (e.g. recordOutcome) —
  // the file is copied here from the picker's own (unstable) path so it
  // survives the originating dialog closing. Null for actions with no
  // attachment.
  TextColumn get attachmentLocalPath => text().nullable()();
  // Set once the attachment half of a two-step action succeeds, so a retry
  // after the SECOND half fails doesn't re-upload the file.
  TextColumn get uploadedAttachmentPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get status => text()(); // PendingActionStatus.name
  TextColumn get scopeUserId => text()();
  // Drives the same-customer-already-pending guard and the per-row "Sync
  // pending" chip — null for an action with no single owning customer.
  TextColumn get relatedCustomerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [CachedLists, PendingActions])
class LocalDb extends _$LocalDb {
  LocalDb() : super(_openConnection());
  LocalDb.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(pendingActions);
        },
      );

  /// Overwrites one list's cached snapshot for [scopeUserId] — called after
  /// every successful individual list refresh (see AppStore's
  /// `_refreshXFromApi` methods), not just a full clean sweep, so a partial
  /// refresh still improves the cache for whatever succeeded.
  Future<void> putList(String key, String scopeUserId, Object? data) async {
    await into(cachedLists).insertOnConflictUpdate(CachedListsCompanion.insert(
      key: key,
      scopeUserId: scopeUserId,
      json: jsonEncode(data),
      lastFetchedAt: DateTime.now(),
    ));
  }

  /// The cached JSON for one list, decoded — null if nothing's cached yet
  /// for this user.
  Future<Object?> getList(String key, String scopeUserId) async {
    final row = await (select(cachedLists)
          ..where((t) => t.key.equals(key) & t.scopeUserId.equals(scopeUserId)))
        .getSingleOrNull();
    if (row == null) return null;
    return jsonDecode(row.json);
  }

  /// The oldest `lastFetchedAt` across every list cached for this user —
  /// used as the single "data as of" staleness timestamp shown to the user.
  /// Null if nothing is cached yet.
  Future<DateTime?> oldestFetchedAt(String scopeUserId) async {
    final rows = await (select(cachedLists)..where((t) => t.scopeUserId.equals(scopeUserId))).get();
    if (rows.isEmpty) return null;
    return rows.map((r) => r.lastFetchedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// True if this user has ANY cached data at all — distinguishes "cache
  /// exists but is stale" from "genuinely never synced on this device"
  /// (the one case offline-first can't help).
  Future<bool> hasAnyCache(String scopeUserId) async {
    final row = await (select(cachedLists)..where((t) => t.scopeUserId.equals(scopeUserId))..limit(1)).getSingleOrNull();
    return row != null;
  }

  /// Wipes every cached list for [scopeUserId] — called when a different
  /// user logs in on the same device, so one salesperson's portfolio can
  /// never flash on-screen for another (see AppStore's login flow).
  Future<void> clearFor(String scopeUserId) async {
    await (delete(cachedLists)..where((t) => t.scopeUserId.equals(scopeUserId))).go();
  }

  // ── Pending action queue ──────────────────────────────────────────────

  Future<void> insertPendingAction(PendingActionsCompanion row) => into(pendingActions).insert(row);

  /// Queued/retryable rows for this user, oldest first — what `flush()`
  /// processes, strictly in this order, one at a time.
  Future<List<PendingAction>> flushablePendingActions(String scopeUserId) {
    return (select(pendingActions)
          ..where((t) => t.scopeUserId.equals(scopeUserId) & t.status.isIn(const ['pending', 'failedRetryable']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Every row still in play (not yet synced) for a user — drives
  /// [AppStore.pendingActionCount] and the Pending Sync screen. Includes
  /// `failedTerminal` ones, since those still need the user's attention
  /// (discard/retry), unlike a fully `synced` row which is just deleted.
  Stream<List<PendingAction>> watchOpenPendingActions(String scopeUserId) {
    return (select(pendingActions)
          ..where((t) => t.scopeUserId.equals(scopeUserId) & t.status.isNotValue('synced'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<bool> hasOpenActionForCustomer(String scopeUserId, String customerId) async {
    final row = await (select(pendingActions)
          ..where((t) =>
              t.scopeUserId.equals(scopeUserId) &
              t.relatedCustomerId.equals(customerId) &
              t.status.isNotValue('synced') &
              t.status.isNotValue('failedTerminal'))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> updatePendingAction(String id, PendingActionsCompanion update) =>
      (this.update(pendingActions)..where((t) => t.id.equals(id))).write(update);

  Future<void> deletePendingAction(String id) => (delete(pendingActions)..where((t) => t.id.equals(id))).go();

  Future<PendingAction?> findPendingAction(String id) =>
      (select(pendingActions)..where((t) => t.id.equals(id))).getSingleOrNull();
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'tprms_cache.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
