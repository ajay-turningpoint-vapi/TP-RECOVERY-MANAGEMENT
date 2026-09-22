import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:salesman_mobile/services/api_client.dart';
import 'package:salesman_mobile/services/attachment_staging.dart';
import 'package:salesman_mobile/services/local_db.dart';
import 'package:salesman_mobile/services/pending_action.dart';

/// Thrown by [PendingActionQueue.enqueue] when the same customer already
/// has an unsynced action in the queue — see the class doc for why a
/// second one is refused rather than stacked.
class PendingActionBlockedException implements Exception {
  final String message;
  PendingActionBlockedException(this.message);
  @override
  String toString() => message;
}

/// The offline write queue's enqueue/flush engine. A network-shaped
/// [ApiException] (statusCode 0) from any `AppStore` write method lands
/// here instead of failing outright: the action is persisted (see
/// local_db.dart's `PendingActions` table) and replayed automatically once
/// connectivity returns, via [flush] — triggered by AppStore on every SSE
/// reconnect, app resume, and a periodic backstop timer while the queue is
/// non-empty.
///
/// Deliberately simple for v1: actions flush strictly in the order they
/// were queued, one at a time (never in parallel), and a customer can only
/// ever have ONE unsynced action at a time — see [enqueue]. There is no
/// cross-action dependency tracking; each queued action is independent.
class PendingActionQueue {
  PendingActionQueue(this._localDb, this._apiClient);

  final LocalDb _localDb;
  final ApiClient _apiClient;
  static const _uuid = Uuid();

  bool _flushing = false;

  /// True if [customerId] already has an action queued/in-flight for
  /// [scopeUserId] — the UI uses this to proactively disable a second
  /// action's button, rather than only finding out after a tap.
  Future<bool> hasOpenActionForCustomer(String scopeUserId, String customerId) =>
      _localDb.hasOpenActionForCustomer(scopeUserId, customerId);

  /// Queues one write action for later. [attachmentBytes]/[attachmentContentType],
  /// when present, are staged to durable local storage immediately (see
  /// AttachmentStaging) — the caller's in-memory bytes (e.g. an XFile
  /// that came from a dialog about to close) don't need to survive past
  /// this call.
  ///
  /// Throws [PendingActionBlockedException] if [relatedCustomerId] already
  /// has an unsynced action — callers should catch this and surface it as
  /// a "please wait for it to sync" message, not enqueue a second one.
  Future<String> enqueue({
    required PendingActionType type,
    required String targetEndpoint,
    required Map<String, dynamic> payload,
    required String scopeUserId,
    String? relatedCustomerId,
    List<int>? attachmentBytes,
    String? attachmentContentType,
  }) async {
    if (relatedCustomerId != null && await hasOpenActionForCustomer(scopeUserId, relatedCustomerId)) {
      throw PendingActionBlockedException(
          'This customer has an unsynced change pending — please wait for it to sync before recording another action.');
    }

    final id = _uuid.v4();
    String? attachmentLocalPath;
    if (attachmentBytes != null && attachmentContentType != null) {
      attachmentLocalPath = await AttachmentStaging.stage(id, attachmentBytes, contentType: attachmentContentType);
    }

    await _localDb.insertPendingAction(PendingActionsCompanion.insert(
      id: id,
      type: type.name,
      payloadJson: jsonEncode(payload),
      targetEndpoint: targetEndpoint,
      attachmentLocalPath: Value(attachmentLocalPath),
      createdAt: DateTime.now(),
      status: PendingActionStatus.pending.name,
      scopeUserId: scopeUserId,
      relatedCustomerId: Value(relatedCustomerId),
    ));
    return id;
  }

  /// Processes every pending/failedRetryable action for [scopeUserId], in
  /// queued order, one at a time. Stops at the first network-shaped
  /// failure (no point hammering an unreachable server — the next trigger
  /// tries again); a real rejection on one item doesn't block the rest.
  /// Safe to call repeatedly — overlapping calls coalesce.
  Future<void> flush(String scopeUserId) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final items = await _localDb.flushablePendingActions(scopeUserId);
      for (final item in items) {
        final keepGoing = await _flushOne(item);
        if (!keepGoing) break;
      }
    } finally {
      _flushing = false;
    }
  }

  /// Returns false if the caller should stop flushing (server unreachable);
  /// true to continue to the next queued item.
  Future<bool> _flushOne(PendingAction item) async {
    await _localDb.updatePendingAction(
      item.id,
      PendingActionsCompanion(
        status: Value(PendingActionStatus.inFlight.name),
        attemptCount: Value(item.attemptCount + 1),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );

    try {
      var payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;

      // Two-step actions (an attachment to upload first) resume at
      // whichever half didn't complete on a prior attempt.
      var uploadedPath = item.uploadedAttachmentPath;
      if (item.attachmentLocalPath != null && uploadedPath == null) {
        final bytes = await AttachmentStaging.read(item.attachmentLocalPath!);
        final contentType = item.attachmentLocalPath!.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'image/jpeg';
        uploadedPath = await _apiClient.uploadAttachment(bytes, filename: p.basename(item.attachmentLocalPath!), contentType: contentType);
        await _localDb.updatePendingAction(item.id, PendingActionsCompanion(uploadedAttachmentPath: Value(uploadedPath)));
      }
      if (uploadedPath != null) {
        payload = {...payload, 'attachmentPath': uploadedPath};
      }

      await _apiClient.postRaw(item.targetEndpoint, payload, idempotencyKey: item.id);

      if (item.attachmentLocalPath != null) {
        unawaited(AttachmentStaging.delete(item.attachmentLocalPath!));
      }
      await _localDb.deletePendingAction(item.id);
      return true;
    } on ApiException catch (e) {
      final retryable = e.statusCode == 0;
      await _localDb.updatePendingAction(
        item.id,
        PendingActionsCompanion(
          status: Value((retryable ? PendingActionStatus.failedRetryable : PendingActionStatus.failedTerminal).name),
          lastError: Value(e.message),
        ),
      );
      return !retryable;
    } catch (e) {
      await _localDb.updatePendingAction(
        item.id,
        PendingActionsCompanion(status: Value(PendingActionStatus.failedRetryable.name), lastError: Value(e.toString())),
      );
      return false;
    }
  }

  /// Re-queues a `failedTerminal` item (the user chose "Retry" on the
  /// Pending Sync screen after fixing whatever it was rejected for) and
  /// flushes immediately.
  Future<void> retryNow(String actionId, String scopeUserId) async {
    await _localDb.updatePendingAction(actionId, PendingActionsCompanion(status: Value(PendingActionStatus.pending.name)));
    await flush(scopeUserId);
  }

  /// Discards a queued action the user chose not to retry — deletes it and
  /// any staged attachment. Irreversible.
  Future<void> discard(String actionId) async {
    final item = await _localDb.findPendingAction(actionId);
    if (item?.attachmentLocalPath != null) {
      unawaited(AttachmentStaging.delete(item!.attachmentLocalPath!));
    }
    await _localDb.deletePendingAction(actionId);
  }
}
