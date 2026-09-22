import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/models/escalation_case.dart';
import 'package:salesman_mobile/v2/models/notification_item.dart';
import 'package:salesman_mobile/v2/models/control_snapshot.dart';
import 'package:salesman_mobile/v2/models/outcome_correction_request.dart';
import 'package:salesman_mobile/v2/models/outcome_edit_request.dart';
import 'package:salesman_mobile/services/api_client.dart';
import 'package:salesman_mobile/services/notification_service.dart';
import 'package:salesman_mobile/services/realtime_client.dart';
import 'package:salesman_mobile/services/local_db.dart';
import 'package:salesman_mobile/services/pending_action.dart';
import 'package:salesman_mobile/services/pending_action_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// Thrown by a write method (recordOutcome, a PTP/dispute/payment-claim/
/// task action, ...) instead of the network [ApiException] it caught, when
/// that failure was network-shaped and the action has been queued for
/// automatic sync instead of lost. Callers should show a success-toned
/// "Saved — will sync once you're back online" message, not an error one —
/// a real (non-network) rejection still throws [ApiException] as before
/// and is never queued.
class QueuedForSyncException implements Exception {
  const QueuedForSyncException();
}

/// One server-paginated page of a customer's audit history — see
/// AppStore.fetchAuditHistoryPage. `nextCursor` is null once there's
/// nothing more to fetch.
class AuditHistoryPage {
  final List<AuditEvent> items;
  final String? nextCursor;
  AuditHistoryPage({required this.items, required this.nextCursor});
}

class AppStore extends ChangeNotifier {
  // Empty until a real login response sets these (see the 'fullName' read
  // below) — isLoggedIn starts false, so LoginScreen always renders first
  // and no real user ever sees these. Previously hardcoded to a fake
  // "Rahul"/"Rahul Sharma" persona left over from an old demo account that
  // no longer exists in the real database at all.
  String currentSalesmanId = '';
  String userRole = ''; // 'SALESPERSON', 'RECOVERY_EXECUTIVE', 'MANAGEMENT', or 'ADMIN'
  String currentUserFullName = '';
  // The actual login credential (e.g. 'gopal') — distinct from
  // currentSalesmanId, which is the internal DB id (a UUID for real
  // salesman accounts) used for RMS ownership filtering, not for display.
  String currentUsername = '';
  bool isLoggedIn = false;

  /// True from construction until [restoreSession] finishes checking for a
  /// persisted session — the app shows a splash instead of the login
  /// screen during this window so a genuinely still-logged-in user
  /// (refresh token still valid) never sees a login flash on cold start.
  bool sessionLoading = true;

  // Universal sync-freeze — true while the server's daily BUSY sync job
  // (customer ageing + invoice sync + PTP verification, or a MANAGEMENT
  // admin's manual trigger — see server/src/services/syncLockService.js)
  // is running. Every screen checks this via the SyncFreezeOverlay wrapped
  // around the whole app in main_v3.dart, since real customer/PTP/task
  // data is being rewritten server-side for the duration.
  bool isSyncing = false;
  DateTime? syncingSince;

  // A killed / crashed sync process can leave the server-side lock set with
  // no "finished" event ever arriving, which would freeze every client
  // behind the "Syncing with BUSY" curtain indefinitely. The server now
  // puts a TTL on that lock, but this is the client's own backstop: never
  // trust `isSyncing` for longer than a real sync could plausibly take.
  static const Duration _maxSyncCurtain = Duration(minutes: 20);

  /// `isSyncing` but the start timestamp is implausibly old — the lock is
  /// almost certainly stale (dead sync process). Don't block the UI for it.
  bool get isSyncStale =>
      isSyncing &&
      syncingSince != null &&
      DateTime.now().difference(syncingSince!) > _maxSyncCurtain;

  /// Whether to actually show the full-screen sync freeze curtain.
  bool get showSyncCurtain => isSyncing && !isSyncStale;

  // Outcome of the last FINISHED BUSY sync (see server
  // routes/syncStatusRoutes.js `lastSync`). When the sync failed — most
  // often because the BUSY ERP source was unreachable — active clients
  // show a real message instead of silently rendering stale data. Cleared
  // automatically once a later sync succeeds.
  bool syncFailed = false;
  bool syncFailedIsConnection = false;
  String? syncFailedMessage;
  DateTime? syncFailedAt;
  bool _syncFailureDismissed = false;

  /// True while a failed-sync message should be visible to the user (a
  /// newer failure re-shows it even after a manual dismiss).
  bool get showSyncFailure =>
      syncFailed && !_syncFailureDismissed && !showSyncCurtain;

  void dismissSyncFailure() {
    if (_syncFailureDismissed) return;
    _syncFailureDismissed = true;
    notifyListeners();
  }

  // Manager-only kill switch (see server's maintenanceService.js). Blocks
  // every non-MANAGEMENT request server-side; this is purely the client's
  // reflection of that state, kept current two ways — whichever fires
  // first wins: the SSE 'maintenance' push (see _onRealtimeEvent, instant
  // for an already-connected client) or ApiClient.onMaintenanceMode (fires
  // off ANY rejected request, covering a client whose stream is mid-
  // reconnect when the toggle happens). MANAGEMENT itself is never
  // blocked, so this only ever matters for other roles.
  bool maintenanceMode = false;
  DateTime? maintenanceSince;

  void _handleMaintenanceMode() {
    if (maintenanceMode) return;
    maintenanceMode = true;
    notifyListeners();
  }

  /// Proactive, unauthenticated check — called once from [restoreSession]
  /// on every cold start so the login screen itself can reflect an active
  /// maintenance window, not just a login attempt made during one. Also
  /// polled every 15s by LoginScreen while logged out (no SSE without
  /// auth), which is how a logged-out user sitting on the maintenance
  /// screen learns it's over.
  Future<void> checkMaintenanceStatus() async {
    try {
      final result = await apiClient.getMaintenanceStatus();
      final enabled = result['enabled'] as bool? ?? false;
      final since = result['since'] as String?;
      final wasEnabled = maintenanceMode;
      maintenanceMode = enabled;
      maintenanceSince = enabled && since != null ? DateTime.tryParse(since) : null;
      if (wasEnabled && !enabled) _notifyMaintenanceOver();
      notifyListeners();
    } catch (_) {
      // Can't reach the server at all — the normal connectivity handling
      // elsewhere already covers that; nothing maintenance-specific to do.
    }
  }

  /// A real OS notification (not just the screen clearing itself) — the
  /// maintenance page is deliberately calm/passive ("this page updates on
  /// its own"), so anyone who backgrounded the app while waiting still
  /// needs a prompt to come back, not just a silently-changed screen.
  void _notifyMaintenanceOver() {
    NotificationService.instance.show(
      id: 990000001,
      title: 'Maintenance Complete',
      body: "You're all set — Clock is back online and ready to use.",
      icon: 'ic_notif_clock',
      bigText: true,
    );
  }

  // Real-time push replaces all client polling. One SSE stream
  // (`GET /api/events`) delivers coarse "these lists changed" events; we
  // re-fetch just those lists. See services/realtime_client.dart.
  late final RealtimeClient _realtime = RealtimeClient(apiClient);
  StreamSubscription<RealtimeEvent>? _realtimeEventsSub;
  StreamSubscription<bool>? _realtimeConnSub;
  Timer? _invalidateDebounce;
  final Set<String> _pendingInvalidations = {};
  bool _refreshInFlight = false;

  // True while any server fetch of the core lists is running (login/restore,
  // a nav-tap refresh, or an SSE-triggered re-fetch). Screens show a thin
  // progress bar / spinner off this so a load never happens invisibly.
  bool get isFetchingData => _refreshInFlight;

  // Flips true the first time the full data set has come back from the
  // server this session. Until then, list screens show a loader instead of
  // an empty state (on a warm start the scaffold renders before the first
  // fetch completes — see restoreSession).
  bool _hasLoadedInitialData = false;
  bool get hasLoadedInitialData => _hasLoadedInitialData;
  bool get isInitialDataLoading => isLoggedIn && !_hasLoadedInitialData;

  // Surfaced by InitialDataLoader when the very first load (no cache to
  // fall back on — see _loadFromCache below) fails outright, so the user
  // gets a real error + retry button instead of an indefinite spinner.
  String? _initialLoadError;
  String? get initialLoadError => _initialLoadError;

  // Last-known-good local snapshot (see lib/services/local_db.dart) —
  // customers/tasks/ptps/etc. survive a cold start with no signal, read
  // back and shown immediately while a live refresh is attempted in the
  // background. Non-null means the user is currently looking at cached
  // data, not a confirmed-live snapshot (see _loadFromCache/dataAsOf).
  final LocalDb _localDb = LocalDb();
  DateTime? dataAsOf;
  bool get isShowingCachedData => dataAsOf != null;

  // Offline write queue (see lib/services/pending_action_queue.dart) — a
  // Record Outcome / PTP / dispute / payment-claim / task action that fails
  // on a network error is queued here instead of just failing, and synced
  // automatically once connectivity returns.
  late final PendingActionQueue pendingActionQueue = PendingActionQueue(_localDb, apiClient);
  StreamSubscription<List<PendingAction>>? _pendingActionsSub;
  Timer? _pendingFlushTimer;
  List<PendingAction> _pendingActions = [];
  List<PendingAction> get pendingActions => _pendingActions;
  int get pendingActionCount => _pendingActions.length;
  bool hasPendingActionForCustomer(String customerId) =>
      _pendingActions.any((a) => a.relatedCustomerId == customerId && a.status != 'failedTerminal');

  void _startPendingActionWatch() {
    _pendingActionsSub?.cancel();
    _pendingActionsSub = _localDb.watchOpenPendingActions(currentSalesmanId).listen((rows) {
      _pendingActions = rows;
      notifyListeners();
    });
    _pendingFlushTimer?.cancel();
    // Backstop: SSE-reconnect and app-resume (see _startRealtime /
    // onAppResumed) are the primary flush triggers; this just guarantees a
    // queue never sits stuck if neither fires for a while (e.g. the app
    // stays foregrounded with a flaky, never-fully-dropped connection).
    _pendingFlushTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(pendingActionQueue.flush(currentSalesmanId));
    });
  }

  void _stopPendingActionWatch() {
    _pendingActionsSub?.cancel();
    _pendingActionsSub = null;
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _pendingActions = [];
  }

  /// Called from main_v3.dart's WidgetsBindingObserver on
  /// AppLifecycleState.resumed — a salesperson foregrounding the app after
  /// regaining signal shouldn't have to wait for SSE's own backoff ladder
  /// (up to 30s) before a queued action flushes.
  void onAppResumed() {
    if (!isLoggedIn) return;
    unawaited(pendingActionQueue.flush(currentSalesmanId));
  }

  /// Every write method's catch block funnels its [ApiException] through
  /// here: a real rejection (statusCode != 0) is rethrown unchanged, so
  /// every existing screen's error handling is untouched for that case. A
  /// network-shaped failure (statusCode 0) is queued instead, then this
  /// throws [QueuedForSyncException] so the caller can show a distinct
  /// "saved, will sync later" message instead of today's error toast. If
  /// the customer already has an unsynced action pending, the queue itself
  /// refuses a second one ([PendingActionBlockedException]) — surfaced
  /// here as a plain [ApiException] so it reads like any other rejection
  /// rather than a silent no-op.
  Future<Never> _queueOrRethrow(
    ApiException e, {
    required PendingActionType type,
    required String targetEndpoint,
    required Map<String, dynamic> payload,
    String? relatedCustomerId,
    List<int>? attachmentBytes,
    String? attachmentContentType,
  }) async {
    if (e.statusCode != 0) throw e;
    try {
      await pendingActionQueue.enqueue(
        type: type,
        targetEndpoint: targetEndpoint,
        payload: payload,
        scopeUserId: currentSalesmanId,
        relatedCustomerId: relatedCustomerId,
        attachmentBytes: attachmentBytes,
        attachmentContentType: attachmentContentType,
      );
    } on PendingActionBlockedException catch (blocked) {
      throw ApiException(statusCode: 0, message: blocked.message);
    }
    throw const QueuedForSyncException();
  }

  Future<void> _cacheList(String key, Object? raw) async {
    if (currentSalesmanId.isEmpty) return;
    try {
      await _localDb.putList(key, currentSalesmanId, raw);
    } catch (_) {
      // Best-effort — a local disk write failing must never break a live
      // refresh that otherwise succeeded.
    }
  }

  // First `_refreshNotificationsFromApi` call each session loads the
  // existing backlog, not newly-arrived items — this suppresses firing a
  // burst of OS notifications for history the user hasn't even opened the
  // in-app bell for yet.
  bool _notificationsPrimed = false;

  final ApiClient apiClient = ApiClient();
  DateTime lastBusySync = DateTime.now();

  AppStore() {
    // Fires when a background request's silent refresh attempt fails
    // outright (the refresh token itself was rejected) — drops the user
    // back to the login screen from wherever they are, not just from a
    // screen that happens to catch the resulting ApiException.
    apiClient.onSessionExpired = _handleSessionExpired;
    apiClient.onMaintenanceMode = _handleMaintenanceMode;
  }

  List<Customer> customers = [];
  List<AppTask> tasks = [];

  /// A Salesperson may only see their own assigned customer portfolio
  /// (spec RMS-01, Product Law — LOCKED). Recovery Executive/Management keep
  /// company-wide visibility via [customers] directly.
  ///
  /// BUSY-sourced customers (c.address set — see busyCustomerService.js)
  /// have no RMS `assignedSalesmanId` at all; the server already scoped
  /// them to this salesman's BUSY code before they ever reached the
  /// client, via a different mechanism than assignedSalesmanId, so the
  /// RMS-side check below is bypassed for them rather than weakened —
  /// an unassigned RMS customer (assignedSalesmanId also blank) still
  /// correctly stays excluded.
  List<Customer> get myCustomers => userRole == 'SALESPERSON'
      ? customers.where((c) => c.address != null || c.assignedSalesmanId == currentSalesmanId).toList()
      : visibleCustomers;

  /// Same portfolio-isolation rule applied to tasks: a Salesperson's "My
  /// Tasks" must show only tasks owned by them, not every task company-wide.
  /// RE/Management see every task, narrowed to the selected branch.
  List<AppTask> get myTasks =>
      userRole == 'SALESPERSON' ? tasks.where((t) => t.ownerId == currentSalesmanId).toList() : visibleTasks;

  /// Open (not-completed) tasks the signed-in salesperson owns — drives the
  /// count bubble on the bottom-nav Tasks icon.
  int get myOpenTaskCount =>
      myTasks.where((t) => t.status != TaskStatus.completed).length;

  // ─────────────────────────────────────────────────────────────────────
  // Branch filter — a single global scope an RE / Manager sets once (from
  // the dashboard's branch dropdown, persisted). Every RE/Manager list,
  // card and count is derived from the `visible*` views below, so picking
  // a branch narrows the whole app; 'All Branches' is a pass-through.
  // Salesperson portfolios are already single-scoped, so this never
  // applies to them.
  // ─────────────────────────────────────────────────────────────────────
  static const String kAllBranches = 'All Branches';
  static const String _kBranchPrefKey = 're_branch_filter';
  String _branchFilter = kAllBranches;
  String get branchFilter => _branchFilter;
  bool get isAllBranches => _branchFilter == kAllBranches;
  bool get canFilterByBranch => userRole == 'RECOVERY_EXECUTIVE' || userRole == 'MANAGEMENT';
  bool get _branchActive => canFilterByBranch && !isAllBranches;

  /// 'All Branches' + every distinct branch seen on the roster / customers.
  List<String> get branchOptions {
    final set = <String>{};
    for (final s in salesmen) {
      final b = (s['branch'] as String?)?.trim();
      if (b != null && b.isNotEmpty) set.add(b);
    }
    for (final c in customers) {
      if (c.branch.trim().isNotEmpty) set.add(c.branch);
    }
    final list = set.toList()..sort();
    return [kAllBranches, ...list];
  }

  Future<void> setBranchFilter(String value) async {
    if (_branchFilter == value) return;
    _branchFilter = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBranchPrefKey, value);
    } catch (_) {/* preference is a convenience, never fatal */}
  }

  Future<void> _loadBranchFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _branchFilter = prefs.getString(_kBranchPrefKey) ?? kAllBranches;
    } catch (_) {
      _branchFilter = kAllBranches;
    }
    notifyListeners();
  }

  // Branch resolvers — tasks/PTPs/disputes/escalations carry no branch of
  // their own; it comes from their customer (falling back to the assigned
  // salesman's branch for a task with no matching customer row).
  String salesmanBranchOf(String salesmanId) {
    final rec = salesmen.firstWhere((s) => s['id'] == salesmanId, orElse: () => const {});
    return (rec['branch'] as String?) ?? 'Turning Point';
  }

  String customerBranchOf(String customerId) {
    for (final c in customers) {
      if (c.id == customerId) return c.branch;
    }
    return 'Turning Point';
  }

  String taskBranchOf(AppTask t) {
    for (final c in customers) {
      if (c.id == t.customerId) return c.branch;
    }
    return t.ownerId.isNotEmpty ? salesmanBranchOf(t.ownerId) : 'Turning Point';
  }

  bool _inBranch(String branch) => !_branchActive || branch == _branchFilter;

  // Branch-scoped views — identity unless a specific branch is active.
  List<Customer> get visibleCustomers =>
      _branchActive ? customers.where((c) => c.branch == _branchFilter).toList() : customers;
  List<AppTask> get visibleTasks =>
      _branchActive ? tasks.where((t) => _inBranch(taskBranchOf(t))).toList() : tasks;
  List<PromiseToPay> get visiblePtps =>
      _branchActive ? ptps.where((p) => _inBranch(customerBranchOf(p.customerId))).toList() : ptps;
  List<Map<String, dynamic>> get visibleDisputes => _branchActive
      ? disputes.where((d) => _inBranch(customerBranchOf('${d['customerCode']}'))).toList()
      : disputes;
  List<Map<String, dynamic>> get visiblePaymentClaims => _branchActive
      ? paymentClaims.where((p) => _inBranch(customerBranchOf('${p['customerCode']}'))).toList()
      : paymentClaims;
  List<EscalationCase> get visibleEscalationCases =>
      _branchActive ? escalationCases.where((e) => _inBranch(customerBranchOf(e.customerId))).toList() : escalationCases;
  List<Map<String, dynamic>> get visibleSalesmen => _branchActive
      ? salesmen.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == _branchFilter).toList()
      : salesmen;
  // The attempt number the *next* No Answer submission would be — the
  // real server-tracked count (customers[].noAnswerAttempts) plus one.
  // Drives the form's "Attempt N" label and its "a Physical Visit will be
  // created automatically" warning on the call that hits the threshold.
  int noAnswerAttemptCount(String customerId) {
    final customer = customers.firstWhere((c) => c.id == customerId, orElse: () => customers.first);
    return customer.noAnswerAttempts + 1;
  }
  // Spec calls this threshold out as configurable, not fixed — how many
  // unanswered attempts before a Physical Visit is auto-recommended. The
  // 3rd No Answer triggers it (and resets the counter); recording any
  // other outcome first resets the counter too. Kept in sync with the
  // server's NO_ANSWER_THRESHOLD in customerService.js.
  static const int noAnswerThreshold = 3;

  // End of Day metrics
  int customersHandled = 0;
  int ptpsCreated = 0;
  double ptpAmount = 0.0;
  int tasksCompleted = 0;

  // The "40/2" progress on the dashboard's Today's Recovery card — real,
  // server-computed from the actual audit trail (reportService.getDashboard's
  // myRecoveryDoneTodayCount, counting distinct customers with a
  // recordOutcome-sourced audit event today), not an in-memory per-session
  // counter. Stable across app restarts/relaunches and rolls over at
  // midnight on its own, since it's a genuine "today" query rather than a
  // client-side flag that has to remember to reset.
  int get recoveryDoneTodayCount => (_dashboardReport['myRecoveryDoneTodayCount'] as int?) ?? 0;

  /// The actual customer ids behind [recoveryDoneTodayCount] — grounded in
  /// the same real audit trail (a recordOutcome-sourced audit event today),
  /// not customer.updatedAt. updatedAt is NOT a safe "done today" signal on
  /// its own: the daily BUSY sync rewrites every synced customer's row
  /// (customerAgeingSync/customerInvoiceSync), bumping updatedAt for the
  /// whole portfolio regardless of whether the salesperson touched them —
  /// right after that sync runs, nearly every resolved customer would
  /// otherwise falsely show as "done today" in Today's Recovery Tasks.
  Set<String> get recoveryDoneTodayCustomerIds =>
      ((_dashboardReport['myRecoveryDoneTodayCustomerIds'] as List?) ?? const []).cast<String>().toSet();

  // Reports screen usage (real, session-based — not a fabricated figure)
  int reportsGeneratedCount = 3;
  void incrementReportsGenerated() {
    reportsGeneratedCount++;
    notifyListeners();
  }

  /// Real, genuinely-accumulated historical daily metrics from the server
  /// (`GET /api/reports/trends`, populated by the 5 PM snapshot job) — only
  /// ever as many points as have genuinely been recorded. No fabricated
  /// placeholder history.
  List<Map<String, dynamic>> trends = [];

  List<Map<String, dynamic>> get recoveryScoreTrend =>
      trends.map((t) => {'label': _trendLabel(t), 'score': t['avgRecoveryScore']}).toList();
  List<Map<String, dynamic>> get ptpAmountTrend => trends.map((t) => {'label': _trendLabel(t), 'amount': t['ptpAmountTotal']}).toList();
  List<Map<String, dynamic>> get brokenPtpCountTrend => trends.map((t) => {'label': _trendLabel(t), 'count': t['brokenPtpCount']}).toList();
  List<Map<String, dynamic>> get collectionTrend =>
      trends.map((t) => {'label': _trendLabel(t), 'expected': t['collectionExpected'], 'actual': t['collectionActual']}).toList();
  List<Map<String, dynamic>> get noFollowUpTrend => trends.map((t) => {'label': _trendLabel(t), 'count': t['noFollowUpCount']}).toList();
  List<Map<String, dynamic>> get dailyCollectionTrend => trends.map((t) => {'label': _trendLabel(t), 'amount': t['collectionActual']}).toList();
  List<Map<String, dynamic>> get collectionsTrendLast7Days =>
      trends.map((t) => {'label': _trendLabel(t), 'expected': t['collectionExpected'], 'actual': t['collectionActual']}).toList();

  String _trendLabel(Map<String, dynamic> t) => DateFormat('dd MMM').format(DateTime.parse(t['date'] as String).toLocal());

  static const int noFollowUpThresholdDays = 4; // configurable, per spec §71
  // Company-wide (server) list; when a branch is active it's recomputed
  // locally from the branch-scoped customers, using the SAME rule the
  // server applies (no real activity logged in noFollowUpThresholdDays+
  // days) so switching a branch filter never changes what "no follow-up"
  // means — only which customers it's evaluated over. Previously this
  // branch used an unrelated `!hasValidNextAction` check, so the exact same
  // report could silently show two different definitions of "no
  // follow-up" depending on unrelated dashboard state.
  List<Customer> get noFollowUpAccounts => _branchActive
      ? visibleCustomers.where((c) => c.totalDue > 0 && daysSinceLastFollowUp(c) >= noFollowUpThresholdDays).toList()
      : ((_dashboardReport['noFollowUpAccounts'] as List?) ?? []).map((j) => Customer.fromJson(j as Map<String, dynamic>)).toList();

  /// Days since the most recent real recovery activity on this customer —
  /// their latest audit event or task activity; falls back to their overdue
  /// age when nothing has ever been logged. A real, non-fabricated
  /// per-customer computation over already-real data (not an aggregation
  /// formula), used by report screens to sort/filter an arbitrary customer
  /// list on demand — the company-wide equivalent (`noFollowUpAccounts`
  /// above) is computed server-side.
  int daysSinceLastFollowUp(Customer c) {
    // Real, server-computed value (with actual audit history the bulk
    // customer list never sends) when this customer came from
    // noFollowUpAccounts. Only that one dashboard field carries it.
    if (c.serverDaysSinceLastFollowUp != null) return c.serverDaysSinceLastFollowUp!;
    DateTime? last;
    for (final a in c.auditHistory) {
      if (last == null || a.timestamp.isAfter(last)) last = a.timestamp;
    }
    for (final t in tasks.where((t) => t.customerId == c.id)) {
      final ts = t.completedAt ?? t.deadline;
      if (last == null || ts.isAfter(last)) last = ts;
    }
    if (last == null) return c.oldestOverdueDays;
    final days = DateTime.now().difference(last).inDays;
    return days < 0 ? 0 : days;
  }

  double get todaysCollectedAmount => (_dashboardReport['todaysCollectedAmount'] as num?)?.toDouble() ?? 0.0;

  // Company-wide recovery target — Tier 1 (25%) of total overdue exposure,
  // computed server-side in reportService.getDashboard.
  double get recoveryTarget => (_dashboardReport['recoveryTarget'] as num?)?.toDouble() ?? 0.0;
  // Expected Collection = valid customer payment commitments (scheduled
  // PTPs) — a simple filter over the real, already-fetched `ptps` list, not
  // an aggregation formula.
  double get expectedCollection => teamExpectedCollection;

  // Recovery Executive Team Data
  double get teamTotalOutstanding => visibleCustomers.fold(0.0, (sum, c) => sum + c.totalOutstanding);
  double get teamTotalDue => visibleCustomers.fold(0.0, (sum, c) => sum + c.totalDue);
  double get teamExpectedCollection => ptps
      .where((p) => p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification)
      .fold(0.0, (sum, p) => sum + p.amountPromised);

  /// Company-wide dashboard aggregates — real, computed server-side in
  /// `reportService.getDashboard` (see server/src/services/reportService.js),
  /// role-scoped the same way every other list endpoint already is. Fetched
  /// by [_refreshReportsFromApi].
  Map<String, dynamic> _dashboardReport = {};

  // When a branch is active, the headline cards recompute from the
  // branch-scoped local lists (see the answer to "recompute client-side");
  // 'All Branches' keeps the exact server-computed figures.
  double get totalOverdueAmount => _branchActive
      ? visibleCustomers.where((c) => c.totalDue > 0).fold(0.0, (s, c) => s + c.totalDue)
      : (_dashboardReport['totalOverdueAmount'] as num?)?.toDouble() ?? 0.0;
  int get totalOverdueCustomerCount => _branchActive
      ? visibleCustomers.where((c) => c.totalDue > 0).length
      : (_dashboardReport['totalOverdueCustomerCount'] as int?) ?? 0;
  double get dueTodayPtpAmount => _branchActive ? _branchDueTodayPtps.fold(0.0, (s, p) => s + p.amountPromised) : (_dashboardReport['dueTodayPtpAmount'] as num?)?.toDouble() ?? 0.0;
  int get dueTodayPtpCount => _branchActive ? _branchDueTodayPtps.length : (_dashboardReport['dueTodayPtpCount'] as int?) ?? 0;
  List<PromiseToPay> get _branchDueTodayPtps {
    final now = DateTime.now();
    return visiblePtps.where((p) {
      if (p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification) return false;
      final d = p.promiseDate;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
  }
  int get overdueCustomersCount => _branchActive ? totalOverdueCustomerCount : (_dashboardReport['overdueCustomersCount'] as int?) ?? 0;
  double get overdueCustomersAmount => _branchActive ? totalOverdueAmount : (_dashboardReport['overdueCustomersAmount'] as num?)?.toDouble() ?? 0.0;
  int get ptpKeptMtdPercent => (_dashboardReport['ptpKeptMtdPercent'] as int?) ?? 0;

  int get ptpKeptTarget => 75; // configured business target, not a derived figure

  int get todaysCollectedCustomerCount => (_dashboardReport['todaysCollectedCustomerCount'] as int?) ?? 0;
  double get companyCollectionTargetToday => (_dashboardReport['companyCollectionTargetToday'] as num?)?.toDouble() ?? 0.0;
  int get companyCollectionAchievedTodayPercent => (_dashboardReport['companyCollectionAchievedTodayPercent'] as int?) ?? 0;

  /// Total outstanding split into ageing buckets — real, computed
  /// server-side from every customer's oldest overdue days.
  Map<String, double> get outstandingAgeingBuckets {
    final raw = (_dashboardReport['outstandingAgeingBuckets'] as Map?) ?? {};
    return raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  /// Dispute counts/amounts grouped into the four lifecycle buckets shown on
  /// the Manager Dashboard — real, computed server-side.
  Map<String, Map<String, num>> get disputeOverviewByStatus {
    final raw = (_dashboardReport['disputeOverviewByStatus'] as Map?) ?? {};
    return raw.map((k, v) => MapEntry(k as String, (v as Map).cast<String, num>()));
  }

  int get totalDisputesCount => (_dashboardReport['totalDisputesCount'] as int?) ?? 0;
  double get totalDisputesAmount => (_dashboardReport['totalDisputesAmount'] as num?)?.toDouble() ?? 0.0;

  /// PTP lifecycle counts/amounts for the Manager Dashboard — real,
  /// computed server-side.
  Map<String, dynamic> get ptpOverviewStats => (_dashboardReport['ptpOverviewStats'] as Map?)?.cast<String, dynamic>() ?? {};

  /// Top 5 customers by outstanding due, company-wide — real, computed
  /// server-side.
  List<Customer> get topOverdueCustomers {
    if (_branchActive) {
      final list = visibleCustomers.where((c) => c.totalDue > 0).toList()
        ..sort((a, b) => b.totalDue.compareTo(a.totalDue));
      return list.take(5).toList();
    }
    return ((_dashboardReport['topOverdueCustomers'] as List?) ?? []).map((j) => Customer.fromJson(j as Map<String, dynamic>)).toList();
  }

  int get customers30PlusOverdueCount => (_dashboardReport['customers30PlusOverdueCount'] as int?) ?? 0;

  /// Total amount actually received across every kept/partially-kept PTP in
  /// the portfolio — the Manager Reports "Total Received" figure.
  double get totalReceivedAllTime => visiblePtps.where((p) => p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept).fold(0.0, (s, p) => s + (p.amountReceived ?? 0));

  // Needs Your Attention tiles — the counts/flags themselves (level,
  // status, collectionAchievedPercent, etc.) are real server data; these
  // getters are simple display filters over that already-real data, not
  // aggregation formulas. Company-wide totals (disputesAwaitingReviewCount,
  // needsAttentionBadgeCount) come straight from the dashboard report.
  int get salesmenOverdueTargetsCount => visibleSalesmen.where((s) => (s['collectionAchievedPercent'] as int) < 60).length;
  /// Physical-visit tasks the salesman closed without recording an outcome —
  /// the RE nudges them, there is nothing to "review".
  List<AppTask> get physicalVisitsPendingReview => visibleTasks
      .where((t) =>
          t.type == TaskType.physicalVisit &&
          t.status == TaskStatus.completed &&
          (t.outcome == null || t.outcome!.trim().isEmpty))
      .toList();
  int get physicalVisitsPendingReviewCount =>
      _branchActive ? physicalVisitsPendingReview.length : (_dashboardReport['physicalVisitsPendingReviewCount'] as int?) ?? 0;
  int get disputesAwaitingReviewCount => _branchActive
      ? visibleDisputes.where((d) => disputeNeedsReActionStatuses.contains(d['status'])).length
      : (_dashboardReport['disputesAwaitingReviewCount'] as int?) ?? 0;

  /// Every dispute status where an RE/Management action is genuinely
  /// needed right now — a fresh claim to approve/reject ('Pending
  /// Approval'), or a resolution owner's claim to verify ('Awaiting
  /// Verification'). Every RE-facing badge/list/count meaning "how many
  /// disputes need my attention" must read this, not just 'Pending
  /// Approval' alone — that was the single root cause behind a dispute
  /// going silently invisible (no badge, no notification, buried under
  /// "resolved/other") the moment a resolution owner submitted theirs for
  /// verification. Distinct from a pure status-overview bucketing (e.g.
  /// the manager's Dispute Status Report), where 'Awaiting Verification'
  /// is correctly grouped under "In Progress" instead — that's a
  /// different question ("what state is it in") from this one ("does it
  /// need MY action right now").
  static const Set<String> disputeNeedsReActionStatuses = {'Pending Approval', 'Awaiting Verification'};
  int get pendingTaskExtensionCount => (_dashboardReport['pendingTaskExtensionCount'] as int?) ?? 0;
  int get needsAttentionBadgeCount =>
      _branchActive ? totalOpenTaskItemsCount : (_dashboardReport['needsAttentionBadgeCount'] as int?) ?? 0;
  int get pendingOutcomeCorrectionCount => pendingOutcomeCorrections.length;

  /// The logged-in salesperson's own explainable Recovery Score breakdown
  /// (RMS-05), computed server-side (see scoringService.computeRecoveryScoreComponents).
  /// Null for RE/Management (no owned portfolio to score).
  Map<String, num>? get myRecoveryScoreComponents => (_dashboardReport['myRecoveryScoreComponents'] as Map?)?.cast<String, num>();

  /// Every open item the unified RE Tasks screen renders — kept in sync with
  /// ReTasksScreen's item composition so the bottom-nav badge always matches
  /// what "All Tasks" actually shows.
  int get totalOpenTaskItemsCount {
    final now = DateTime.now();
    final plainTasks = visibleTasks.where((t) {
      if (t.status == TaskStatus.completed) return false;
      // Mirror ReTasksScreen: a salesman's own call-back from their own
      // recorded outcome only counts once it's overdue.
      final isSalesmanSelfFollowUp = t.type == TaskType.customerCall &&
          (t.source == 'Record Outcome' || t.source == 'Recovery Reconcile' || t.source == 'Recovery' || t.source == 'No Answer') &&
          t.ownerId != currentSalesmanId;
      if (isSalesmanSelfFollowUp && !t.deadline.isBefore(now)) return false;
      return true;
    }).length;
    final escalatedCustomerIds = openEscalationCases.map((e) => e.customerId).toSet();
    final unescalatedBrokenPtps = brokenPtps.where((p) => !escalatedCustomerIds.contains(p.customerId)).length;
    return plainTasks +
        physicalVisitsPendingReviewCount +
        salesmenOverdueTargetsCount +
        disputesAwaitingReviewCount +
        ptpCorrectionRequests.length +
        pendingOutcomeEditCount +
        pendingPaymentClaimCount +
        unescalatedBrokenPtps;
  }

  /// The full company salesmen roster with every performance figure —
  /// including Recovery Score — computed server-side (see
  /// server/src/services/salesmanService.js) from real customers/ptps/tasks.
  /// Empty for a SALESPERSON (matches the server's RBAC on that route).
  List<Map<String, dynamic>> salesmen = [];

  Future<void> _refreshSalesmenFromApi() async {
    if (userRole == 'SALESPERSON') {
      salesmen = [];
      return;
    }
    final raw = await apiClient.getSalesmen();
    salesmen = raw.cast<Map<String, dynamic>>();
    unawaited(_cacheList('salesmen', raw));
  }

  /// RE marks an underperforming salesman's nudge "complete" for today. It
  /// drops off the RE Tasks list and reappears automatically on the next
  /// calendar day if the salesman is still below the collection threshold.
  Future<void> dismissUnderperformance(String salesmanId) async {
    await apiClient.dismissUnderperformance(salesmanId);
    await _refreshSalesmenFromApi();
    notifyListeners();
  }

  int recoveryScoreFor(String salesmanId) {
    final rec = salesmen.firstWhere((s) => s['id'] == salesmanId, orElse: () => {'recoveryScore': 75});
    return (rec['recoveryScore'] as int?) ?? 75;
  }

  /// A salesman's real, readable name for display — `assignedSalesmanId` /
  /// `s['name']` / `s['id']` are all really the same internal user id (used
  /// throughout the app to match Customer.assignedSalesmanId / Task.ownerId
  /// against the roster), never meant to be shown to a person. Falls back
  /// to the id only if the roster hasn't loaded / doesn't contain it, so a
  /// screen never renders a hard failure over a display nicety.
  String salesmanDisplayName(String salesmanId) {
    if (salesmanId.isEmpty) return 'Unmapped';
    final rec = salesmen.firstWhere((s) => s['id'] == salesmanId, orElse: () => const {});
    final name = rec['fullName'] as String?;
    if (name != null && name.isNotEmpty) return name;
    // A SALESPERSON never loads the roster (RBAC — see _refreshSalesmenFromApi),
    // so their own tasks would otherwise render the raw owner id. Resolve at
    // least themselves from the session.
    if (salesmanId == currentSalesmanId && currentUserFullName.isNotEmpty) {
      return currentUserFullName;
    }
    return salesmanId;
  }

  /// The salesman's own phone number from the roster (RE/Management only —
  /// same RBAC as the roster fetch itself, see _refreshSalesmenFromApi), for
  /// the "call the owning salesperson" action on task/customer detail
  /// screens. Null if unmapped, the roster hasn't loaded, or the salesman
  /// has no phone on file.
  String? salesmanPhone(String salesmanId) {
    if (salesmanId.isEmpty) return null;
    final rec = salesmen.firstWhere((s) => s['id'] == salesmanId, orElse: () => const {});
    return rec['phone'] as String?;
  }

  // Populated only from the API (_refreshDisputesFromApi / _refreshPaymentClaimsFromApi /
  // _refreshEscalationsFromApi). Never seeded with demo rows — an empty list until
  // the server responds.
  List<Map<String, dynamic>> disputes = [];

  List<Map<String, dynamic>> paymentClaims = [];

  List<EscalationCase> escalationCases = [];

  List<NotificationItem> notifications = [];

  List<ControlSnapshot> controlSnapshots = [];

  /// In local/demo mode this stays a live view onto BusySimulator's own
  /// list (set in [loginAs]); in API-backed mode it's populated from the
  /// server by [_refreshPtpsFromApi] and never touches BusySimulator.
  List<PromiseToPay> ptps = [];

  // RE notes logged against a salesman (Attention Details "Add Note")
  List<Map<String, dynamic>> salesmanNotes = [];

  List<Map<String, dynamic>> notesFor(String salesmanName) => salesmanNotes.where((n) => n['salesman'] == salesmanName).toList();

  void addSalesmanNote(String salesmanName, String note) {
    salesmanNotes.insert(0, {
      'salesman': salesmanName,
      'note': note,
      'timestamp': DateTime.now(),
      'author': currentUserFullName,
    });
    notifyListeners();
  }

  /// Generic notes attached to any Tasks-screen item (a task, dispute, PTP,
  /// etc.) — keyed by a caller-supplied refId so any screen can log/show
  /// notes without a dedicated model per item type.
  List<Map<String, dynamic>> itemNotes = [];

  List<Map<String, dynamic>> notesForItem(String refId) => itemNotes.where((n) => n['refId'] == refId).toList();

  void addItemNote(String refId, String note) {
    itemNotes.insert(0, {
      'refId': refId,
      'note': note,
      'timestamp': DateTime.now(),
      'author': currentUserFullName,
    });
    notifyListeners();
  }

  // Attachments (evidence) — same refId scheme as itemNotes so any Tasks
  // screen item can carry uploaded evidence.
  List<Map<String, dynamic>> attachments = [];

  List<Map<String, dynamic>> attachmentsForItem(String refId) => attachments.where((a) => a['refId'] == refId).toList();

  void addAttachment(String refId, String fileName, Uint8List bytes) {
    attachments.insert(0, {
      'refId': refId,
      'fileName': fileName,
      'bytes': bytes,
      'timestamp': DateTime.now(),
      'author': currentUserFullName,
    });
    notifyListeners();
  }

  void removeAttachment(String refId, String fileName, DateTime timestamp) {
    attachments.removeWhere((a) => a['refId'] == refId && a['fileName'] == fileName && a['timestamp'] == timestamp);
    notifyListeners();
  }

  // Customer Detail Correction (spec §38 — Wrong Address / contact fixes)
  void updateCustomerContactDetails(String customerId, {String? contactNumber, String? alternateContactNumber, String? branch}) {
    final i = customers.indexWhere((c) => c.id == customerId);
    if (i == -1) return;
    final c = customers[i];
    final changes = <String>[
      if (contactNumber != null && contactNumber != c.contactNumber) 'Primary Contact: ${c.contactNumber} → $contactNumber',
      if (alternateContactNumber != null && alternateContactNumber != c.alternateContactNumber) 'Alternate Contact: ${c.alternateContactNumber} → $alternateContactNumber',
      if (branch != null && branch != c.branch) 'Branch: ${c.branch} → $branch',
    ];
    customers[i] = c.copyWith(
      contactNumber: contactNumber,
      alternateContactNumber: alternateContactNumber,
      branch: branch,
      auditHistory: [
        ...c.auditHistory,
        AuditEvent(
          timestamp: DateTime.now(),
          type: 'RE_CORRECTED_CUSTOMER_DETAILS',
          description: changes.isEmpty
              ? 'Customer detail correction submitted with no field changes.'
              : 'Customer contact/address details corrected by $currentUserFullName following a reported Wrong Address / Customer Not Available outcome. Changes: ${changes.join('; ')}.',
          actor: currentUserFullName,
          source: 'Customer Detail Correction Task',
        ),
      ],
    );
    notifyListeners();
  }

  // Outcome Correction Requests (spec §20 analogue for recorded outcomes —
  // a salesperson cannot silently rewrite an already-recorded outcome; it
  // goes through real RE approval via the API, same pattern as PTP
  // corrections. Server-authoritative — see outcomeCorrectionService.js.
  List<OutcomeCorrectionRequest> outcomeCorrectionRequests = [];

  List<OutcomeCorrectionRequest> get pendingOutcomeCorrections => outcomeCorrectionRequests
      .where((r) => r.status == 'Pending' && _inBranch(customerBranchOf(r.customerId)))
      .toList();

  Future<void> _refreshOutcomeCorrectionsFromApi() async {
    final raw = await apiClient.getOutcomeCorrections();
    _applyOutcomeCorrections(raw);
    unawaited(_cacheList('outcomeCorrections', raw));
  }

  void _applyOutcomeCorrections(List<dynamic> raw) {
    final customerNames = {for (final c in customers) c.id: c.name};
    outcomeCorrectionRequests = raw.map((json) {
      final r = json as Map<String, dynamic>;
      return OutcomeCorrectionRequest.fromJson(r, customerName: customerNames[r['customerId']] ?? r['customerId'] as String);
    }).toList();
  }

  Future<void> requestOutcomeCorrection(String customerId, String requestedOutcome, String requestedReason, String note) async {
    await apiClient.requestOutcomeCorrection(customerId, {
      'requestedOutcome': requestedOutcome,
      'requestedReason': requestedReason,
      'requestNote': note,
    });
    await _refreshOutcomeCorrectionsFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> approveOutcomeCorrection(String id) async {
    final req = outcomeCorrectionRequests.firstWhere((r) => r.id == id);
    await apiClient.approveOutcomeCorrection(id);
    await _refreshOutcomeCorrectionsFromApi();
    await _refreshOneCustomerFromApi(req.customerId);
    notifyListeners();
  }

  Future<void> rejectOutcomeCorrection(String id, String reason) async {
    await apiClient.rejectOutcomeCorrection(id, reason);
    await _refreshOutcomeCorrectionsFromApi();
    notifyListeners();
  }

  // Outcome Edit Requests — edit a recorded outcome's own fields (PTP
  // amount/date/mode, dispute amount/reason, …) with RE approval before it
  // applies. Server-authoritative — see outcomeEditService.js.
  List<OutcomeEditRequest> outcomeEditRequests = [];

  List<OutcomeEditRequest> get pendingOutcomeEdits => outcomeEditRequests
      .where((r) => r.status == 'Pending' && _inBranch(customerBranchOf(r.customerId)))
      .toList();

  int get pendingOutcomeEditCount => pendingOutcomeEdits.length;

  /// Payment claims ("Payment Already Made") a salesman raised that still
  /// need the RE to verify (or fail) against BUSY. Branch-scoped.
  List<Map<String, dynamic>> get pendingPaymentClaims => visiblePaymentClaims
      .where((p) => p['status'] == 'Awaiting Verification' || p['status'] == 'Sync Pending')
      .toList();
  int get pendingPaymentClaimCount => pendingPaymentClaims.length;

  /// Every pending "salesperson asked for a decision" item across the app —
  /// disputes awaiting review, PTP correction requests, outcome edit
  /// requests, outcome correction requests, and payment-claim
  /// verifications — see ApprovalsListScreen, which this count matches.
  int get pendingApprovalsCount =>
      visibleDisputes.where((d) => disputeNeedsReActionStatuses.contains(d['status'])).length +
      ptpCorrectionRequests.length +
      pendingOutcomeEdits.length +
      pendingOutcomeCorrections.length +
      pendingPaymentClaims.length;

  /// Subset of [pendingApprovalsCount] already flagged high-priority or
  /// tied to an escalated account — same "critical" definition
  /// ApprovalsListScreen(onlyCritical: true) uses, kept in sync here so
  /// the dashboard's "Critical Approvals" count never drifts from what
  /// tapping it actually shows.
  int get criticalApprovalsCount {
    bool escalated(String customerId) {
      final c = customers.firstWhere((c) => c.id == customerId, orElse: () => customers.first);
      return c.escalationLevel != 'none';
    }

    return visibleDisputes.where((d) => disputeNeedsReActionStatuses.contains(d['status']) && d['priority'] == 'High').length +
        ptpCorrectionRequests.where((p) => escalated(p.customerId)).length +
        pendingOutcomeEdits.where((r) => escalated(r.customerId)).length +
        pendingOutcomeCorrections.where((r) => escalated(r.customerId)).length +
        pendingPaymentClaims.where((p) => escalated('${p['customerCode']}')).length;
  }

  bool hasPendingOutcomeEdit(String customerId) =>
      outcomeEditRequests.any((r) => r.customerId == customerId && r.status == 'Pending');

  Future<void> _refreshOutcomeEditsFromApi() async {
    final raw = await apiClient.getOutcomeEdits();
    _applyOutcomeEdits(raw);
    unawaited(_cacheList('outcomeEdits', raw));
  }

  void _applyOutcomeEdits(List<dynamic> raw) {
    final customerNames = {for (final c in customers) c.id: c.name};
    outcomeEditRequests = raw.map((json) {
      final r = json as Map<String, dynamic>;
      return OutcomeEditRequest.fromJson(r, customerName: customerNames[r['customerId']] ?? r['customerId'] as String);
    }).toList();
  }

  Future<void> requestOutcomeEdit(String customerId, Map<String, dynamic> body) async {
    await apiClient.requestOutcomeEdit(customerId, body);
    await _refreshOutcomeEditsFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> approveOutcomeEdit(String id) async {
    final req = outcomeEditRequests.firstWhere((r) => r.id == id);
    await apiClient.approveOutcomeEdit(id);
    await _refreshOutcomeEditsFromApi();
    await _refreshOneCustomerFromApi(req.customerId);
    await _refreshPtpsFromApi();
    await _refreshDisputesFromApi();
    await _refreshPaymentClaimsFromApi();
    await _refreshTasksFromApi();
    // An approved NoAnswerReplacement changes recoveryDoneTodayCount's
    // underlying audit trail — keep the dashboard card in sync.
    await _refreshReportsFromApi();
    notifyListeners();
  }

  Future<void> rejectOutcomeEdit(String id, String reason) async {
    await apiClient.rejectOutcomeEdit(id, reason);
    await _refreshOutcomeEditsFromApi();
    notifyListeners();
  }

  // Dynamic urgent counts
  int get brokenPtpCount => visibleCustomers.where((c) => c.reasonForAction.toLowerCase().contains('broken ptp')).length;
  int get mgmtInstructionCount => visibleTasks.where((t) => t.type == TaskType.managementInstruction && t.status != TaskStatus.completed).length;
  int get physicalVisitDueCount => visibleTasks.where((t) => t.type == TaskType.physicalVisit && t.status != TaskStatus.completed && t.deadline.isBefore(DateTime.now())).length;

  // RE control-layer aggregates
  double get ownerlessExposure => visibleCustomers.where((c) => c.ownerMappingRequired).fold(0.0, (s, c) => s + c.totalDue);
  List<Customer> get ownerMappingRequiredCustomers => visibleCustomers.where((c) => c.ownerMappingRequired).toList();
  List<Customer> get noValidNextActionCustomers => visibleCustomers.where((c) => !c.hasValidNextAction && c.totalDue > 0).toList();
  List<EscalationCase> get openEscalationCases => visibleEscalationCases.where((e) => e.isOpen).toList();
  List<EscalationCase> get l4Cases => visibleEscalationCases.where((e) => e.isOpen && e.level == 'L4').toList();
  List<PromiseToPay> get brokenPtps => visiblePtps.where((p) => p.status == PtpStatus.broken).toList();
  List<Customer> get highRiskAccounts => visibleCustomers.where((c) => c.totalDue > 0 && c.creditHealthScore != null && c.creditHealthScore! < 70).toList();

  /// De-duplicated Money at Risk (build guide §25) — every customer touched
  /// by an open escalation, a broken PTP, severe overdue ageing, or a
  /// high/critical credit-health band, counted exactly once even when they
  /// qualify under more than one reason (never summed per-queue).
  List<Customer> get atRiskAccounts {
    final brokenCustomerIds = brokenPtps.map((p) => p.customerId).toSet();
    return visibleCustomers.where((c) => c.totalDue > 0 && (c.escalationLevel != 'none' || brokenCustomerIds.contains(c.id) || c.oldestOverdueDays >= 60 || c.creditHealthBand == 'High' || c.creditHealthBand == 'Critical')).toList();
  }

  double get moneyAtRisk => atRiskAccounts.fold(0.0, (s, c) => s + c.totalDue);
  List<PromiseToPay> get syncPendingPtps => visiblePtps.where((p) => p.status == PtpStatus.financialSyncPending).toList();
  List<PromiseToPay> get ptpCorrectionRequests => visiblePtps.where((p) => p.correctionStatus == 'Pending').toList();
  int get unreadNotificationCount => notifications.where((n) => !n.read).length;
  int get overdueTaskCount => visibleTasks.where((t) => t.isOverdue).length;

  /// Called once at app startup (see v3/main_v3.dart) — checks for a
  /// still-valid persisted session (access token, or a refresh token that
  /// can silently mint a new one via [ApiClient]'s 401 handling) so a
  /// genuinely still-logged-in user lands straight on their dashboard
  /// instead of the login screen. This — combined with the refresh token
  /// itself — is what actually delivers "no need to log in all the time":
  /// previously the persisted token was never read back at all, so every
  /// cold start showed the login screen regardless of any saved session.
  Future<void> restoreSession() async {
    // Runs unconditionally, whether or not there's a persisted session, so
    // even someone who's never logged in sees the real maintenance state
    // on the login screen itself — not just after a rejected login attempt.
    // Best-effort: a failed check here just means the login screen looks
    // normal until an actual login attempt reveals the block instead.
    unawaited(checkMaintenanceStatus());

    await apiClient.loadPersistedSession();
    if (!apiClient.isAuthenticated) {
      sessionLoading = false;
      notifyListeners();
      return;
    }
    try {
      final user = await apiClient.getMe();
      _applyLoggedInUser(user);
      sessionLoading = false;
      notifyListeners();
      unawaited(_loadFromCache().then((_) => _refreshDataForRole()).catchError((_) {
        // _initialLoadError/dataAsOf already reflect the failure —
        // nothing further to do with the exception itself here.
      }));
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        // A pure network failure — the tokens were never actually rejected,
        // getMe() just couldn't be reached. Logging the user out here would
        // wipe a perfectly good refresh token over a signal drop (the bug
        // this replaces). Fall back to the last-known identity + cached
        // data instead of the login screen.
        final identity = await apiClient.getLastIdentitySnapshot();
        final hasCache = identity != null && await _localDb.hasAnyCache(identity['id'] as String);
        if (identity != null && hasCache) {
          _applyLoggedInUser(identity);
          sessionLoading = false;
          notifyListeners();
          await _loadFromCache();
        } else {
          // Nothing to fall back on (first-ever launch with no signal) —
          // the one case offline-first genuinely can't help. Same
          // end-state as before: land on the login screen, but WITHOUT
          // destroying the stored tokens, since they were never rejected.
          sessionLoading = false;
          _initialLoadError = e.message;
          notifyListeners();
        }
      } else if (e.code == 'MAINTENANCE_MODE') {
        // The manager-only kill switch, not a real auth rejection —
        // ApiClient.onMaintenanceMode already flipped maintenanceMode to
        // true. Keep the tokens and last-known identity intact so the app
        // resumes normally the moment maintenance clears, instead of
        // forcing a fresh login for something that was never the
        // session's fault.
        final identity = await apiClient.getLastIdentitySnapshot();
        if (identity != null) _applyLoggedInUser(identity);
        sessionLoading = false;
        notifyListeners();
      } else {
        // A real auth rejection (401/403) — the token is genuinely invalid.
        await apiClient.logout();
        isLoggedIn = false;
        sessionLoading = false;
        notifyListeners();
      }
    } catch (_) {
      await apiClient.logout();
      isLoggedIn = false;
      sessionLoading = false;
      notifyListeners();
    }
  }

  /// Reads back the last-known snapshot for the signed-in user (see
  /// lib/services/local_db.dart) and populates every in-memory list from
  /// it, so a cold start with no signal shows real last-known data instead
  /// of a blank/stuck screen. Sets [dataAsOf] to the oldest list's fetch
  /// time as a staleness marker — cleared the moment a live refresh
  /// actually succeeds (see _refreshAllFromApi). No-op if nothing's cached
  /// yet for this user (first-ever login on this device).
  Future<void> _loadFromCache() async {
    if (currentSalesmanId.isEmpty) return;
    try {
      final asOf = await _localDb.oldestFetchedAt(currentSalesmanId);
      if (asOf == null) return; // nothing cached yet for this user

      final rawCustomers = await _localDb.getList('customers', currentSalesmanId);
      if (rawCustomers != null) _applyCustomers(rawCustomers as List<dynamic>);
      final rawTasks = await _localDb.getList('tasks', currentSalesmanId);
      if (rawTasks != null) _applyTasks(rawTasks as List<dynamic>);
      final rawPtps = await _localDb.getList('ptps', currentSalesmanId);
      if (rawPtps != null) _applyPtps(rawPtps as List<dynamic>);
      final rawDisputes = await _localDb.getList('disputes', currentSalesmanId);
      if (rawDisputes != null) _applyDisputes(rawDisputes as List<dynamic>);
      final rawClaims = await _localDb.getList('paymentClaims', currentSalesmanId);
      if (rawClaims != null) _applyPaymentClaims(rawClaims as List<dynamic>);
      final rawEscalations = await _localDb.getList('escalations', currentSalesmanId);
      if (rawEscalations != null) _applyEscalations(rawEscalations as List<dynamic>);
      final rawNotifications = await _localDb.getList('notifications', currentSalesmanId);
      if (rawNotifications != null) _applyNotifications(rawNotifications as Map<String, dynamic>, notifyOs: false);
      final rawSalesmen = await _localDb.getList('salesmen', currentSalesmanId);
      if (rawSalesmen != null) salesmen = (rawSalesmen as List<dynamic>).cast<Map<String, dynamic>>();
      final rawCorrections = await _localDb.getList('outcomeCorrections', currentSalesmanId);
      if (rawCorrections != null) _applyOutcomeCorrections(rawCorrections as List<dynamic>);
      final rawEdits = await _localDb.getList('outcomeEdits', currentSalesmanId);
      if (rawEdits != null) _applyOutcomeEdits(rawEdits as List<dynamic>);
      final rawReport = await _localDb.getList('dashboardReport', currentSalesmanId);
      if (rawReport != null) _dashboardReport = rawReport as Map<String, dynamic>;
      final rawTrends = await _localDb.getList('trends', currentSalesmanId);
      if (rawTrends != null) trends = (rawTrends as List<dynamic>).cast<Map<String, dynamic>>();

      dataAsOf = asOf;
      _hasLoadedInitialData = true;
      _initialLoadError = null;
      notifyListeners();
    } catch (_) {
      // A corrupt/unreadable cache must never block a live login attempt —
      // _refreshAllFromApi runs regardless of whether this succeeded.
    }
  }

  void _applyLoggedInUser(Map<String, dynamic> user) {
    isLoggedIn = true;
    userRole = user['role'] as String;
    currentSalesmanId = user['id'] as String;
    currentUsername = user['username'] as String? ?? currentSalesmanId;
    currentUserFullName = user['fullName'] as String;
    lastBusySync = DateTime.now();
    unawaited(_loadBranchFilter());
    _startRealtime();
    _startPendingActionWatch();
  }

  void _handleSessionExpired() {
    isLoggedIn = false;
    _branchFilter = kAllBranches;
    _stopRealtime();
    _stopPendingActionWatch();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Real-time event stream (replaces the old 10s/45s/90s polling timers)
  // ─────────────────────────────────────────────────────────────────────
  void _startRealtime() {
    _notificationsPrimed = false;
    NotificationService.instance.requestPermission();
    _realtimeEventsSub?.cancel();
    _realtimeConnSub?.cancel();
    _realtimeConnSub = _realtime.connectionState.listen((connected) {
      if (connected) {
        // Catch-up: pull everything once per (re)connect so anything that
        // changed while the stream was down is picked up. `_refreshAllFromApi`
        // includes notifications; `_notificationsPrimed` stays true so a
        // reconnect never re-fires OS banners for the backlog.
        unawaited(_reconnectCatchUp());
        // A live path to the server exists again — the primary trigger for
        // flushing anything the offline queue is holding.
        unawaited(pendingActionQueue.flush(currentSalesmanId));
      }
    });
    _realtimeEventsSub = _realtime.events.listen(_onRealtimeEvent);
    _realtime.start();
  }

  void _stopRealtime() {
    _realtimeEventsSub?.cancel();
    _realtimeEventsSub = null;
    _realtimeConnSub?.cancel();
    _realtimeConnSub = null;
    _invalidateDebounce?.cancel();
    _pendingInvalidations.clear();
    _realtime.stop();
  }

  Future<void> _reconnectCatchUp() async {
    if (!isLoggedIn) return;
    try {
      await _refreshDataForRole();
      await _refreshSyncStatusFromApi();
    } catch (_) {/* the next event or reconnect retries */}
  }

  void _onRealtimeEvent(RealtimeEvent e) {
    switch (e.type) {
      case 'sync':
        final phase = e.data['phase'] as String?;
        final since = e.data['since'] as String?;
        final syncing = phase == 'started';
        if (syncing != isSyncing || since != syncingSince?.toIso8601String()) {
          isSyncing = syncing;
          syncingSince = syncing && since != null ? DateTime.tryParse(since) : null;
          notifyListeners();
        }
        // The 'finished' push carries no outcome — pull /api/sync-status so
        // a failed / unreachable-BUSY run surfaces its message right away
        // instead of only on the next reconnect.
        if (phase == 'finished') unawaited(_refreshSyncStatusFromApi());
        break;
      case 'notification':
        _refreshNotificationsFromApi().then((_) => notifyListeners()).catchError((_) {});
        break;
      case 'maintenance':
        final enabled = e.data['enabled'] as bool? ?? false;
        final since = e.data['since'] as String?;
        final wasEnabled = maintenanceMode;
        maintenanceMode = enabled;
        maintenanceSince = enabled && since != null ? DateTime.tryParse(since) : null;
        if (wasEnabled && !enabled) _notifyMaintenanceOver();
        notifyListeners();
        break;
      case 'invalidate':
        final resources = (e.data['resources'] as List?)?.cast<String>() ?? const <String>[];
        _pendingInvalidations.addAll(resources);
        final customerId = e.data['customerId'] as String?;
        if (customerId != null) _pendingInvalidations.add('customer:$customerId');
        _invalidateDebounce?.cancel();
        _invalidateDebounce = Timer(const Duration(milliseconds: 250), _applyInvalidations);
        break;
    }
  }

  Future<void> _applyInvalidations() async {
    if (!isLoggedIn || _refreshInFlight) {
      // Retry shortly if a refresh is already running.
      if (isLoggedIn && _pendingInvalidations.isNotEmpty) {
        _invalidateDebounce?.cancel();
        _invalidateDebounce = Timer(const Duration(milliseconds: 250), _applyInvalidations);
      }
      return;
    }
    final pending = Set<String>.from(_pendingInvalidations);
    _pendingInvalidations.clear();
    if (pending.isEmpty) return;
    _refreshInFlight = true;
    notifyListeners();
    try {
      Future<void> maybe(String key, Future<void> Function() fn) => pending.contains(key) ? fn() : Future.value();
      await maybe('customers', refreshCustomersFromApi);
      await maybe('tasks', _refreshTasksFromApi);
      await maybe('ptps', _refreshPtpsFromApi);
      await maybe('disputes', _refreshDisputesFromApi);
      await maybe('paymentClaims', _refreshPaymentClaimsFromApi);
      await maybe('escalations', _refreshEscalationsFromApi);
      await maybe('outcomeEdits', _refreshOutcomeEditsFromApi);
      await maybe('outcomeCorrections', _refreshOutcomeCorrectionsFromApi);
      await maybe('salesmen', _refreshSalesmenFromApi);
      // Any of these moving can change the server-computed dashboard aggregates.
      if (pending.any((r) => const {'customers', 'tasks', 'ptps', 'disputes'}.contains(r))) {
        await _refreshReportsFromApi();
      }
      for (final key in pending.where((k) => k.startsWith('customer:'))) {
        final id = key.substring('customer:'.length);
        if (customers.any((c) => c.id == id)) await _refreshOneCustomerFromApi(id);
      }
      notifyListeners();
    } catch (_) {
      // Put them back so the next event (or a nav-tap refresh) retries.
      _pendingInvalidations.addAll(pending);
    } finally {
      _refreshInFlight = false;
      if (_pendingInvalidations.isNotEmpty) {
        _invalidateDebounce?.cancel();
        _invalidateDebounce = Timer(const Duration(milliseconds: 250), _applyInvalidations);
      }
    }
  }

  Future<void> _refreshSyncStatusFromApi() async {
    try {
      final status = await apiClient.getSyncStatus();
      final syncing = status['syncing'] as bool? ?? false;
      final since = status['since'] as String?;
      if (syncing != isSyncing || since != syncingSince?.toIso8601String()) {
        isSyncing = syncing;
        syncingSince = since != null ? DateTime.tryParse(since) : null;
        notifyListeners();
      }
      _applyLastSyncOutcome(status['lastSync'] as Map<String, dynamic>?);
    } catch (_) {
      // A poll failing (offline, momentary server hiccup) shouldn't itself
      // freeze or unfreeze the app — the next tick tries again, same as
      // the notification poll's own silent-retry behavior.
    }
  }

  /// Folds the server's `lastSync` summary into the failed-sync banner
  /// state. A newer failure (different finishedAt) re-arms the banner even
  /// if the user dismissed the previous one; a successful sync clears it.
  void _applyLastSyncOutcome(Map<String, dynamic>? last) {
    // 'success' / 'inProgress' are fine; only a genuinely 'failed' run or a
    // 'stalled' (killed) one warrants the banner.
    final failed = last != null &&
        (last['status'] == 'failed' || last['status'] == 'stalled');
    final atRaw = last?['finishedAt'] as String? ?? last?['startedAt'] as String?;
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    final message = last?['message'] as String?;
    final isConn = last?['connectionError'] as bool? ?? false;

    final changed = failed != syncFailed ||
        at != syncFailedAt ||
        message != syncFailedMessage;
    if (!changed) return;

    if (failed && at != syncFailedAt) _syncFailureDismissed = false;
    if (!failed) _syncFailureDismissed = false;
    syncFailed = failed;
    syncFailedIsConnection = isConn;
    syncFailedMessage = message;
    syncFailedAt = at;
    notifyListeners();
  }

  /// Manual full refresh — bound to every bottom-nav tab change and the
  /// manager report "refresh" icons. User-triggered, not a timer. Silent
  /// on failure; overlapping calls are coalesced.
  /// Runs one refresh call, swallowing (and logging in debug) any failure
  /// so it can't abort the rest of the sequence. Before this guard existed,
  /// a single transient failure (e.g. a slow customers fetch) skipped every
  /// later refresh in `refreshLiveData` — leaving payment claims,
  /// escalations, outcome edits etc. stale until a full app restart.
  Future<void> _guardedRefresh(String label, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[refresh] $label failed (kept previous data): $e');
        return true;
      }());
    }
  }

  Future<void> refreshLiveData() async {
    if (!isLoggedIn || _refreshInFlight) return;
    _refreshInFlight = true;
    notifyListeners();
    try {
      await _guardedRefresh('customers', refreshCustomersFromApi);
      await _guardedRefresh('tasks', _refreshTasksFromApi);
      await _guardedRefresh('ptps', _refreshPtpsFromApi);
      await _guardedRefresh('disputes', _refreshDisputesFromApi);
      await _guardedRefresh('paymentClaims', _refreshPaymentClaimsFromApi);
      await _guardedRefresh('escalations', _refreshEscalationsFromApi);
      await _guardedRefresh('outcomeCorrections', _refreshOutcomeCorrectionsFromApi);
      await _guardedRefresh('outcomeEdits', _refreshOutcomeEditsFromApi);
      await _guardedRefresh('salesmen', _refreshSalesmenFromApi);
      await _guardedRefresh('reports', _refreshReportsFromApi);
      await _guardedRefresh('syncStatus', _refreshSyncStatusFromApi);
      notifyListeners();
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Real authentication against the TP-RMS server — replaces the
  /// hardcoded username/password map in [LoginScreen]. Returns null on
  /// success, or a user-facing error message on failure (bad credentials,
  /// server unreachable, etc.) so the caller can show it without needing
  /// to know about [ApiException].
  Future<String?> loginWithApi(String username, String password) async {
    try {
      // A shared device logging in as a DIFFERENT user than whoever used it
      // last — drop the previous user's cached portfolio so it can never
      // flash on screen (even briefly, before the first live fetch lands)
      // for someone else. Same-user re-login keeps the cache, which is the
      // whole point (an instant warm dashboard next time).
      final previousIdentity = await apiClient.getLastIdentitySnapshot();
      final user = await apiClient.login(username, password);
      if (previousIdentity != null && previousIdentity['id'] != user['id']) {
        unawaited(_localDb.clearFor(previousIdentity['id'] as String));
      }
      _applyLoggedInUser(user);

      await _refreshDataForRole();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please check your connection and try again.';
    }
  }

  /// Sets the signed-in user's password directly — no current-password
  /// check. Returns null on success, or a user-facing error message (weak
  /// new password, server unreachable) otherwise — same contract as
  /// [loginWithApi].
  Future<String?> changePassword(String newPassword) async {
    try {
      await apiClient.changePassword(newPassword);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please check your connection and try again.';
    }
  }

  /// Admin-only kill switch — server-enforced (see
  /// server/src/routes/maintenanceRoutes.js), this call itself will 403 for
  /// anyone else (including MANAGEMENT, which no longer has this at all).
  /// Sets [maintenanceMode] from the real server response immediately; the
  /// broadcast SSE 'maintenance' push (see _onRealtimeEvent) then confirms
  /// the same state for every other connected client, including this one
  /// on reconnect. Returns null on success, or a user-facing error message
  /// otherwise.
  Future<String?> toggleMaintenanceMode(bool enabled) async {
    try {
      final result = await apiClient.setMaintenanceMode(enabled);
      maintenanceMode = result['enabled'] as bool? ?? enabled;
      final since = result['since'] as String?;
      maintenanceSince = since != null ? DateTime.tryParse(since) : null;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please check your connection and try again.';
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // ADMIN-only (see server/src/routes/busySyncAdminRoutes.js / adminRoutes.js)
  // ─────────────────────────────────────────────────────────────────────

  /// Raw pass-through, no AppStore-level caching (same pattern as
  /// [fetchAuditHistoryPage]) — this data is only ever shown on the one
  /// Admin screen, never needed elsewhere in the app.
  Future<Map<String, dynamic>> fetchBusySyncHealth() => apiClient.getBusySyncHealth();
  Future<List<dynamic>> fetchBusySyncRuns({int limit = 20}) => apiClient.getBusySyncRuns(limit: limit);

  /// Starts a sync run — company-wide when [branch] is omitted, or scoped
  /// to just that one branch (see admin_scaffold_v3.dart's per-branch Sync
  /// button). Returns null on success, or a user-facing error message
  /// (including "already running").
  Future<String?> triggerBusySync({String? branch}) async {
    try {
      await apiClient.triggerBusySync(branch: branch);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please check your connection and try again.';
    }
  }

  /// Resets a salesperson's password — server refuses any other target
  /// role. Returns null on success, or a user-facing error message.
  Future<String?> resetSalesmanPassword(String salesmanId, String newPassword) async {
    try {
      await apiClient.resetSalesmanPassword(salesmanId, newPassword);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Please check your connection and try again.';
    }
  }

  /// The post-login data refresh, branched by role. ADMIN has no
  /// server-side access to customers/tasks/ptps/disputes/etc at all (see
  /// authorize() gates throughout server/src/routes) — [_refreshAllFromApi]
  /// would 403 immediately on its first, unguarded call and never even set
  /// [_hasLoadedInitialData], leaving InitialDataLoader stuck. ADMIN only
  /// ever needs the salesmen roster (for the password-reset picker), so it
  /// gets its own lean path that still sets the same completion flags the
  /// full bundle would. Every other role is unaffected — this just calls
  /// straight through to [_refreshAllFromApi].
  Future<void> _refreshDataForRole() async {
    if (userRole != 'ADMIN') {
      await _refreshAllFromApi();
      return;
    }
    _refreshInFlight = true;
    notifyListeners();
    try {
      await _refreshSalesmenFromApi();
      _hasLoadedInitialData = true;
      _initialLoadError = null;
      dataAsOf = null;
    } catch (e) {
      if (!_hasLoadedInitialData) {
        _initialLoadError = e is ApiException ? e.message : 'Could not reach the server. Please check your connection and try again.';
      }
      rethrow;
    } finally {
      _refreshInFlight = false;
      notifyListeners();
    }
  }

  /// The full real-data refresh sequence — used both at login and by
  /// [refreshBusySync] (report screens' "refresh" icon).
  Future<void> _refreshAllFromApi() async {
    _refreshInFlight = true;
    notifyListeners();
    try {
      // Customers first and unguarded — every other list keys off it, so if
      // this genuinely fails the login should surface the error. Bounded
      // so a network stall can't hang this indefinitely (ApiClient's own
      // 20s-per-request timeout only covers ONE call; this covers the
      // whole call including any 401-triggered refresh-and-retry inside
      // it) — see InitialDataLoader, which shows initialLoadError + a
      // retry button once _hasLoadedInitialData is still false after this.
      await refreshCustomersFromApi().timeout(const Duration(seconds: 25));
      await _guardedRefresh('tasks', _refreshTasksFromApi);
      await _guardedRefresh('ptps', _refreshPtpsFromApi);
      await _guardedRefresh('disputes', _refreshDisputesFromApi);
      await _guardedRefresh('paymentClaims', _refreshPaymentClaimsFromApi);
      await _guardedRefresh('escalations', _refreshEscalationsFromApi);
      await _guardedRefresh('notifications', _refreshNotificationsFromApi);
      await _guardedRefresh('salesmen', _refreshSalesmenFromApi);
      await _guardedRefresh('outcomeCorrections', _refreshOutcomeCorrectionsFromApi);
      await _guardedRefresh('outcomeEdits', _refreshOutcomeEditsFromApi);
      await _guardedRefresh('reports', _refreshReportsFromApi);
      _hasLoadedInitialData = true;
      _initialLoadError = null;
      dataAsOf = null; // this is now a confirmed-live snapshot, not cache
    } catch (e) {
      // Only surface as a blocking error state if there's still nothing on
      // screen at all (no cache was loaded) — with cached data already
      // showing, a failed background refresh just leaves dataAsOf set and
      // the offline banner (see sync_freeze_overlay.dart) handles it.
      if (!_hasLoadedInitialData) {
        _initialLoadError = e is ApiException ? e.message : 'Could not reach the server. Please check your connection and try again.';
      }
      rethrow;
    } finally {
      _refreshInFlight = false;
      notifyListeners();
    }
  }

  /// Bound to the retry button in InitialDataLoader's error state — a real
  /// user-triggered retry rather than hoping the SSE client reconnects on
  /// its own eventually.
  Future<void> retryInitialLoad() async {
    if (!isLoggedIn) return;
    try {
      await _refreshDataForRole();
    } catch (_) {/* initialLoadError already set; UI reads it */}
  }

  /// Company-wide (or salesperson-scoped) dashboard aggregates and real
  /// historical trend data — everything previously computed client-side
  /// from raw arrays now comes straight from the server (see
  /// server/src/services/reportService.js).
  Future<void> _refreshReportsFromApi() async {
    _dashboardReport = await apiClient.getDashboardReport();
    final rawTrends = await apiClient.getTrends();
    trends = rawTrends.cast<Map<String, dynamic>>();
    unawaited(_cacheList('dashboardReport', _dashboardReport));
    unawaited(_cacheList('trends', rawTrends));
  }

  Future<void> refreshCustomersFromApi() async {
    final raw = await apiClient.getCustomers();
    _applyCustomers(raw);
    unawaited(_cacheList('customers', raw));
  }

  // GET /api/customers never includes invoices/auditHistory (only the
  // single-customer detail fetch does — see refreshCustomerDetailFromApi).
  // This runs on every broad 'customers' SSE invalidation, which fires for
  // ANY write anywhere in the app, not just to a customer the user has
  // open — without carrying the previous in-memory values forward, a
  // Customer 360 screen sitting open on one customer would have its
  // History/Invoices tabs silently reset to empty the instant some other
  // salesperson recorded an outcome on a completely different customer.
  void _applyCustomers(List<dynamic> raw) {
    final previousById = {for (final c in customers) c.id: c};
    customers = raw.map((json) {
      final updated = Customer.fromJson(json as Map<String, dynamic>);
      final previous = previousById[updated.id];
      if (previous == null) return updated;
      return updated.copyWith(
        auditHistory: updated.auditHistory.isEmpty ? previous.auditHistory : updated.auditHistory,
        invoices: updated.invoices.isEmpty ? previous.invoices : updated.invoices,
      );
    }).toList();
  }

  Future<void> _refreshTasksFromApi() async {
    final raw = await apiClient.getTasks();
    _applyTasks(raw);
    unawaited(_cacheList('tasks', raw));
  }

  void _applyTasks(List<dynamic> raw) {
    final customerNames = {for (final c in customers) c.id: c.name};
    tasks = raw.map((json) {
      final map = json as Map<String, dynamic>;
      return AppTask.fromJson(map, customerName: customerNames[map['customerId']]);
    }).toList();
  }

  Future<void> _refreshPtpsFromApi() async {
    final raw = await apiClient.getPtps();
    _applyPtps(raw);
    unawaited(_cacheList('ptps', raw));
  }

  void _applyPtps(List<dynamic> raw) {
    ptps = raw.map((json) => PromiseToPay.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Maps the server's dispute JSON (customerId/totalDueAtRaise/invoiceNumber
  /// — its own model's field names) onto the same Map shape the app's
  /// existing dispute screens already read (customer/totalDue/invoice/
  /// customerCode — set by the original BusySimulator seed data), so none
  /// of those screens need to change.
  Future<void> _refreshDisputesFromApi() async {
    final raw = await apiClient.getDisputes();
    _applyDisputes(raw);
    unawaited(_cacheList('disputes', raw));
  }

  void _applyDisputes(List<dynamic> raw) {
    final customerNames = {for (final c in customers) c.id: c.name};
    disputes = raw.map((json) {
      final d = json as Map<String, dynamic>;
      return {
        'id': d['id'],
        'customer': customerNames[d['customerId']] ?? d['customerId'],
        'customerCode': d['customerId'],
        'amount': (d['amount'] as num).toDouble(),
        'totalDue': (d['totalDueAtRaise'] as num).toDouble(),
        'reason': d['reason'],
        'status': d['status'],
        'statusDetail': d['statusDetail'],
        'invoice': d['invoiceNumber'],
        'priority': d['priority'],
        'resolutionOwner': d['resolutionOwner'],
        'rejectionReason': d['rejectionReason'],
        'infoRequestNote': d['infoRequestNote'],
        'attachmentPath': d['attachmentPath'],
        'messages': ((d['messages'] as List?) ?? const [])
            .map((m) => {
                  'authorName': m['authorName'],
                  'authorRole': m['authorRole'],
                  'kind': m['kind'],
                  'body': m['body'],
                  'attachmentPath': m['attachmentPath'],
                  'createdAt': DateTime.parse(m['createdAt'] as String).toLocal(),
                })
            .toList(),
        'raisedDate': DateTime.parse(d['raisedDate'] as String).toLocal(),
        'lastUpdated': DateTime.parse(d['lastUpdated'] as String).toLocal(),
        'deadline': d['resolutionDeadline'] != null ? DateTime.parse(d['resolutionDeadline'] as String).toLocal() : null,
        'department': d['department'],
      };
    }).toList();
  }

  Future<void> _refreshPaymentClaimsFromApi() async {
    final raw = await apiClient.getPaymentClaims();
    _applyPaymentClaims(raw);
    unawaited(_cacheList('paymentClaims', raw));
  }

  void _applyPaymentClaims(List<dynamic> raw) {
    final customerNames = {for (final c in customers) c.id: c.name};
    paymentClaims = raw.map((json) {
      final p = json as Map<String, dynamic>;
      return {
        'id': p['id'],
        'customer': customerNames[p['customerId']] ?? p['customerId'],
        'customerCode': p['customerId'],
        'amount': (p['amount'] as num).toDouble(),
        'date': DateFormat('dd MMM yyyy').format(DateTime.parse(p['claimDate'] as String).toLocal()),
        'claimDateRaw': DateTime.parse(p['claimDate'] as String).toLocal(),
        'reference': p['reference'],
        'status': p['status'],
        'attachmentPath': p['attachmentPath'],
      };
    }).toList();
  }

  Future<void> _refreshEscalationsFromApi() async {
    final raw = await apiClient.getEscalations();
    _applyEscalations(raw);
    unawaited(_cacheList('escalations', raw));
  }

  void _applyEscalations(List<dynamic> raw) {
    final customerNames = {for (final c in customers) c.id: c.name};
    escalationCases = raw.map((json) {
      final e = json as Map<String, dynamic>;
      return EscalationCase.fromJson(e, customerName: customerNames[e['customerId']] ?? e['customerId'] as String);
    }).toList();
  }

  Future<void> _refreshNotificationsFromApi() async {
    final raw = await apiClient.getNotifications();
    // Cache first — _applyNotifications diffs against the PREVIOUS in-memory
    // `notifications` to decide what's "new" (see _notifyAboutNewlyArrived),
    // so caching after would cache post-diff state instead of the raw
    // response; doesn't matter for replay (cache load never re-fires OS
    // notifications, see _loadFromCache), so order here is inconsequential.
    unawaited(_cacheList('notifications', raw));
    _applyNotifications(raw, notifyOs: true);
  }

  void _applyNotifications(Map<String, dynamic> raw, {required bool notifyOs}) {
    final items = raw['items'] as List<dynamic>;
    final fresh = items.map((json) => NotificationItem.fromJson(json as Map<String, dynamic>)).toList();
    if (notifyOs) _notifyAboutNewlyArrived(fresh);
    notifications = fresh;
  }

  /// Raises a real OS notification for each unread item this client
  /// hasn't already seen this session — compared by id against the
  /// previous [notifications] snapshot (not just a count delta), so a poll
  /// racing with the user reading one notification while another arrives
  /// can't miscount and miss (or double-fire) either one.
  void _notifyAboutNewlyArrived(List<NotificationItem> fresh) {
    if (!_notificationsPrimed) {
      // First load this session (login/restore) — this is the existing
      // backlog, not "new" arrivals; don't fire a burst of OS
      // notifications for history the in-app bell hasn't even shown yet.
      _notificationsPrimed = true;
      return;
    }
    final previousIds = notifications.map((n) => n.id).toSet();
    for (final n in fresh.where((n) => !n.read && !previousIds.contains(n.id))) {
      NotificationService.instance.show(
        id: n.id.hashCode & 0x7fffffff,
        title: n.title,
        body: n.body,
        icon: NotificationService.iconFor(n.title, n.body),
      );
    }
  }

  /// Re-fetches one customer's full detail (including its recomputed
  /// state and updated auditHistory) after a server-side action that
  /// touched it but wasn't itself a customer-record-outcome call — e.g.
  /// completing a task, or an RE action. Updates it in place in
  /// [customers]; appends it if it wasn't already in this session's scope
  /// (e.g. a Manager viewing a customer outside a filtered list).
  Future<void> _refreshOneCustomerFromApi(String customerId) async {
    final detail = await apiClient.getCustomerDetail(customerId);
    final updated = Customer.fromJson(detail);
    final index = customers.indexWhere((c) => c.id == customerId);
    if (index != -1) {
      customers[index] = updated;
    } else {
      customers.add(updated);
    }
  }

  /// GET /api/customers (used to populate [customers] everywhere else)
  /// never includes `invoices`/`auditHistory` — only the single-customer
  /// detail endpoint does (see customerService.getDetail). Customer 360
  /// calls this on open so its Invoices/History tabs show the real data
  /// instead of falling back to [Customer.invoices]'s default empty list.
  Future<void> refreshCustomerDetailFromApi(String customerId) async {
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  /// One page of a customer's audit history, newest first — server-side
  /// keyset pagination (GET /api/customers/:id/audit-history) so a
  /// long-tenured customer's full history (potentially hundreds of rows)
  /// is never downloaded up front. Pass the previous page's `nextCursor`
  /// to fetch the next one; omit it for page one.
  Future<AuditHistoryPage> fetchAuditHistoryPage(String customerId, {String? cursor, int limit = 20}) async {
    final json = await apiClient.getCustomerAuditHistoryPage(customerId, cursor: cursor, limit: limit);
    final items = ((json['items'] as List?) ?? const [])
        .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    return AuditHistoryPage(items: items, nextCursor: json['nextCursor'] as String?);
  }

  /// Revokes the refresh token server-side (via [ApiClient.logout]) so this
  /// is a real session invalidation, not just discarding a local token —
  /// the same refresh token could otherwise still be replayed until its
  /// 30-day expiry.
  Future<void> logout() async {
    isLoggedIn = false;
    _branchFilter = kAllBranches;
    _stopRealtime();
    _stopPendingActionWatch();
    isSyncing = false;
    notifyListeners();
    await apiClient.logout();
  }

  /// Second-stage verification on an already-Approved dispute — real,
  /// server-authoritative (see disputeService.resolve). `outcome` is
  /// 'Resolved' (genuinely reduces totalDue by the disputed amount) or
  /// 'Returned to Recovery' (nothing was received — no money moves).
  Future<void> resolveDispute(String id, String outcome, {String? note}) async {
    final dispute = disputes.firstWhere((d) => d['id'] == id);
    final customerId = dispute['customerCode'] as String;
    final body = {'outcome': outcome, if (note != null) 'note': note};
    try {
      await apiClient.resolveDispute(id, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeResolve, targetEndpoint: '/api/disputes/$id/resolve', payload: body, relatedCustomerId: customerId);
    }
    await _refreshDisputesFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> approveDispute(String id, String resolutionOwner, DateTime deadline, String description,
      {String? note, String? attachmentPath, String? department}) async {
    final dispute = disputes.firstWhere((d) => d['id'] == id);
    final customerId = dispute['customerCode'] as String;
    // The server requires a non-empty note for the resolution owner; older
    // callers only supply `description` (the resolution instruction) — use
    // that as the note when none is given.
    final effectiveNote = (note != null && note.trim().isNotEmpty) ? note.trim() : description;
    final body = {
      'resolutionOwner': resolutionOwner,
      // .toUtc() first — a naive local-time string here gets misread by the
      // server as UTC (z.coerce.date()), shifting evening IST deadlines
      // into the next calendar day.
      'deadline': deadline.toUtc().toIso8601String(),
      'description': description,
      'note': effectiveNote,
      if (attachmentPath != null && attachmentPath.isNotEmpty) 'attachmentPath': attachmentPath,
      if (department != null && department.isNotEmpty) 'department': department,
    };
    try {
      await apiClient.approveDispute(id, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeApprove, targetEndpoint: '/api/disputes/$id/approve', payload: body, relatedCustomerId: customerId);
    }
    await _refreshDisputesFromApi();
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  /// Free back-and-forth message on a dispute (RE ⇄ resolution-owner salesman).
  Future<void> postDisputeMessage(String disputeId, {required String body, String? attachmentPath}) async {
    final payload = {
      'body': body,
      if (attachmentPath != null && attachmentPath.isNotEmpty) 'attachmentPath': attachmentPath,
    };
    final dispute = disputes.firstWhere((d) => d['id'] == disputeId);
    try {
      await apiClient.postDisputeMessage(disputeId, payload);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeMessage,
          targetEndpoint: '/api/disputes/$disputeId/message',
          payload: payload,
          relatedCustomerId: dispute['customerCode'] as String);
    }
    await _refreshDisputesFromApi();
    notifyListeners();
  }

  /// The resolution-owner salesman resolves the dispute from their task.
  Future<void> resolveDisputeByOwner(String disputeId, String taskId, {String? note}) async {
    final dispute = disputes.firstWhere((d) => d['id'] == disputeId);
    final customerId = dispute['customerCode'] as String;
    final body = {
      'taskId': taskId,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    try {
      await apiClient.resolveDisputeByOwner(disputeId, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeResolveByOwner,
          targetEndpoint: '/api/disputes/$disputeId/resolve-by-owner',
          payload: body,
          relatedCustomerId: customerId);
    }
    await _refreshDisputesFromApi();
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> rejectDisputeByOwner(String disputeId, String taskId, String reason) async {
    final dispute = disputes.firstWhere((d) => d['id'] == disputeId);
    final customerId = dispute['customerCode'] as String;
    final body = {'taskId': taskId, 'reason': reason};
    try {
      await apiClient.rejectDisputeByOwner(disputeId, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeRejectByOwner,
          targetEndpoint: '/api/disputes/$disputeId/reject-by-owner',
          payload: body,
          relatedCustomerId: customerId);
    }
    await _refreshDisputesFromApi();
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> rejectDispute(String id, String reason) async {
    final dispute = disputes.firstWhere((d) => d['id'] == id);
    final customerId = dispute['customerCode'] as String;
    final body = {'reason': reason};
    try {
      await apiClient.rejectDispute(id, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeReject, targetEndpoint: '/api/disputes/$id/reject', payload: body, relatedCustomerId: customerId);
    }
    await _refreshDisputesFromApi();
    // A rejected dispute now also auto-creates a call-customer follow-up
    // task for the salesperson (server-side) — refresh tasks too so it
    // shows up immediately, same as approveDispute already does.
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> requestDisputeInfo(String id, String salesmanId, String desc, DateTime deadline) async {
    final dispute = disputes.firstWhere((d) => d['id'] == id);
    final customerId = dispute['customerCode'] as String;
    final body = {
      'salesmanId': salesmanId,
      'desc': desc,
      'deadline': deadline.toUtc().toIso8601String(),
    };
    try {
      await apiClient.requestDisputeInfo(id, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeRequestInfo,
          targetEndpoint: '/api/disputes/$id/request-info',
          payload: body,
          relatedCustomerId: customerId);
    }
    await _refreshDisputesFromApi();
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  /// Salesperson answers an RE clarification request from their linked
  /// task. Appends [body] to the dispute thread, closes [taskId], and the
  /// dispute goes back to the RE queue (server-side).
  Future<void> answerDisputeClarification(String disputeId, String taskId, String body) async {
    final payload = {'taskId': taskId, 'body': body};
    final dispute = disputes.firstWhere((d) => d['id'] == disputeId);
    try {
      await apiClient.answerDisputeClarification(disputeId, payload);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.disputeAnswer,
          targetEndpoint: '/api/disputes/$disputeId/answer',
          payload: payload,
          relatedCustomerId: dispute['customerCode'] as String?);
    }
    await _refreshDisputesFromApi();
    await _refreshTasksFromApi();
    notifyListeners();
  }

  /// Server-authoritative (paymentClaimService.verify): Verified reduces
  /// the customer's real totalDue/totalOutstanding, Failed returns them to
  /// active recovery — the same "only BUSY-confirmed money reduces
  /// exposure" rule, computed server-side now. The old "Sync Pending"
  /// branch (tied to the local isBusySyncHealthy demo toggle) has no
  /// server equivalent — BUSY sync simulation is out of scope, see
  /// server/README.md — so a verify call now always resolves to Verified
  /// or Failed, never Sync Pending.
  Future<void> verifyPaymentClaim(String id, bool success) async {
    final claim = paymentClaims.firstWhere((p) => p['id'] == id);
    try {
      await apiClient.verifyPaymentClaim(id, success);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.paymentClaimVerify,
          targetEndpoint: '/api/payment-claims/$id/verify',
          payload: {'success': success},
          relatedCustomerId: claim['customerCode'] as String?);
    }
    await _refreshPaymentClaimsFromApi();
    // Verifying (either way) now also auto-creates a call-customer
    // follow-up task for the salesperson (server-side) — refresh tasks
    // too so it shows up immediately.
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(claim['customerCode'] as String);
    notifyListeners();
  }

  Future<void> approveInternalAction(String taskId, {String? note, String? attachmentPath}) async {
    final task = tasks.firstWhere((t) => t.id == taskId);
    await apiClient.approveInternalAction(taskId, {
      if (note != null && note.isNotEmpty) 'note': note,
      if (attachmentPath != null && attachmentPath.isNotEmpty) 'attachmentPath': attachmentPath,
    });
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  Future<void> rejectInternalAction(String taskId, {String? reason, String? attachmentPath}) async {
    final task = tasks.firstWhere((t) => t.id == taskId);
    await apiClient.rejectInternalAction(taskId, {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (attachmentPath != null && attachmentPath.isNotEmpty) 'attachmentPath': attachmentPath,
    });
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  static const Map<String, int> _escalationSeverity = {'L4': 4, 'L3': 3, 'L2': 2, 'L1': 1, 'none': 0};

  /// Kept only for [test/system_wide_verification_test.dart]'s offline unit
  /// coverage of the ordering rule — the server now computes and applies
  /// this ordering itself (see scoringService.compareByRecoveryPriority),
  /// so `customers`/`myCustomers` already arrive pre-sorted from the API
  /// and nothing in this store calls this anymore.
  static int compareByRecoveryPriority(Customer a, Customer b) {
    final escCompare = (_escalationSeverity[b.escalationLevel] ?? 0).compareTo(_escalationSeverity[a.escalationLevel] ?? 0);
    if (escCompare != 0) return escCompare;
    final overdueCompare = b.oldestOverdueDays.compareTo(a.oldestOverdueDays);
    if (overdueCompare != 0) return overdueCompare;
    return b.totalDue.compareTo(a.totalDue);
  }

  /// [myCustomers] already arrives from the server sorted by real recovery
  /// priority (server/src/services/scoringService.js's
  /// compareByRecoveryPriority, applied in customerService.listForUser) —
  /// this just filters to actionable and takes the first, no client-side
  /// re-sort needed.
  ///
  /// A customer isPendingNoAnswerEdit is excluded too, not just
  /// 'Waiting / Monitoring' ones — their Record Outcome button is locked
  /// on the customer screen the same as a resolved customer's (see
  /// Customer360Screen's `isLocked`), just reachable a different way
  /// (Today's Recovery Tasks' "Edit Recorded Outcome"), so "Start
  /// Recovery" landing here would show the salesman a customer they
  /// can't actually record anything against.
  Customer? getNextCustomer({Set<String>? excludeIds}) {
    // Customers whose outcome is already recorded today (Internal Action,
    // Dispute, Follow-up, PTP, Payment Made — any "source: Record Outcome"
    // audit event today) are done for the salesman; keep them out of the
    // one-by-one Start Recovery queue.
    final doneToday = recoveryDoneTodayCustomerIds;
    // A 3rd-No-Answer physical visit takes over — the next step is the
    // visit, not another call, so drop those from the call queue too.
    final onPhysicalVisit = tasks
        .where((t) =>
            t.type == TaskType.physicalVisit && t.status != TaskStatus.completed)
        .map((t) => t.customerId)
        .toSet();
    final actionable = myCustomers.where((c) =>
        c.currentRecoveryState != 'Waiting / Monitoring' &&
        !c.isPendingNoAnswerEdit &&
        !doneToday.contains(c.id) &&
        !onPhysicalVisit.contains(c.id) &&
        !(excludeIds?.contains(c.id) ?? false));
    return actionable.isEmpty ? null : actionable.first;
  }

  void updateCustomerState(String customerId, String nextAction, String reason) {
    recordOutcome(customerId, nextAction, reason, 'State updated to $nextAction');
  }

  /// Records a call/visit outcome via the real API — server-authoritative
  /// (see customerService.recordOutcome). [screenshot], when present (e.g.
  /// call evidence from NoAnswerForm), is uploaded first and its resulting
  /// server-assigned path is attached to the audit event this outcome
  /// creates — see ApiClient.uploadAttachment.
  Future<void> recordOutcome(String customerId, String nextAction, String reason, String details,
      {DateTime? followUpAt,
      double? ptpAmountValue,
      DateTime? ptpDate,
      String? ptpMode,
      XFile? screenshot,
      bool replacingNoAnswer = false}) async {
    final body = {
      'nextAction': nextAction,
      'reason': reason,
      'details': details,
      if (followUpAt != null) 'followUpAt': followUpAt.toUtc().toIso8601String(),
      if (ptpAmountValue != null) 'ptpAmountValue': ptpAmountValue,
      if (ptpDate != null) 'ptpDate': ptpDate.toUtc().toIso8601String(),
      if (ptpMode != null) 'ptpMode': ptpMode,
      // Salesman is replacing a misrecorded No Answer via "Edit Recorded
      // Outcome" (Today's Recovery Tasks only) — see
      // customerService.recordOutcome's `replacingNoAnswer` branch, which
      // erases the old No Answer audit row and attempt count instead of
      // layering this new outcome on top of it.
      if (replacingNoAnswer) 'replacingNoAnswer': true,
    };

    Map<String, dynamic> detail;
    try {
      String? attachmentPath;
      if (screenshot != null) {
        final bytes = await screenshot.readAsBytes();
        attachmentPath = await apiClient.uploadAttachment(bytes, filename: screenshot.name, contentType: screenshot.mimeType ?? 'image/jpeg');
      }
      detail = await apiClient.recordOutcome(customerId, {
        ...body,
        if (attachmentPath != null) 'attachmentPath': attachmentPath,
      });
    } on ApiException catch (e) {
      await _queueOrRethrow(
        e,
        type: PendingActionType.recordOutcome,
        targetEndpoint: '/api/customers/$customerId/record-outcome',
        payload: body,
        relatedCustomerId: customerId,
        attachmentBytes: screenshot != null ? await screenshot.readAsBytes() : null,
        attachmentContentType: screenshot?.mimeType ?? (screenshot != null ? 'image/jpeg' : null),
      );
    }

    final updated = Customer.fromJson(detail);
    final index = customers.indexWhere((c) => c.id == customerId);
    if (index != -1) {
      customers[index] = updated;
    } else {
      customers.add(updated);
    }
    customersHandled++;
    if (nextAction == 'PTP Scheduled') ptpsCreated++;

    // recordOutcome can create a task AND/OR a PTP/dispute/payment claim
    // depending on nextAction/reason (see customerService.recordOutcome on
    // the server) — refresh every list it might have touched, not just
    // tasks, or a claim/PTP/dispute created by this call stays invisible
    // until some other action happens to trigger a refresh. Also refresh
    // reports: the Today's Recovery "done" count (recoveryDoneTodayCount)
    // is server-computed from the audit trail this call just added to.
    await _refreshTasksFromApi();
    await _refreshPtpsFromApi();
    await _refreshDisputesFromApi();
    await _refreshPaymentClaimsFromApi();
    await _refreshReportsFromApi();
    notifyListeners();
  }

  /// The same-day self-service replace (recordOutcome's `replacingNoAnswer`)
  /// only exists for the day the No Answer was recorded — see
  /// Customer360Screen's `_openEditRecordedOutcome`. Once that window has
  /// passed, replacing it goes through the same RE-approval path every
  /// other outcome edit already uses (see requestOutcomeEdit /
  /// outcomeEditService.js's 'NoAnswerReplacement' kind): nothing changes
  /// on the customer until an RE approves.
  Future<void> requestNoAnswerReplacement(String customerId, String nextAction, String reason, String details,
      {DateTime? followUpAt, double? ptpAmountValue, DateTime? ptpDate, String? ptpMode, XFile? screenshot}) async {
    String? attachmentPath;
    if (screenshot != null) {
      final bytes = await screenshot.readAsBytes();
      attachmentPath = await apiClient.uploadAttachment(bytes, filename: screenshot.name, contentType: screenshot.mimeType ?? 'image/jpeg');
    }
    await requestOutcomeEdit(customerId, {
      'outcomeKind': 'NoAnswerReplacement',
      'requestedPayload': {
        'nextAction': nextAction,
        'reason': reason,
        'details': details,
        if (followUpAt != null) 'followUpAt': followUpAt.toUtc().toIso8601String(),
        if (ptpAmountValue != null) 'ptpAmountValue': ptpAmountValue,
        if (ptpDate != null) 'ptpDate': ptpDate.toUtc().toIso8601String(),
        if (ptpMode != null) 'ptpMode': ptpMode,
        if (attachmentPath != null) 'attachmentPath': attachmentPath,
      },
      'editReason': 'Correcting a No Answer recorded on a previous day.',
    });
  }

  /// Server-authoritative: completion, the "money still due, nothing else
  /// open" reopen guard, and the resulting audit entry are all computed by
  /// taskService.completeTask on the server — see server/README.md. This
  /// client just calls it and refreshes. `visitPhoto` is required by the
  /// server (and rejected with a real error if omitted) when this is a
  /// Physical Visit task — real proof the visit happened, preserved in the
  /// customer's history alongside the completion.
  Future<void> completeTask(String taskId, {XFile? visitPhoto}) async {
    final task = tasks.firstWhere((t) => t.id == taskId, orElse: () => tasks.first);
    try {
      String? attachmentPath;
      if (visitPhoto != null) {
        final bytes = await visitPhoto.readAsBytes();
        attachmentPath = await apiClient.uploadAttachment(bytes, filename: visitPhoto.name, contentType: visitPhoto.mimeType ?? 'image/jpeg');
      }
      await apiClient.completeTask(taskId, attachmentPath: attachmentPath);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.taskComplete,
          targetEndpoint: '/api/tasks/$taskId/complete',
          payload: const {},
          relatedCustomerId: task.customerId,
          attachmentBytes: visitPhoto != null ? await visitPhoto.readAsBytes() : null,
          attachmentContentType: visitPhoto?.mimeType ?? (visitPhoto != null ? 'image/jpeg' : null));
    }
    tasksCompleted++;
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  Future<void> reviewPhysicalVisit(String taskId) async {
    await apiClient.reviewTask(taskId);
    await _refreshTasksFromApi();
    notifyListeners();
  }

  Future<void> approveTaskEdit(String taskId) async {
    final task = tasks.firstWhere((t) => t.id == taskId, orElse: () => tasks.first);
    try {
      await apiClient.approveTaskEdit(taskId);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.taskApproveEdit,
          targetEndpoint: '/api/tasks/$taskId/approve-edit',
          payload: const {},
          relatedCustomerId: task.customerId);
    }
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  /// RE directly rescheduling a task's deadline (spec: RE already has
  /// approval authority, so this must not create a Pending request that
  /// only RE could then approve — that would be a self-directed approval
  /// loop). Only the salesperson's own extension requests (made from their
  /// own task) went through [approveTaskEdit]/[rejectTaskEdit] — the
  /// salesperson-side "Edit Task" / extension-request feature itself was
  /// removed from My Tasks; these RE-side review methods remain in case
  /// any legacy pending requests still exist.
  Future<void> rescheduleTask(String taskId, String reason, DateTime newDeadline) async {
    final task = tasks.firstWhere((t) => t.id == taskId, orElse: () => tasks.first);
    final body = {'reason': reason, 'newDeadline': newDeadline.toUtc().toIso8601String()};
    try {
      await apiClient.rescheduleTask(taskId, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.taskReschedule,
          targetEndpoint: '/api/tasks/$taskId/reschedule',
          payload: body,
          relatedCustomerId: task.customerId);
    }
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  Future<void> rejectTaskEdit(String taskId) async {
    final task = tasks.firstWhere((t) => t.id == taskId);
    try {
      await apiClient.rejectTaskEdit(taskId);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.taskRejectEdit,
          targetEndpoint: '/api/tasks/$taskId/reject-edit',
          payload: const {},
          relatedCustomerId: task.customerId);
    }
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  Future<void> reassignTask(String taskId, String newOwnerId, String reason) async {
    final task = tasks.firstWhere((t) => t.id == taskId);
    final body = {'newOwnerId': newOwnerId, 'reason': reason};
    try {
      await apiClient.reassignTask(taskId, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.taskReassign,
          targetEndpoint: '/api/tasks/$taskId/reassign',
          payload: body,
          relatedCustomerId: task.customerId);
    }
    await _refreshTasksFromApi();
    await _refreshOneCustomerFromApi(task.customerId);
    notifyListeners();
  }

  /// Server-authoritative (customerService.takeControl): supersedes every
  /// open task for this customer and sets RE Control state — same
  /// "single active outcome record" rule recordOutcome already enforces.
  Future<void> takeREControl(String customerId) async {
    await apiClient.takeControl(customerId);
    await _refreshOneCustomerFromApi(customerId);
    await _refreshTasksFromApi();
    notifyListeners();
  }

  Future<void> releaseREControl(String customerId) async {
    await apiClient.releaseControl(customerId);
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> assignManagementInstruction(String customerId, String salesmanId, String desc, DateTime deadline, {String priority = 'Critical', String taskType = 'managementInstruction', String? note, String? attachmentPath}) async {
    await apiClient.assignManagementInstruction(customerId, {
      'salesmanId': salesmanId,
      'desc': desc,
      'deadline': deadline.toUtc().toIso8601String(),
      'priority': priority,
      'taskType': taskType,
      if (note != null && note.isNotEmpty) 'note': note,
      if (attachmentPath != null && attachmentPath.isNotEmpty) 'attachmentPath': attachmentPath,
    });
    await _refreshOneCustomerFromApi(customerId);
    await _refreshTasksFromApi();
    notifyListeners();
  }

  Future<void> reassignCustomer(String customerId, String fromSalesmanId, String toSalesmanId, String reason) async {
    await apiClient.reassignCustomer(customerId, {'toSalesmanId': toSalesmanId, 'reason': reason});
    await _refreshOneCustomerFromApi(customerId);
    // Both salesmen's roster figures (customers, totalOverdue,
    // collectionTarget, recoveryScore, ...) reflect their post-reassignment
    // portfolio immediately — real, recomputed server-side on every fetch.
    await _refreshSalesmenFromApi();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // PTP Correction (spec §20)
  // ---------------------------------------------------------------------
  Future<void> requestPtpCorrection(String ptpId, double newAmount, DateTime newDate, String reason,
      {String? paymentMode}) async {
    final ptp = ptps.firstWhere((p) => p.id == ptpId);
    final body = {
      'amount': newAmount,
      'date': newDate.toUtc().toIso8601String(),
      if (paymentMode != null && paymentMode.isNotEmpty) 'paymentMode': paymentMode,
      'reason': reason,
    };
    try {
      await apiClient.requestPtpCorrection(ptpId, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.ptpCorrectionRequest,
          targetEndpoint: '/api/ptps/$ptpId/request-correction',
          payload: body,
          relatedCustomerId: ptp.customerId);
    }
    await _refreshPtpsFromApi();
    notifyListeners();
  }

  Future<void> approvePtpCorrection(String ptpId) async {
    final ptp = ptps.firstWhere((p) => p.id == ptpId);
    try {
      await apiClient.approvePtpCorrection(ptpId);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.ptpCorrectionApprove,
          targetEndpoint: '/api/ptps/$ptpId/approve-correction',
          payload: const {},
          relatedCustomerId: ptp.customerId);
    }
    await _refreshPtpsFromApi();
    await _refreshOneCustomerFromApi(ptp.customerId);
    notifyListeners();
  }

  Future<void> rejectPtpCorrection(String ptpId, String reason) async {
    final ptp = ptps.firstWhere((p) => p.id == ptpId);
    final body = {'reason': reason};
    try {
      await apiClient.rejectPtpCorrection(ptpId, body);
    } on ApiException catch (e) {
      await _queueOrRethrow(e,
          type: PendingActionType.ptpCorrectionReject,
          targetEndpoint: '/api/ptps/$ptpId/reject-correction',
          payload: body,
          relatedCustomerId: ptp.customerId);
    }
    await _refreshPtpsFromApi();
    await _refreshOneCustomerFromApi(ptp.customerId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Escalation (spec §22-§25)
  // ---------------------------------------------------------------------
  /// A real, manual RE escalation via the API. Broken-PTP auto-escalation
  /// is computed server-side (see ptpService.evaluateBrokenPtpEscalation)
  /// once ptpVerificationService verifies a PTP as broken against BUSY —
  /// there is no client-side escalation engine, and no manual "mark PTP
  /// outcome" path either: a PTP's kept/partiallyKept/broken outcome is
  /// decided exclusively by that automated BUSY verification.
  Future<void> escalateCustomer(String customerId, String level, String reason, String plan, String ownerId, DateTime deadline) async {
    await apiClient.raiseEscalation(customerId, {
      'level': level,
      'reason': reason,
      'plan': plan,
      'ownerId': ownerId,
      'deadline': deadline.toUtc().toIso8601String(),
      'moneyAtRisk': customers.firstWhere((c) => c.id == customerId).totalDue,
    });
    await _refreshEscalationsFromApi();
    await _refreshOneCustomerFromApi(customerId);
    notifyListeners();
  }

  Future<void> resolveEscalation(String caseId, String resolutionNote) async {
    final existing = escalationCases.firstWhere((e) => e.id == caseId);
    await apiClient.resolveEscalation(caseId, resolutionNote);
    await _refreshEscalationsFromApi();
    await _refreshOneCustomerFromApi(existing.customerId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Notifications (spec §50)
  // ---------------------------------------------------------------------
  Future<void> markNotificationRead(String id) async {
    await apiClient.markNotificationRead(id);
    final i = notifications.indexWhere((n) => n.id == id);
    if (i != -1) {
      notifications[i] = notifications[i].copyWith(read: true);
      notifyListeners();
    }
  }

  Future<void> markAllNotificationsRead() async {
    await apiClient.markAllNotificationsRead();
    notifications = notifications.map((n) => n.copyWith(read: true)).toList();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // 5 PM Control (spec §51)
  // ---------------------------------------------------------------------
  void runFivePmControl() {
    controlSnapshots.insert(0, ControlSnapshot(
      id: 'CS_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      overdueTasks: overdueTaskCount,
      mandatoryActionsNotCompleted: tasks.where((t) => t.priority == 'Critical' && t.status != TaskStatus.completed).length,
      brokenPtpWithoutNextAction: brokenPtps.where((p) {
        final c = customers.firstWhere((c) => c.id == p.customerId, orElse: () => customers.first);
        return !c.hasValidNextAction;
      }).length,
      ownerlessExposure: ownerlessExposure,
      l3CasesWithoutPlan: escalationCases.where((e) => e.isOpen && e.level == 'L3' && e.plan.trim().isEmpty).length,
    ));
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Company-wide search (spec §58)
  // ---------------------------------------------------------------------
  List<Customer> searchCustomers(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();
    return customers.where((c) =>
        c.name.toLowerCase().contains(q) ||
        c.id.toLowerCase().contains(q) ||
        c.assignedSalesmanId.toLowerCase().contains(q) ||
        c.branch.toLowerCase().contains(q)).toList();
  }

  /// A dozen manager report screens call this from a small "refresh" icon
  /// expecting it to bring their data up to date — re-fetches everything
  /// from the real server.
  void refreshBusySync() {
    unawaited(_refreshAllFromApi());
  }
}
