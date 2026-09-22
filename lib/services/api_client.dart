import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown for any non-2xx response from the TP-RMS API. Carries the
/// server's own error message (from its centralized `{error:{message}}`
/// shape) instead of a generic "request failed" — see
/// server/src/middleware/errorHandler.js. Also used (with statusCode 0)
/// for client-side failures — timeouts, unreachable server — so every
/// caller has exactly one exception type to catch.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException({required this.statusCode, required this.message, this.code});

  @override
  String toString() => message;
}

/// Thin HTTP client for the TP-RMS Express/MariaDB backend
/// (see server/README.md).
///
/// Session model: a short-lived (1h) access token authenticates every
/// request; a long-lived (30 day), single-use, server-revocable refresh
/// token silently exchanges for a new pair whenever the access token has
/// expired (see server/src/services/authService.js). This is what lets the
/// app stay logged in for weeks without the user ever seeing a login
/// screen mid-session — the 401-triggered refresh below is invisible to
/// every screen that calls into this client. Both tokens live in
/// [FlutterSecureStorage] (Android Keystore-backed), which — unlike the
/// plain SharedPreferences this used to use — is excluded from Android
/// Auto Backup, so an uninstall+reinstall can never silently restore a
/// logged-in session.
class ApiClient {
  // Public IP (router port-forward -> this Mac's nginx on :80, see
  // /opt/homebrew/etc/nginx/servers/tprms.conf), so the app works over
  // mobile data too, not just when a device is on the same LAN.
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? 'http://43.255.141.110';

  final String baseUrl;
  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'tp_rms_access_token';
  static const _refreshTokenKey = 'tp_rms_refresh_token';
  static const _identityKey = 'tp_rms_last_identity';
  static const _requestTimeout = Duration(seconds: 20);

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;

  /// Set by AppStore. Fired when the session can no longer be salvaged —
  /// the refresh token itself was rejected (expired, revoked, or reused) —
  /// so the UI can drop back to the login screen from wherever it happens
  /// to be, not just from a screen that catches the resulting ApiException.
  void Function()? onSessionExpired;

  /// Set by AppStore. Fired the instant ANY request comes back rejected
  /// with the manager-only maintenance kill switch (see server's
  /// middleware/auth.js) — not just the SSE 'maintenance' push, which can
  /// miss a client whose stream happens to be reconnecting at that exact
  /// moment. Between the two, every screen's next real request is a second,
  /// reliable way to notice the block, not just the real-time one.
  void Function()? onMaintenanceMode;

  Future<void> loadPersistedSession() async {
    _accessToken = await _storage.read(key: _accessTokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);
  }

  bool get isAuthenticated => _accessToken != null && _refreshToken != null;

  /// The last successfully-fetched `getMe()`/`login()` identity (role/id/
  /// username/fullName), persisted so a cold start that fails on a pure
  /// network error (not a real auth rejection) can still route the UI —
  /// see AppStore.restoreSession's offline fallback, which needs a role/id
  /// to show cached data with even though this session never reached the
  /// server. Cleared together with the tokens on an actual logout.
  Future<void> saveIdentitySnapshot(Map<String, dynamic> user) =>
      _storage.write(key: _identityKey, value: jsonEncode(user));

  Future<Map<String, dynamic>?> getLastIdentitySnapshot() async {
    final raw = await _storage.read(key: _identityKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSession(String? accessToken, String? refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (accessToken == null) {
      await _storage.delete(key: _accessTokenKey);
    } else {
      await _storage.write(key: _accessTokenKey, value: accessToken);
    }
    if (refreshToken == null) {
      await _storage.delete(key: _refreshTokenKey);
    } else {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Map<String, String> _headers([Map<String, String>? extra]) => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        if (extra != null) ...extra,
      };

  Future<dynamic> _handle(http.Response res) async {
    final isJson = res.headers['content-type']?.contains('application/json') ?? false;
    final body = isJson && res.body.isNotEmpty ? jsonDecode(res.body) : null;

    if (res.statusCode >= 200 && res.statusCode < 300) return body;

    final error = body is Map ? body['error'] as Map<String, dynamic>? : null;
    final code = error?['code'] as String?;
    if (code == 'MAINTENANCE_MODE') onMaintenanceMode?.call();
    throw ApiException(
      statusCode: res.statusCode,
      message: error?['message'] as String? ?? 'Request failed (${res.statusCode})',
      code: code,
    );
  }

  /// Bare HTTP call with a timeout and friendly translation of network
  /// failures — every caller downstream only ever has to catch
  /// [ApiException], never a raw [SocketException]/[TimeoutException].
  Future<http.Response> _rawSend(String method, String path, [Map<String, dynamic>? body, Map<String, String>? extraHeaders]) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final future = method == 'GET'
          ? http.get(uri, headers: _headers(extraHeaders))
          : http.post(uri, headers: _headers(extraHeaders), body: body != null ? jsonEncode(body) : null);
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(statusCode: 0, message: 'The server is taking too long to respond. Please try again.');
    } on SocketException {
      throw ApiException(statusCode: 0, message: 'Could not reach the server. Please check your connection and try again.');
    } on http.ClientException {
      throw ApiException(statusCode: 0, message: 'Could not reach the server. Please check your connection and try again.');
    } on FormatException {
      throw ApiException(statusCode: 0, message: 'Received an unexpected response from the server. Please try again.');
    }
  }

  /// Sends an authenticated request; on a 401 (an expired or otherwise
  /// rejected access token) it transparently refreshes once and retries
  /// before giving up. This — not just issuing a refresh token in the
  /// first place — is the actual mechanism behind "no need to log in all
  /// the time": every screen just calls `_get`/`_post` as before and never
  /// has to know the access token silently rotated mid-request.
  Future<dynamic> _authedSend(String method, String path, [Map<String, dynamic>? body, Map<String, String>? extraHeaders]) async {
    var res = await _rawSend(method, path, body, extraHeaders);
    if (res.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        res = await _rawSend(method, path, body, extraHeaders);
      }
    }
    return _handle(res);
  }

  /// Single-flight refresh: several screens legitimately fire off parallel
  /// requests (e.g. the post-login `_refreshAllFromApi` burst), so several
  /// of them can hit a 401 for the same expired access token at once. Only
  /// the first caller actually spends the (single-use) refresh token; every
  /// concurrent caller awaits that same in-flight attempt instead of racing
  /// to redeem it and knocking each other's rotation out from under them.
  Future<bool> _tryRefresh() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final currentRefreshToken = _refreshToken;
    if (currentRefreshToken == null) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': currentRefreshToken}),
          )
          .timeout(_requestTimeout);

      if (res.statusCode != 200) {
        // The refresh token itself was rejected (expired / revoked /
        // already used) — there's no recovering this session client-side.
        await _persistSession(null, null);
        onSessionExpired?.call();
        return false;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await _persistSession(body['accessToken'] as String, body['refreshToken'] as String);
      return true;
    } catch (_) {
      // A network blip during the refresh attempt itself — don't destroy a
      // still-valid session over it. The retried original request will
      // fail with its own friendly network-error message, and the refresh
      // token (untouched) remains available to try again next time.
      return false;
    }
  }

  Future<dynamic> _get(String path) => _authedSend('GET', path);
  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) => _authedSend('POST', path, body);

  /// Generic authenticated POST to any endpoint — used by
  /// [PendingActionQueue] to flush a queued offline write without needing
  /// a dedicated typed method per action type (the queue already knows the
  /// right path/body at enqueue time, since it's built from the same call
  /// the live path would have made). [idempotencyKey] is sent as
  /// `X-Idempotency-Key` (see server/src/middleware/idempotency.js) so a
  /// retry after a lost response replays the original result instead of
  /// re-executing the mutation.
  Future<dynamic> postRaw(String path, Map<String, dynamic> body, {required String idempotencyKey}) =>
      _authedSend('POST', path, body, {'X-Idempotency-Key': idempotencyKey});

  /// Force a token refresh, reusing the same single-flight guard the 401
  /// retry path uses. The realtime SSE stream calls this when the server
  /// closes it with a 401 (its long-lived connection outlives the 1h
  /// access token). Returns true if a fresh token is now in place.
  Future<bool> ensureFreshToken() => _tryRefresh();

  /// Auth headers for a long-lived SSE GET to `$baseUrl/api/events`.
  Map<String, String> get eventStreamHeaders => {
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      };

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _rawSend('POST', '/api/auth/login', {'username': username, 'password': password});
    final body = await _handle(res) as Map<String, dynamic>;
    await _persistSession(body['accessToken'] as String, body['refreshToken'] as String);
    final user = body['user'] as Map<String, dynamic>;
    unawaited(saveIdentitySnapshot(user));
    return user;
  }

  Future<Map<String, dynamic>> getMe() async {
    final user = await _get('/api/auth/me') as Map<String, dynamic>;
    unawaited(saveIdentitySnapshot(user));
    return user;
  }

  /// The admin-only kill switch's current state — `{enabled, since}`.
  /// Deliberately callable with no session at all (the login screen needs
  /// this before anyone's signed in); `_get` sends whatever token exists,
  /// but the server route itself never requires one for this one.
  Future<Map<String, dynamic>> getMaintenanceStatus() async =>
      await _get('/api/maintenance') as Map<String, dynamic>;

  /// Flips the kill switch. Server-enforced ADMIN-only — see
  /// server/src/routes/maintenanceRoutes.js. While on, every other role
  /// (including MANAGEMENT) is signed out on its next request.
  Future<Map<String, dynamic>> setMaintenanceMode(bool enabled) async =>
      await _post('/api/maintenance', {'enabled': enabled}) as Map<String, dynamic>;

  // ---------------------------------------------------------------------
  // ADMIN-only (see server/src/routes/busySyncAdminRoutes.js /
  // adminRoutes.js) — BUSY sync health/trigger and salesperson password
  // resets. Server-enforced; these calls 403 for any other role.
  // ---------------------------------------------------------------------

  /// Per-branch BUSY sync health: running state, last run per branch,
  /// total customer count, MSSQL/MariaDB connectivity.
  Future<Map<String, dynamic>> getBusySyncHealth() async =>
      await _get('/api/busy-sync/sync/status') as Map<String, dynamic>;

  /// Most recent sync runs across all branches (newest first).
  Future<List<dynamic>> getBusySyncRuns({int limit = 20}) async {
    final body = await _get('/api/busy-sync/sync/runs?limit=$limit') as Map<String, dynamic>;
    return body['runs'] as List<dynamic>? ?? const [];
  }

  /// Manually starts a sync run in the background. Omitting [branch] syncs
  /// every branch (company-wide); passing one (must match a branch label
  /// exactly, e.g. "Turning Point") narrows the run to just that branch.
  /// Throws [ApiException] with statusCode 409 if a run — company-wide or
  /// single-branch — is already in progress (one shared lock server-side).
  Future<void> triggerBusySync({String? branch}) async {
    await _post('/api/busy-sync/sync/trigger', branch != null ? {'branch': branch} : null);
  }

  /// Resets a salesperson's password directly (no current-password check).
  /// Server refuses this for any non-SALESPERSON target — see
  /// server/src/services/adminService.js.
  Future<void> resetSalesmanPassword(String salesmanId, String newPassword) async {
    await _post('/api/admin/salesmen/$salesmanId/reset-password', {'newPassword': newPassword});
  }

  /// Sets the signed-in user's password directly — no current-password
  /// check (the caller is already authenticated via their access token).
  /// The server revokes every other session and returns a fresh token pair
  /// for this device — persisted here so the app stays logged in.
  Future<void> changePassword(String newPassword) async {
    final body = await _post('/api/auth/change-password', {
      'newPassword': newPassword,
    }) as Map<String, dynamic>;
    await _persistSession(body['accessToken'] as String, body['refreshToken'] as String);
  }

  /// Revokes the refresh token server-side (a real session invalidation,
  /// not just discarding a local JWT) and clears local storage either way
  /// — a failed revoke call just leaves that one token to expire naturally
  /// in 30 days rather than blocking the user from logging out locally.
  Future<void> logout() async {
    final token = _refreshToken;
    await _persistSession(null, null);
    await _storage.delete(key: _identityKey);
    if (token == null) return;
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': token}),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }

  // ---- Customers ----
  Future<List<dynamic>> getCustomers() async => await _get('/api/customers') as List<dynamic>;
  Future<Map<String, dynamic>> getCustomerDetail(String id) async => await _get('/api/customers/$id') as Map<String, dynamic>;
  Future<Map<String, dynamic>> getCustomerAuditHistoryPage(String id, {String? cursor, int limit = 20}) async {
    final query = <String, String>{'limit': '$limit', if (cursor != null) 'cursor': cursor};
    final qs = Uri(queryParameters: query).query;
    return await _get('/api/customers/$id/audit-history?$qs') as Map<String, dynamic>;
  }
  Future<Map<String, dynamic>> recordOutcome(String customerId, Map<String, dynamic> body) async =>
      await _post('/api/customers/$customerId/record-outcome', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> takeControl(String customerId) async => await _post('/api/customers/$customerId/take-control') as Map<String, dynamic>;
  Future<Map<String, dynamic>> releaseControl(String customerId) async => await _post('/api/customers/$customerId/release-control') as Map<String, dynamic>;
  Future<Map<String, dynamic>> reassignCustomer(String customerId, Map<String, dynamic> body) async =>
      await _post('/api/customers/$customerId/reassign', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> assignManagementInstruction(String customerId, Map<String, dynamic> body) async =>
      await _post('/api/customers/$customerId/management-instruction', body) as Map<String, dynamic>;

  // ---- Tasks ----
  Future<List<dynamic>> getTasks() async => await _get('/api/tasks') as List<dynamic>;
  Future<Map<String, dynamic>> completeTask(String taskId, {String? attachmentPath}) async =>
      await _post('/api/tasks/$taskId/complete', {if (attachmentPath != null) 'attachmentPath': attachmentPath}) as Map<String, dynamic>;
  Future<Map<String, dynamic>> requestTaskExtension(String taskId, Map<String, dynamic> body) async =>
      await _post('/api/tasks/$taskId/request-extension', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> approveTaskEdit(String taskId) async => await _post('/api/tasks/$taskId/approve-edit') as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectTaskEdit(String taskId) async => await _post('/api/tasks/$taskId/reject-edit') as Map<String, dynamic>;
  Future<Map<String, dynamic>> reassignTask(String taskId, Map<String, dynamic> body) async =>
      await _post('/api/tasks/$taskId/reassign', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> rescheduleTask(String taskId, Map<String, dynamic> body) async =>
      await _post('/api/tasks/$taskId/reschedule', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> reviewTask(String taskId) async => await _post('/api/tasks/$taskId/review') as Map<String, dynamic>;
  Future<Map<String, dynamic>> approveInternalAction(String taskId, Map<String, dynamic> body) async =>
      await _post('/api/tasks/$taskId/approve-internal-action', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectInternalAction(String taskId, Map<String, dynamic> body) async =>
      await _post('/api/tasks/$taskId/reject-internal-action', body) as Map<String, dynamic>;

  // ---- PTPs ----
  Future<List<dynamic>> getPtps() async => await _get('/api/ptps') as List<dynamic>;
  Future<Map<String, dynamic>> requestPtpCorrection(String ptpId, Map<String, dynamic> body) async =>
      await _post('/api/ptps/$ptpId/request-correction', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> approvePtpCorrection(String ptpId) async => await _post('/api/ptps/$ptpId/approve-correction') as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectPtpCorrection(String ptpId, Map<String, dynamic> body) async =>
      await _post('/api/ptps/$ptpId/reject-correction', body) as Map<String, dynamic>;

  // ---- Disputes ----
  Future<List<dynamic>> getDisputes() async => await _get('/api/disputes') as List<dynamic>;
  Future<Map<String, dynamic>> approveDispute(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/approve', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectDispute(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/reject', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> requestDisputeInfo(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/request-info', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> resolveDispute(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/resolve', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> answerDisputeClarification(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/answer', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> postDisputeMessage(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/message', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> resolveDisputeByOwner(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/resolve-by-owner', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectDisputeByOwner(String disputeId, Map<String, dynamic> body) async =>
      await _post('/api/disputes/$disputeId/reject-by-owner', body) as Map<String, dynamic>;

  // ---- Outcome correction requests ----
  Future<List<dynamic>> getOutcomeCorrections() async => await _get('/api/outcome-corrections') as List<dynamic>;
  Future<Map<String, dynamic>> requestOutcomeCorrection(String customerId, Map<String, dynamic> body) async =>
      await _post('/api/outcome-corrections/customer/$customerId', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> approveOutcomeCorrection(String id) async => await _post('/api/outcome-corrections/$id/approve') as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectOutcomeCorrection(String id, String reason) async =>
      await _post('/api/outcome-corrections/$id/reject', {'reason': reason}) as Map<String, dynamic>;

  // ---- Outcome edit requests (edit a recorded outcome's own fields, RE-approved) ----
  Future<List<dynamic>> getOutcomeEdits() async => await _get('/api/outcome-edits') as List<dynamic>;
  Future<Map<String, dynamic>> requestOutcomeEdit(String customerId, Map<String, dynamic> body) async =>
      await _post('/api/outcome-edits/customer/$customerId', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> approveOutcomeEdit(String id) async => await _post('/api/outcome-edits/$id/approve') as Map<String, dynamic>;
  Future<Map<String, dynamic>> rejectOutcomeEdit(String id, String reason) async =>
      await _post('/api/outcome-edits/$id/reject', {'reason': reason}) as Map<String, dynamic>;

  // ---- Payment claims ----
  Future<List<dynamic>> getPaymentClaims() async => await _get('/api/payment-claims') as List<dynamic>;
  Future<Map<String, dynamic>> verifyPaymentClaim(String claimId, bool success) async =>
      await _post('/api/payment-claims/$claimId/verify', {'success': success}) as Map<String, dynamic>;

  // ---- Escalations ----
  Future<List<dynamic>> getEscalations() async => await _get('/api/escalations') as List<dynamic>;
  Future<Map<String, dynamic>> raiseEscalation(String customerId, Map<String, dynamic> body) async =>
      await _post('/api/escalations/customer/$customerId', body) as Map<String, dynamic>;
  Future<Map<String, dynamic>> resolveEscalation(String escalationId, String? note) async =>
      await _post('/api/escalations/$escalationId/resolve', note != null ? {'note': note} : null) as Map<String, dynamic>;

  // ---- Salesmen ----
  Future<List<dynamic>> getSalesmen() async => await _get('/api/salesmen') as List<dynamic>;
  Future<Map<String, dynamic>> dismissUnderperformance(String salesmanId) async =>
      await _post('/api/salesmen/$salesmanId/dismiss-underperformance') as Map<String, dynamic>;

  // ---- Reports ----
  Future<Map<String, dynamic>> getDashboardReport() async => await _get('/api/reports/dashboard') as Map<String, dynamic>;
  Future<List<dynamic>> getTrends() async => await _get('/api/reports/trends') as List<dynamic>;
  Future<Map<String, dynamic>> getRePerformance() async => await _get('/api/reports/re-performance') as Map<String, dynamic>;
  Future<Map<String, dynamic>?> getNextCustomer() async => await _get('/api/customers/next') as Map<String, dynamic>?;

  // ---- Notifications ----
  /// Returns the raw `{items, unreadCount}` response.
  Future<Map<String, dynamic>> getNotifications() async => await _get('/api/notifications') as Map<String, dynamic>;

  /// Whether the daily BUSY sync job (customer ageing + invoice sync + PTP
  /// verification — see server/src/services/syncLockService.js) is
  /// currently running — polled by every logged-in role to drive the
  /// universal sync-freeze overlay (AppStore.isSyncing).
  Future<Map<String, dynamic>> getSyncStatus() async => await _get('/api/sync-status') as Map<String, dynamic>;
  Future<void> markNotificationRead(String notificationId) => _post('/api/notifications/$notificationId/read');
  Future<void> markAllNotificationsRead() => _post('/api/notifications/read-all');

  // ---- Attachments (call-screenshot evidence, see outcome_forms.dart's
  // NoAnswerForm and server/src/routes/attachmentRoutes.js) ----

  /// Uploads image [bytes] and returns the server-assigned filename (a
  /// fresh uuid — never the original name) to pass as `attachmentPath`
  /// when recording the outcome this is evidence for.
  ///
  /// Mirrors [_authedSend]'s 401-refresh-and-retry: unlike a JSON call, a
  /// sent [http.MultipartRequest] can't be resent, so on a 401 this rebuilds
  /// the multipart request from scratch (same bytes, fresh access token)
  /// rather than reusing the original. Without this, filling out a form that
  /// takes longer than the access token's lifetime (e.g. picking a deadline
  /// date/time before attaching a PDF) would fail the upload with "Invalid
  /// or expired token" even though every other request on the same screen
  /// silently refreshes.
  Future<String> uploadAttachment(List<int> bytes, {required String filename, required String contentType}) async {
    final uri = Uri.parse('$baseUrl/api/attachments');
    // The filename MUST be non-empty: a multipart file part with an empty
    // `filename=""` is parsed as an ordinary form field, not a file, so
    // the server then reports "no file uploaded". PDFs picked via
    // XFile.fromData come through here with an empty name (cross_file's
    // io impl ignores the `name:` arg), which is exactly how this bit.
    final ext = contentType == 'application/pdf' ? '.pdf' : '.jpg';
    var safeName = filename.trim();
    if (safeName.isEmpty) safeName = 'attachment$ext';

    Future<http.Response> send() async {
      // Only the auth header — never _headers, whose 'Content-Type:
      // application/json' would fight the multipart boundary content-type.
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: safeName, contentType: MediaType.parse(contentType)));
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      final streamed = await request.send().timeout(_requestTimeout);
      return http.Response.fromStream(streamed);
    }

    try {
      var res = await send();
      if (res.statusCode == 401 && _refreshToken != null) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          res = await send();
        }
      }
      final body = await _handle(res) as Map<String, dynamic>;
      return body['path'] as String;
    } on TimeoutException {
      throw ApiException(statusCode: 0, message: 'The server is taking too long to respond. Please try again.');
    } on SocketException {
      throw ApiException(statusCode: 0, message: 'Could not reach the server. Please check your connection and try again.');
    } on http.ClientException {
      throw ApiException(statusCode: 0, message: 'Could not reach the server. Please check your connection and try again.');
    }
  }

  /// Full URL for a previously-uploaded attachment — pair with
  /// [attachmentAuthHeaders] on `Image.network` (the endpoint requires
  /// authentication, which `Image.network` doesn't send by default).
  String attachmentUrl(String path) => '$baseUrl/api/attachments/$path';

  Map<String, String> get attachmentAuthHeaders => _headers();
}
