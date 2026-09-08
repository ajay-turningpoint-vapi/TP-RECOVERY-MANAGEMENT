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
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? 'http://192.168.1.141:4000';

  final String baseUrl;
  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'tp_rms_access_token';
  static const _refreshTokenKey = 'tp_rms_refresh_token';
  static const _requestTimeout = Duration(seconds: 20);

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;

  /// Set by AppStore. Fired when the session can no longer be salvaged —
  /// the refresh token itself was rejected (expired, revoked, or reused) —
  /// so the UI can drop back to the login screen from wherever it happens
  /// to be, not just from a screen that catches the resulting ApiException.
  void Function()? onSessionExpired;

  Future<void> loadPersistedSession() async {
    _accessToken = await _storage.read(key: _accessTokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);
  }

  bool get isAuthenticated => _accessToken != null && _refreshToken != null;

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

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<dynamic> _handle(http.Response res) async {
    final isJson = res.headers['content-type']?.contains('application/json') ?? false;
    final body = isJson && res.body.isNotEmpty ? jsonDecode(res.body) : null;

    if (res.statusCode >= 200 && res.statusCode < 300) return body;

    final error = body is Map ? body['error'] as Map<String, dynamic>? : null;
    throw ApiException(
      statusCode: res.statusCode,
      message: error?['message'] as String? ?? 'Request failed (${res.statusCode})',
      code: error?['code'] as String?,
    );
  }

  /// Bare HTTP call with a timeout and friendly translation of network
  /// failures — every caller downstream only ever has to catch
  /// [ApiException], never a raw [SocketException]/[TimeoutException].
  Future<http.Response> _rawSend(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final future = method == 'GET'
          ? http.get(uri, headers: _headers)
          : http.post(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
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
  Future<dynamic> _authedSend(String method, String path, [Map<String, dynamic>? body]) async {
    var res = await _rawSend(method, path, body);
    if (res.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        res = await _rawSend(method, path, body);
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

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _rawSend('POST', '/api/auth/login', {'username': username, 'password': password});
    final body = await _handle(res) as Map<String, dynamic>;
    await _persistSession(body['accessToken'] as String, body['refreshToken'] as String);
    return body['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async => await _get('/api/auth/me') as Map<String, dynamic>;

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
  Future<Map<String, dynamic>> completeTask(String taskId) async => await _post('/api/tasks/$taskId/complete') as Map<String, dynamic>;
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
  Future<Map<String, dynamic>> markPtpOutcome(String ptpId, Map<String, dynamic> body) async =>
      await _post('/api/ptps/$ptpId/mark-outcome', body) as Map<String, dynamic>;

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

  // ---- Reports ----
  Future<Map<String, dynamic>> getDashboardReport() async => await _get('/api/reports/dashboard') as Map<String, dynamic>;
  Future<List<dynamic>> getTrends() async => await _get('/api/reports/trends') as List<dynamic>;
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
  Future<String> uploadAttachment(List<int> bytes, {required String filename, required String contentType}) async {
    final uri = Uri.parse('$baseUrl/api/attachments');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType.parse(contentType)));
    try {
      final streamed = await request.send().timeout(_requestTimeout);
      final res = await http.Response.fromStream(streamed);
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

  Map<String, String> get attachmentAuthHeaders => _headers;
}
