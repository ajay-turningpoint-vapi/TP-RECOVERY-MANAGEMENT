import 'package:flutter/material.dart';
import 'package:salesman_mobile/v2/utils/initials.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/escalation_case.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/screens/outcome_forms.dart';
import 'package:salesman_mobile/services/attachment_picker.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';

// Indian digit grouping (₹1,23,456, not ₹123,456) — several money labels
// on this screen used plain toStringAsFixed string interpolation, which
// doesn't group at all; this matches the _rupee pattern already used
// consistently across the v3 screens.
final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);


Color levelColor(String level) {
  switch (level) {
    case 'L4':
      return const Color(0xFF991B1B);
    case 'L3':
      return const Color(0xFFDC2626);
    case 'L2':
      return const Color(0xFFEA580C);
    default:
      return const Color(0xFF64748B);
  }
}

class Customer360Screen extends StatefulWidget {
  final Customer customer;

  /// When true (Manager access), every action surface — take/release
  /// control, assign instruction, reassign agent, record outcome, request
  /// correction — is hidden; only the informational sections render.
  final bool readOnly;

  /// When true, this screen was opened from the dashboard "START RECOVERY"
  /// queue: after an outcome is recorded it advances straight to the next
  /// actionable customer, clearing the earlier queue screens so Back goes
  /// to the dashboard rather than a completed customer.
  final bool recoveryQueue;

  /// Customer ids already worked in this queue run — skipped when picking
  /// the next customer so the queue never loops back onto one just handled.
  final Set<String>? queueVisitedIds;

  /// Opened from the Today's Recovery "Edit Outcome" button: after the
  /// detail loads, auto-opens the recorded outcome's edit form (pre-filled)
  /// so the salesman can request an RE-approved change to its fields.
  final bool editOutcome;

  const Customer360Screen(
      {super.key,
      required this.customer,
      this.readOnly = false,
      this.recoveryQueue = false,
      this.queueVisitedIds,
      this.editOutcome = false});

  @override
  State<Customer360Screen> createState() => _Customer360ScreenState();
}

class _Customer360ScreenState extends State<Customer360Screen> {
  String? _selectedOutcome;
  // Set by _showOutcomeBottomSheet when an open Physical Visit task requires
  // photo proof up front — none of the individual outcome forms (PTP, Will
  // Confirm, Unable/Refused) collect their own attachment, so without this
  // a physical visit could be recorded with no evidence at all. Falls back
  // into _finish() for whichever outcome the salesman ends up picking.
  XFile? _pendingVisitPhoto;
  bool _isLoading = true;
  // History tab infinite scroll — a long-tenured customer can accumulate
  // hundreds of audit events (every outcome, RE decision, and
  // system-generated task writes one). Real server-side keyset pagination
  // (GET /api/customers/:id/audit-history) fetches 20 at a time as the
  // user nears the bottom, instead of the customer detail fetch (which
  // still returns the full history for the Recovery Activities tab's
  // calls/visits counters) downloading everything just to show a list.
  final List<AuditEvent> _historyItems = [];
  String? _historyCursor;
  bool _historyHasMore = true;
  bool _historyLoading = false;

  // Set when a Payment Timeline ageing bucket is tapped ('0-30' | '31-60' |
  // '61-90' | '90+'); filters the Invoices tab to invoices in that bucket.
  String? _invoiceAgeBucket;


  @override
  void initState() {
    super.initState();
    // GET /api/customers (which populates store.customers everywhere else)
    // never includes invoices/auditHistory — only this customer's own
    // detail fetch does. Without this, Invoices/History silently fell back
    // to Customer.invoices's empty-list default and a made-up dummy dataset.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        await context.read<AppStore>().refreshCustomerDetailFromApi(widget.customer.id);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      if (mounted && widget.editOutcome) {
        _openEditRecordedOutcome();
      }
      _loadMoreHistory();
    });
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoading || !_historyHasMore) return;
    setState(() => _historyLoading = true);
    try {
      final page = await context.read<AppStore>().fetchAuditHistoryPage(widget.customer.id, cursor: _historyCursor);
      if (!mounted) return;
      setState(() {
        _historyItems.addAll(page.items);
        _historyCursor = page.nextCursor;
        _historyHasMore = page.nextCursor != null;
      });
    } catch (_) {
      // A failed page fetch just leaves _historyHasMore as-is — the
      // scroll-threshold trigger in _buildFullHistory will retry the next
      // time the user scrolls near the bottom.
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  /// Resolves what outcome was recorded for this customer and opens the
  /// right sheet: a PTP gets its own pre-filled edit sheet; a No Answer
  /// (which never resolved anything) just opens a plain Record Outcome so
  /// the salesman can log what really happened — another No Answer bumps
  /// the attempt count, anything else resolves the account, no RE
  /// approval. Any other recorded outcome kind tells the salesman to ask
  /// their RE.
  /// The latest still-open (scheduled / pending-verification) PTP for a
  /// customer, or null. Used both to route "Edit recorded outcome" to the
  /// PTP sheet and to keep the Recorded Outcome card visible after a
  /// partial PTP un-parks the account (covered/actionable model).
  PromiseToPay? _openScheduledPtp(AppStore store, String customerId) {
    PromiseToPay? ptp;
    for (final p in store.ptps) {
      if (p.customerId == customerId &&
          (p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification)) {
        if (ptp == null || p.promiseDate.isAfter(ptp.promiseDate)) ptp = p;
      }
    }
    return ptp;
  }

  void _openEditRecordedOutcome() {
    final store = context.read<AppStore>();
    final c = store.customers.firstWhere((x) => x.id == widget.customer.id, orElse: () => widget.customer);
    final ptp = _openScheduledPtp(store, c.id);
    if (ptp != null) {
      if (ptp.correctionStatus != 'none') {
        // One-time edit already used — locked through the RE decision and
        // after it (Pending / Approved / Rejected).
        showAppMessage(context,
            message: ptp.correctionStatus == 'Pending'
                ? 'You already sent a correction for this PTP — wait for the RE to decide it.'
                : 'The RE has already reviewed your PTP correction. It can’t be edited again here.',
            title: 'PTP edit locked');
        return;
      }
      _showEditPtpSheet(ptp);
      return;
    }
    final hasOpenPhysicalVisit = store.tasks.any((t) =>
        t.customerId == c.id &&
        t.type == TaskType.physicalVisit &&
        t.status != TaskStatus.completed);
    if (c.isPendingNoAnswerEdit || hasOpenPhysicalVisit) {
      // A No Answer / 3rd-No-Answer Physical Visit never resolved anything —
      // this isn't an "edit", it's a fresh Record Outcome (record what
      // happened on the call-back or the visit). No RE approval.
      _showOutcomeBottomSheet();
      return;
    }
    showAppMessage(context,
        message:
            'This recorded outcome can’t be edited here yet. Ask your Recovery Executive to adjust it.',
        title: 'Not editable');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final currentCustomer = store.customers.firstWhere(
        (c) => c.id == widget.customer.id,
        orElse: () => widget.customer);
    // Any recorded outcome locks Record Outcome — a parked account
    // ("Waiting / Monitoring"), or an outcome logged today for this
    // customer at all (Internal Action, Dispute, Follow-up, PTP, Payment
    // Made — see store.recoveryDoneTodayCustomerIds, grounded in the real
    // "source: Record Outcome" audit trail). The ONE exception is a
    // recorded No Answer, which isn't a resolution: the button stays live,
    // relabelled "NEW RECORD OUTCOME", so the salesman can log what
    // actually happened once the customer calls back (or another No
    // Answer, which just bumps the attempt count).
    final isNoAnswerRerecord = currentCustomer.isPendingNoAnswerEdit;
    final outcomeRecorded =
        currentCustomer.currentRecoveryState == 'Waiting / Monitoring' ||
            store.recoveryDoneTodayCustomerIds.contains(currentCustomer.id);
    // An open "Recovery" task ("Collect ₹X — record a new outcome", raised
    // automatically after a PTP verifies) explicitly asks for the next
    // outcome, so Record Outcome must stay live even if an outcome was
    // already logged today.
    final hasOpenRecoveryTask = store.tasks.any((t) =>
        t.customerId == currentCustomer.id &&
        t.source == 'Recovery' &&
        t.status != TaskStatus.completed);
    // A 3rd-No-Answer Physical Visit is open — the salesman must visit and
    // record the outcome, so keep the button live.
    final hasOpenPhysicalVisit = store.tasks.any((t) =>
        t.customerId == currentCustomer.id &&
        t.type == TaskType.physicalVisit &&
        t.status != TaskStatus.completed);
    final isLocked = outcomeRecorded &&
        !isNoAnswerRerecord &&
        !hasOpenRecoveryTask &&
        !hasOpenPhysicalVisit;
    // "No next action set" — the account has nothing operational queued.
    // The inline button that used to live in the red alert card is gone;
    // the bottom CREATE TASK button turns red instead to carry that urgency.
    final noNextActionSet = !(currentCustomer.hasValidNextAction && currentCustomer.primaryNextAction.trim().isNotEmpty);
    // Management must always be read-only here, regardless of whether the
    // screen that navigated here remembered to pass readOnly: true — most
    // don't. Deriving it from the real role means no call site can ever
    // reintroduce this gap.
    final effectiveReadOnly = widget.readOnly || store.userRole == 'MANAGEMENT';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1B2B48),
          elevation: 0,
          title: const Text('Customer Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          bottom: const TabBar(
            labelColor: Color(0xFF0052CC),
            unselectedLabelColor: Color(0xFF5A6B87),
            indicatorColor: Color(0xFF0052CC),
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Invoices'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Overview Tab
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(currentCustomer),
                  if (effectiveReadOnly) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  const Color(0xFF7C3AED).withValues(alpha: 0.15))),
                      child: const Row(
                        children: [
                          Icon(Icons.visibility_outlined,
                              size: 15, color: Color(0xFF7C3AED)),
                          SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  'Manager view is read-only — reassignment, instruction, and outcome actions are taken by the Recovery Executive or the assigned salesperson.',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF1B2B48)))),
                        ],
                      ),
                    ),
                  ],
                  if (store.userRole == 'RECOVERY_EXECUTIVE' ||
                      effectiveReadOnly) ...[
                    const SizedBox(height: 16),
                    _buildAssignedSalesmanRow(currentCustomer, store),
                    const SizedBox(height: 16),
                    _buildNextActionCard(
                        context, currentCustomer, store, effectiveReadOnly),
                    const SizedBox(height: 16),
                    _buildFreshnessAndHealth(currentCustomer),
                    if (currentCustomer.ownerMappingRequired) ...[
                      const SizedBox(height: 16),
                      _buildExceptionBanner(
                        'Owner Mapping Required',
                        'No active salesperson mapping exists for this exposure.',
                        Icons.person_off_outlined,
                      ),
                    ],
                    if (currentCustomer.escalationLevel != 'none' ||
                        currentCustomer.currentRecoveryState == 'RE Control' ||
                        currentCustomer.currentRecoveryState ==
                            'RE Supervision' ||
                        currentCustomer.ownerMappingRequired) ...[
                      const SizedBox(height: 16),
                      _buildSupervisoryContext(currentCustomer, store),
                    ],
                    if (currentCustomer.escalationLevel != 'none') ...[
                      const SizedBox(height: 16),
                      _buildEscalationSection(currentCustomer, store),
                    ],
                  ],
                  if (store.userRole == 'SALESPERSON' &&
                      ((currentCustomer.currentRecoveryState ==
                                  'Waiting / Monitoring' &&
                              currentCustomer.primaryNextAction.isNotEmpty) ||
                          _openScheduledPtp(store, currentCustomer.id) !=
                              null)) ...[
                    const SizedBox(height: 16),
                    _buildRecordedOutcomeCard(context, currentCustomer, store),
                  ],
                  if (store.userRole == 'SALESPERSON') ...[
                    Builder(builder: (context) {
                      final statusCard =
                          _buildReStatusCard(currentCustomer, store);
                      if (statusCard == null) return const SizedBox();
                      return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: statusCard);
                    }),
                  ],
                  const SizedBox(height: 16),
                  _buildOutstandingSummary(currentCustomer),
                  const SizedBox(height: 16),
                  _buildPaymentTimeline(currentCustomer),
                  const SizedBox(height: 16),
                  _buildRecoveryActivities(currentCustomer, store),
                ],
              ),
            ),
            // Invoices Tab
            _isLoading ? const Center(child: CircularProgressIndicator()) : _buildAllInvoices(currentCustomer),
            // History Tab
            _isLoading ? const Center(child: CircularProgressIndicator()) : _buildFullHistory(currentCustomer),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
            ),
            child: effectiveReadOnly
                ? const Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 16, color: Color(0xFF64748B)),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text('Manager view is read-only.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600))),
                    ],
                  )
                : store.userRole == 'RECOVERY_EXECUTIVE'
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: noNextActionSet
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: () => _showCreateTaskDialog(
                              context, store, currentCustomer),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_task, size: 18),
                              SizedBox(width: 6),
                              Text('CREATE TASK',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLocked
                              ? Colors.grey[400]
                              : const Color(0xFF0052CC),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: isLocked ? null : _showOutcomeBottomSheet,
                        child: Text(
                            isLocked
                                ? 'OUTCOME RECORDED'
                                : isNoAnswerRerecord
                                    ? 'NEW RECORD OUTCOME'
                                    : 'RECORD OUTCOME',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupervisoryContext(Customer c, AppStore store) {
    const levelLabels = {
      'none': 'L1 — Salesperson Led',
      'L1': 'L1 — Salesperson Led',
      'L2': 'L2 — RE Supervision',
      'L3': 'L3 — RE Control',
      'L4': 'L4 — Management Attention',
    };
    final escLevel = c.escalationLevel == 'none' ? 'L1' : c.escalationLevel;
    final escalation = levelLabels[c.escalationLevel] ?? c.escalationLevel;
    final badgeColor = levelColor(escLevel);

    Widget cell(String label, String value, {Color? valueColor}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF97A3B6))),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? const Color(0xFF1B2B48))),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.25), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: badgeColor, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Supervisory Control Context',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1B2B48))),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(escLevel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: badgeColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEDF2F7)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell('Recovery State', c.currentRecoveryState)),
              Expanded(
                  child: cell('Assigned Agent',
                      store.salesmanDisplayName(c.assignedSalesmanId))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: cell('Escalation Level', escalation,
                      valueColor: badgeColor)),
              Expanded(
                  child: cell('Oldest Overdue', '${c.oldestOverdueDays} Days',
                      valueColor: const Color(0xFFE53935))),
            ],
          ),
        ],
      ),
    );
  }

  // Credit Health band -> colour, mirroring the salesman Recovery Score
  // band palette (profile_screen._scoreBandColor) so the two "score"
  // surfaces read the same way.
  static Color _creditHealthColor(String band) {
    switch (band) {
      case 'Low Risk':
        return const Color(0xFF16A34A);
      case 'Moderate':
        return const Color(0xFF0052CC);
      case 'High':
        return const Color(0xFFF57C00);
      case 'Critical':
        return const Color(0xFFE53935);
      default: // Insufficient History
        return const Color(0xFF5A6B87);
    }
  }

  String _syncedAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat('dd MMM').format(t);
  }

  Widget _buildFreshnessAndHealth(Customer c) {
    final fresh = DateTime.now().difference(c.financialFreshness).inHours < 6;
    final band = c.creditHealthBand;
    final healthColor = _creditHealthColor(band);
    final score = c.creditHealthScore;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: fresh ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: fresh
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                Icon(fresh ? Icons.sync : Icons.sync_problem,
                    size: 14,
                    color: fresh
                        ? const Color(0xFF388E3C)
                        : const Color(0xFFE53935)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Financials synced ${_syncedAgo(c.financialFreshness)}',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: fresh
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFE53935)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _showCreditHealthBreakdown(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: healthColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: healthColor.withValues(alpha: 0.35))),
              child: Row(
                children: [
                  Icon(Icons.favorite, size: 14, color: healthColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        score != null
                            ? 'Credit Health: $score%'
                            : 'Credit Health: N/A',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: healthColor)),
                  ),
                  Icon(Icons.chevron_right, size: 14, color: healthColor),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // "User can drill from score to human-readable contributing factors"
  // (Master Build Book RMS-06) — the real weighted components behind this
  // customer's own current Credit Health score.
  void _showCreditHealthBreakdown(Customer c) {
    final breakdown = c.creditHealthComponents;
    final band = c.creditHealthBand;
    final bandColor = _creditHealthColor(band);
    final total = (breakdown?['total'] ?? c.creditHealthScore ?? 0).toInt();

    const components = <(IconData, Color, String, String, int)>[
      (Icons.schedule, Color(0xFF2563EB), 'paymentTimeliness', 'Payment Timeliness', 30),
      (Icons.handshake_outlined, Color(0xFF16A34A), 'ptpReliability', 'PTP Reliability', 20),
      (Icons.hourglass_bottom, Color(0xFF7C3AED), 'currentAgeing', 'Current Ageing', 20),
      (Icons.account_balance_wallet_outlined, Color(0xFFEA580C), 'outstandingExposure', 'Outstanding Exposure', 15),
      (Icons.trending_up, Color(0xFFDC2626), 'recentPaymentTrend', 'Recent Payment Trend', 10),
      (Icons.report_gmailerrorred_outlined, Color(0xFF0D9488), 'behaviouralExceptions', 'Behavioural Exceptions', 5),
    ];

    Widget componentRow(IconData icon, Color color, String label, int weight, num value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$label ($weight%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B2B48))),
                        Text('$value%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (value.clamp(0, 100)) / 100,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFF0F2F5),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: breakdown == null ? 0.42 : 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [bandColor, bandColor.withValues(alpha: 0.7)]), shape: BoxShape.circle),
                    child: Text(breakdown == null && c.creditHealthScore == null ? '—' : '$total%',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Credit Health', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1B2B48))),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: bandColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(band, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: bandColor)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  'Risk belongs to the customer, not the salesperson, and survives reassignment.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF5A6B87), height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              if (breakdown == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Insufficient History — no due exposure or payment/PTP history yet.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF5A6B87)),
                  ),
                )
              else ...[
                for (final comp in components) componentRow(comp.$1, comp.$2, comp.$4, comp.$5, breakdown[comp.$3] ?? 0),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: bandColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: bandColor.withValues(alpha: 0.25))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Weighted Credit Health Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                      Text('$total%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: bandColor)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Always-visible for RE (and read-only Manager) — surfaces exactly what
  /// happens next on this account. When there genuinely is no valid next
  /// action (no owner, nothing scheduled, nothing outstanding on record),
  /// this stops being informational and becomes a hard call-to-action:
  /// RE must create a task or issue an instruction right here, not just be
  /// told about it in a banner buried further down the screen.
  Widget _buildNextActionCard(BuildContext context, Customer c, AppStore store, bool readOnly) {
    final hasAction = c.hasValidNextAction && c.primaryNextAction.trim().isNotEmpty;
    if (hasAction) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFDBFE), width: 1.4),
        ),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, color: Color(0xFF0052CC), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NEXT ACTION',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A6B87),
                          letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text(c.primaryNextAction,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0052CC))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // No valid next action on record — force a decision now, right here.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.6),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NO NEXT ACTION SET',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB91C1C))),
                    SizedBox(height: 3),
                    Text(
                      'This account has no valid operational next action. Use the red CREATE TASK button below to assign one before leaving this screen.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF7F1D1D), height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionBanner(
      String title, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDBA74), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFEA580C), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RE EXCEPTION: $title',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFFC2410C))),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9A3412))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEscalationSection(Customer c, AppStore store) {
    final EscalationCase? escalation =
        store.escalationCases.cast<EscalationCase?>().firstWhere(
              (e) => e != null && e.customerId == c.id && e.isOpen,
              orElse: () => null,
            );
    if (escalation == null) return const SizedBox();
    final color = levelColor(escalation.level);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.trending_up, color: color, size: 18),
            const SizedBox(width: 8),
            Text('${escalation.level} Escalation Case',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          ]),
          const SizedBox(height: 10),
          Text('Reason: ${escalation.reason}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
          const SizedBox(height: 4),
          Text('Plan: ${escalation.plan}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
          const SizedBox(height: 4),
          Text(
              'Owner: ${store.salesmanDisplayName(escalation.ownerId)}  •  Deadline: ${DateFormat('dd MMM, hh:mm a').format(escalation.deadline)}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B2B48))),
        ],
      ),
    );
  }

  /// Surfaces what Recovery Executive is currently doing about this
  /// customer — a raised dispute's live status, an active escalation's
  /// owner/plan/deadline, and any RE-owned dependency task — so the
  /// salesperson always knows the current state of a problem they raised,
  /// not just an audit-log line. Returns null when there is nothing to show.
  Widget? _buildReStatusCard(Customer c, AppStore store) {
    final openDispute = store.disputes.cast<Map<String, dynamic>?>().firstWhere(
          (d) =>
              d != null &&
              d['customer'] == c.name &&
              d['status'] != 'Resolved' &&
              d['status'] != 'Rejected' &&
              // A dispute the RE has finished verifying and found the
              // money was never actually received — a concluded outcome,
              // same as Resolved/Rejected, not something still "open" and
              // worth showing the salesperson as if it were in progress.
              d['status'] != 'Returned to Recovery',
          orElse: () => null,
        );
    final reTasks = store.tasks
        .where((t) =>
            t.customerId == c.id &&
            t.ownerId != store.currentSalesmanId &&
            t.status != TaskStatus.completed)
        .toList();

    if (openDispute == null && c.escalationLevel == 'none' && reTasks.isEmpty) {
      return null;
    }

    Color statusColor(String status) {
      switch (status) {
        case 'Pending Approval':
        case 'Awaiting Verification':
          return const Color(0xFFC2410C);
        case 'Approved':
        case 'In Resolution':
          return const Color(0xFF0052CC);
        default:
          return const Color(0xFF5A6B87);
      }
    }

    // The raw backend status is precise for an RE (who knows the state
    // machine) but reads wrong to the salesperson who raised it — e.g.
    // "Approved" on its own sounds like their claim was granted/settled,
    // when it actually just means the RE accepted it for processing and
    // handed it to a resolution owner; nothing has been confirmed or
    // written off yet. This maps the same status to a label that says
    // what's actually happening from the raiser's side.
    String raiserStatusLabel(String status) {
      switch (status) {
        case 'Approved':
          return 'In Progress — With Resolution Owner';
        case 'Awaiting Verification':
          return 'Resolution Submitted — RE Verifying';
        case 'In Resolution':
          return 'In Progress';
        default:
          return status;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF0052CC), size: 18),
              SizedBox(width: 8),
              Text('Recovery Executive Status',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1B2B48))),
            ],
          ),
          const SizedBox(height: 10),
          if (openDispute != null) ...[
            Text('Dispute raised: ₹${openDispute['amount']}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: Color(0xFF1B2B48))),
            const SizedBox(height: 2),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor(openDispute['status']).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(raiserStatusLabel(openDispute['status'] as String),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor(openDispute['status']))),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          if (c.escalationLevel != 'none') ...[
            Text('Escalated: ${c.escalationLevel}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: Color(0xFF1B2B48))),
            const SizedBox(height: 2),
            const Text(
                'Recovery Executive has taken supervisory/control action on this account.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF5A6B87))),
            const SizedBox(height: 10),
          ],
          for (final t in reTasks) ...[
            Text('RE dependency: ${_taskTypeLabel(t.type)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: Color(0xFF1B2B48))),
            Text(
                'Owner: ${store.salesmanDisplayName(t.ownerId)} · Due ${DateFormat('dd MMM').format(t.deadline)}',
                style:
                    const TextStyle(fontSize: 11.5, color: Color(0xFF5A6B87))),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _taskTypeLabel(TaskType t) {
    switch (t) {
      case TaskType.customerCall:
        return 'Customer Call';
      case TaskType.physicalVisit:
        return 'Physical Visit';
      case TaskType.disputeResolution:
        return 'Dispute Resolution';
      case TaskType.documentFollowUp:
        return 'Document Follow-Up';
      case TaskType.financialTeamFollowUp:
        return 'Financial Team Follow-Up';
      case TaskType.customerDetailCorrection:
        return 'Customer Detail Correction';
      case TaskType.paymentVerification:
        return 'Payment Verification';
      case TaskType.managementInstruction:
        return 'Management Instruction';
    }
  }

  /// Pre-filled edit form for a recorded PTP outcome. Submitting creates an
  /// RE-approval request (store.requestOutcomeEdit) — the PTP is not touched
  /// until the RE approves.
  void _showEditPtpSheet(PromiseToPay ptp) {
    final amountCtrl = TextEditingController(text: ptp.amountPromised.toStringAsFixed(0));
    final reasonCtrl = TextEditingController();
    DateTime date = ptp.promiseDate;
    TimeOfDay time = TimeOfDay.fromDateTime(ptp.promiseDate);
    String mode = (ptp.paymentMode == 'WhatsApp') ? 'WhatsApp' : 'Phone Call';
    String? err;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(builder: (context, setSheet) {
        final df = DateFormat('EEE, dd MMM yyyy');
        InputDecoration dec(String label) => InputDecoration(
            labelText: label, border: const OutlineInputBorder(), isDense: true);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.edit_note, color: Color(0xFF0052CC)),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('Edit Recorded PTP',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48)))),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(sheetCtx)),
                ]),
                const SizedBox(height: 4),
                const Text('Your change goes to the Recovery Executive — the PTP updates only once they approve it.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF5A6B87))),
                const SizedBox(height: 16),
                TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: dec('Promise Amount (₹)')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (d != null) setSheet(() => date = d);
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(df.format(date), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: time);
                        if (t != null) setSheet(() => time = t);
                      },
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(time.format(context)),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: dec('Mode of Communication'),
                  items: const [
                    DropdownMenuItem(value: 'Phone Call', child: Text('Phone Call')),
                    DropdownMenuItem(value: 'WhatsApp', child: Text('WhatsApp')),
                  ],
                  onChanged: (v) => setSheet(() => mode = v ?? mode),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: dec('Reason for this edit *')),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: LoadingElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0052CC),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amt <= 0) {
                        setSheet(() => err = 'Enter a valid promise amount.');
                        return;
                      }
                      if (reasonCtrl.text.trim().isEmpty) {
                        setSheet(() => err = 'A reason for the edit is required.');
                        return;
                      }
                      final navigator = Navigator.of(sheetCtx);
                      final store = context.read<AppStore>();
                      final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      try {
                        // PTP edits go through the PTP Correction flow (full
                        // field edit — amount, date + time, payment mode),
                        // not the generic non-PTP Outcome Edit request.
                        await store.requestPtpCorrection(
                          ptp.id, amt, when, reasonCtrl.text.trim(),
                          paymentMode: mode,
                        );
                        navigator.pop();
                        showAppMessageAfter(navigator,
                            message: 'PTP correction request sent to the Recovery Executive for approval.',
                            type: AppMessageType.info,
                            title: 'Sent for Approval');
                      } catch (e) {
                        setSheet(() => err = 'Could not submit: $e');
                      }
                    },
                    child: const Text('Submit for RE Approval',
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          ),
        );
      }),
    );
  }

  Widget _buildRecordedOutcomeCard(
      BuildContext context, Customer c, AppStore store) {
    // If the account is still actionable (not parked) but carries an open
    // PTP, it's the covered/actionable case: a promise was recorded that
    // only covers part of the overdue. Show the PTP itself as the recorded
    // outcome, plus the split, rather than the reconcile "CALL CUSTOMER".
    final openPtp = _openScheduledPtp(store, c.id);
    // The salesman's PTP edit is one-time: locked the moment a correction
    // is requested (Pending) and stays locked after the RE decides it
    // (Approved / Rejected) — only an untouched PTP can still be edited.
    final ptpCorrectionUsed =
        openPtp != null && openPtp.correctionStatus != 'none';
    final ptpCorrectionPending =
        openPtp != null && openPtp.correctionStatus == 'Pending';
    final alreadyRequested = ptpCorrectionUsed ||
        store.hasPendingOutcomeEdit(c.id) ||
        store.outcomeCorrectionRequests
            .any((r) => r.customerId == c.id && r.status == 'Pending');
    final isPartial = c.currentRecoveryState != 'Waiting / Monitoring' && openPtp != null;
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final headline = isPartial
        ? 'Promise to Pay — ${money.format(openPtp.amountPromised)}'
        : c.primaryNextAction;
    final subline = isPartial
        ? 'Due ${DateFormat('EEE, dd MMM yyyy').format(openPtp.promiseDate)}'
            '${c.actionableAmount > 0 ? ' · ${money.format(c.actionableAmount)} still to recover' : ''}'
        : c.reasonForAction;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: Color(0xFF388E3C), size: 18),
              SizedBox(width: 8),
              Text('Recorded Outcome',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1B2B48))),
            ],
          ),
          const SizedBox(height: 10),
          Text(headline,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF0052CC))),
          const SizedBox(height: 2),
          Text(subline,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
          const SizedBox(height: 10),
          if (alreadyRequested)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  ptpCorrectionUsed && !ptpCorrectionPending
                      ? 'PTP correction was reviewed by the RE — no further edits.'
                      : 'Outcome edit submitted — awaiting RE review. No further edits.',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFC2410C),
                      fontWeight: FontWeight.w600)),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _openEditRecordedOutcome,
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Edit recorded outcome'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0052CC),
                  side: const BorderSide(color: Color(0xFF0052CC)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Who owns this account and how to reach them — always visible for RE
  /// (and read-only Manager), not buried inside the Create Task dialog.
  /// Tapping the call icon opens the same Call / WhatsApp choice sheet used
  /// everywhere else in the app (contactActions).
  Widget _buildAssignedSalesmanRow(Customer c, AppStore store) {
    final salesmanId = c.assignedSalesmanId;
    if (salesmanId.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDBA74)),
        ),
        child: const Row(
          children: [
            Icon(Icons.person_off_outlined, size: 16, color: Color(0xFFEA580C)),
            SizedBox(width: 8),
            Text('No Salesman Assigned',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFC2410C))),
          ],
        ),
      );
    }
    final name = store.salesmanDisplayName(salesmanId);
    final phone = store.salesmanPhone(salesmanId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFE3F2FD),
            child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF0052CC), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ASSIGNED SALESMAN',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF5A6B87), letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
              ],
            ),
          ),
          if (phone != null && phone.trim().isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => contactActions(context, phone),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: const Color(0xFF0052CC).withValues(alpha: 0.08), shape: BoxShape.circle),
                child: const Icon(Icons.call, size: 17, color: Color(0xFF0052CC)),
              ),
            )
          else
            const Text('No phone on file', style: TextStyle(fontSize: 10.5, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Customer c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE3F2FD),
                child: Text(avatarInitials(c.name),
                    style: const TextStyle(
                        color: Color(0xFF0052CC),
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(c.name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B2B48)))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF9C4),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('High Priority',
                          style: TextStyle(
                              color: Color(0xFFF57F17),
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Address sits full-width below the avatar + name, not squeezed
          // beside them.
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 14, color: Color(0xFF5A6B87)),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(c.address ?? 'Ghatkopar, Mumbai',
                      style: const TextStyle(
                          color: Color(0xFF5A6B87), fontSize: 12, height: 1.35))),
              const SizedBox(width: 8),
              CallablePhoneNumber(
                phoneNumber: c.contactNumber,
                iconColor: const Color(0xFF5A6B87),
                iconSize: 14,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutstandingSummary(Customer c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Outstanding Summary',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1B2B48))),
              Text('As on ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                  style:
                      const TextStyle(color: Color(0xFF5A6B87), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDataCol(
                  'Total Outstanding',
                  _rupee.format(c.totalOutstanding),
                  const Color(0xFFE53935)),
              _buildDataCol(
                  'Overdue Amount',
                  _rupee.format(c.totalDue),
                  const Color(0xFFE53935)),
              _buildDataCol(
                  'Future Due',
                  _rupee.format(_futureDue(c)),
                  const Color(0xFF0052CC)),
              _buildDataCol(
                  'Credit Days', '${c.creditDays}', const Color(0xFF1B2B48)),
            ],
          ),
          if (c.coveredAmount > 0) ...[
            const Divider(height: 32, color: Color(0xFFEDF2F7)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDataCol(
                    'Under PTP / Dispute / Claim',
                    _rupee.format(c.coveredAmount),
                    const Color(0xFF8A6D0B)),
                _buildDataCol(
                    'To Recover Now',
                    _rupee.format(c.actionableAmount),
                    const Color(0xFFE53935)),
                const SizedBox(width: 80),
              ],
            ),
          ],
          const Divider(height: 32, color: Color(0xFFEDF2F7)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDataCol(
                  'Credit Limit',
                  _rupee.format(c.creditLimit),
                  const Color(0xFF1B2B48)),
              _buildDataCol(
                  'Last Payment Date',
                  c.lastPaymentDate != null
                      ? DateFormat('dd MMM yyyy').format(c.lastPaymentDate!)
                      : 'N/A',
                  const Color(0xFF1B2B48)),
              _buildDataCol(
                  'Last Payment',
                  _rupee.format(c.lastPaymentAmount ?? 0),
                  const Color(0xFF388E3C)),
            ],
          ),
        ],
      ),
    );
  }

  // futureDue is synced straight from BUSY's own FUTURE_DUE_AMOUNT
  // (customerReport.mssql.sql) — read it as-is, no client-side recompute.
  double _futureDue(Customer c) => c.futureDue;

  Widget _buildDataCol(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF5A6B87),
                fontSize: 10,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPaymentTimeline(Customer c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Timeline',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1B2B48))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _timelineBucket('0-30', '0-30 Days', c.age0_30, const Color(0xFFF57C00)),
              _timelineBucket('31-60', '31-60 Days', c.age31_60, const Color(0xFFFBC02D)),
              _timelineBucket('61-90', '61-90 Days', c.age61_90, const Color(0xFF388E3C)),
              _timelineBucket('90+', '90+ Days', c.age90Plus, const Color(0xFF5A6B87)),
            ],
          )
        ],
      ),
    );
  }

  /// A Payment Timeline ageing node made tappable — filters the Invoices tab
  /// to that bucket and jumps to it. `bucket` is the internal key
  /// ('0-30' | '31-60' | '61-90' | '90+').
  Widget _timelineBucket(String bucket, String label, double amount, Color color) {
    return Builder(
      builder: (ctx) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() => _invoiceAgeBucket = bucket);
          DefaultTabController.of(ctx).animateTo(1);
        },
        child: _buildTimelineNode(label, _rupee.format(amount), color, _invoiceAgeBucket == bucket),
      ),
    );
  }

  Widget _buildTimelineNode(
      String label, String sub, Color color, bool isSelected) {
    return Column(
      children: [
        Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: color,
            size: 20),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: isSelected ? color : color,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        Text(sub,
            style: const TextStyle(color: Color(0xFF5A6B87), fontSize: 10)),
      ],
    );
  }

  // Calls done = every recorded outcome (source='Record Outcome' — each one
  // is logged only after the salesperson actually reaches the customer or
  // logs a No Answer attempt); physical visits = completed physicalVisit
  // tasks, identified from TASK_COMPLETED's description (taskService.js
  // embeds the task type in quotes there, there's no separate channel
  // field on the audit event itself).
  Widget _buildRecoveryActivities(Customer c, AppStore store) {
    final callsDone = c.auditHistory
        .where((a) => a.source == 'Record Outcome')
        .length;
    final visitsDone = c.auditHistory
        .where((a) =>
            a.type == 'TASK_COMPLETED' &&
            a.description.contains('"physicalVisit" task'))
        .length;

    final customerPtps = store.ptps.where((p) => p.customerId == c.id).toList();
    final totalPtps = customerPtps.length;
    final totalPtpAmount = customerPtps.fold(0.0, (s, p) => s + p.amountPromised);
    final totalCollected = customerPtps.fold(0.0, (s, p) => s + (p.amountReceived ?? 0));
    final brokenPtps = customerPtps.where((p) => p.status == PtpStatus.broken).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recovery Activities',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1B2B48))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDataCol('Calls Done', '$callsDone', const Color(0xFF1B2B48)),
              _buildDataCol('Physical Visits', '$visitsDone', const Color(0xFF1B2B48)),
              _buildDataCol('Total Collected', _rupee.format(totalCollected), const Color(0xFF388E3C)),
            ],
          ),
          const Divider(height: 32, color: Color(0xFFEDF2F7)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDataCol('Total PTP Amount', _rupee.format(totalPtpAmount), const Color(0xFF1B2B48)),
              _buildDataCol('Total PTPs', '$totalPtps', const Color(0xFF1B2B48)),
              _buildDataCol('Broken PTPs', '${brokenPtps.length}', const Color(0xFFE53935)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(
      IconData icon, String count, String label, Color color, Color bgColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(count,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF5A6B87),
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInvoiceRowNew(Map<String, dynamic> inv) {
    final invNo = (inv['No'] as String?)?.trim().isNotEmpty == true
        ? (inv['No'] as String).trim()
        : ((inv['invoiceNumber'] as String?) ?? '—');

    final dateRaw = inv['Date'] ?? inv['createdAt'];
    final date = (dateRaw is DateTime
            ? dateRaw
            : (dateRaw is String ? DateTime.parse(dateRaw) : DateTime.now()))
        .toLocal();

    final dueDateRaw = inv['DueDate'] ?? inv['dueDate'];
    final DateTime dueDate = (dueDateRaw is DateTime
            ? dueDateRaw
            : (dueDateRaw is String
                ? DateTime.parse(dueDateRaw)
                : date.add(const Duration(days: 15))))
        .toLocal();

    final amt = inv['TotalAmount'] ?? inv['amount'] ?? 0;
    final pendingAmt = inv['PendingAmount'] ?? 0;
    final pendingNum = pendingAmt is num ? pendingAmt : num.tryParse('$pendingAmt') ?? 0;
    final bool cleared = pendingNum <= 0;

    // Days past (positive) or before (negative) the due date — BUSY's synced
    // value when present, otherwise a live calc from the due date.
    final int dueDays = _effectiveDueDays(inv);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EBF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Invoice number + the number that matters most: what's still pending.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 16, color: Color(0xFF5A6B87)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            invNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF0052CC),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!cleared) ...[
                      const SizedBox(height: 6),
                      _dueDaysPill(dueDays),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    cleared ? 'CLEARED' : 'PENDING',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: cleared
                          ? const Color(0xFF388E3C)
                          : const Color(0xFFE53935),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _rupee.format(pendingAmt),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: cleared
                          ? const Color(0xFF388E3C)
                          : const Color(0xFFE53935),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEDF2F7)),
          const SizedBox(height: 12),
          // Supporting detail, each value under a clear label.
          Row(
            children: [
              Expanded(
                child: _invoiceField(
                    'INVOICE DATE', DateFormat('dd MMM yyyy').format(date)),
              ),
              Expanded(
                child: _invoiceField(
                    'DUE DATE', DateFormat('dd MMM yyyy').format(dueDate)),
              ),
              Expanded(
                child: _invoiceField(
                  'AMOUNT',
                  _rupee.format(amt),
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Small coloured pill showing how far an invoice is past (or before) its
  /// due date. `days` is BUSY's `DATEDIFF(DAY, DueDate, GETDATE())`.
  Widget _dueDaysPill(int days) {
    final Color c;
    final String text;
    if (days > 0) {
      c = const Color(0xFFE53935);
      text = '${days}d overdue';
    } else if (days == 0) {
      c = const Color(0xFFF57C00);
      text = 'Due today';
    } else {
      c = const Color(0xFF5A6B87);
      text = 'Due in ${-days}d';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: c,
        ),
      ),
    );
  }

  Widget _invoiceField(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: Color(0xFF97A3B6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1B2B48),
          ),
        ),
      ],
    );
  }

  /// Days past (positive) / before (negative) an invoice's due date. Prefers
  /// BUSY's synced `DueDays`; falls back to a live calc from `DueDate` for
  /// rows synced before that column existed.
  int _effectiveDueDays(Map<String, dynamic> inv) {
    final dd = (inv['DueDays'] as num?)?.toInt();
    if (dd != null) return dd;
    final raw = inv['DueDate'] ?? inv['dueDate'];
    final due = raw is DateTime ? raw : (raw is String ? DateTime.tryParse(raw) : null);
    if (due == null) return 0;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(due.year, due.month, due.day))
        .inDays;
  }

  bool _inAgeBucket(int dd, String bucket) {
    switch (bucket) {
      case '0-30':
        return dd >= 0 && dd <= 30;
      case '31-60':
        return dd >= 31 && dd <= 60;
      case '61-90':
        return dd >= 61 && dd <= 90;
      case '90+':
        return dd > 90;
    }
    return true;
  }

  Widget _buildAllInvoices(Customer c) {
    final bucket = _invoiceAgeBucket;
    final all = c.invoices;

    if (all.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No invoices on file yet.',
              style: TextStyle(color: Color(0xFF5A6B87), fontSize: 14)),
        ),
      );
    }

    final items = bucket == null
        ? all
        : all.where((i) => _inAgeBucket(_effectiveDueDays(i), bucket)).toList();

    num totalPending = 0;
    for (final i in items) {
      final p = i['PendingAmount'] ?? 0;
      totalPending += p is num ? p : num.tryParse('$p') ?? 0;
    }

    final bucketLabel = bucket == null
        ? ''
        : (bucket == '90+' ? '90+ days overdue' : '$bucket days overdue');

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Invoices',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF1B2B48))),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${items.length}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF5A6B87))),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('TOTAL PENDING',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: Color(0xFF97A3B6))),
                    const SizedBox(height: 2),
                    Text(_rupee.format(totalPending),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFFE53935))),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (bucket != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _invoiceAgeBucket = null),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0052CC).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF0052CC).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_alt, size: 13, color: Color(0xFF0052CC)),
                        const SizedBox(width: 5),
                        Text('Ageing: $bucketLabel',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0052CC))),
                        const SizedBox(width: 4),
                        const Icon(Icons.close, size: 13, color: Color(0xFF0052CC)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 32, 16, 32),
              child: Center(
                child: Text('No invoices in this ageing bucket.',
                    style: TextStyle(color: Color(0xFF5A6B87), fontSize: 13)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildInvoiceRowNew(items[i]),
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }

  /// Turns raw audit `type` codes ("SNAPSHOT_REOPENED_RECOVERY") into
  /// readable titles ("Snapshot Reopened Recovery"). Types that are already
  /// human (contain spaces / no underscores) pass through unchanged.
  String _humanizeAuditType(String raw) {
    if (!raw.contains('_')) return raw;
    const acronyms = {
      'RE', 'PTP', 'RMS', 'GST', 'SMS', 'KYC', 'ID', 'UPI', 'NEFT',
      'L1', 'L2', 'L3', 'L4'
    };
    return raw
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) {
          final u = w.toUpperCase();
          if (acronyms.contains(u)) return u;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Reconstructs the fields the Record Outcome form captured, from the
  /// server's flattened audit description. Labels mirror the form
  /// ("Promise Amount", "Promise Date/Time", "Mode of Communication",
  /// "Spoken To", "Notes", "Reason", "Details"). Free-form / system
  /// descriptions with no recognisable structure come back as one
  /// 'Details' entry.
  List<MapEntry<String, String>> _parseAuditDescription(AuditEvent audit) {
    final desc = audit.description;
    final tl = audit.type.toLowerCase();
    final isPtp = tl.contains('ptp') || tl.contains('promise');
    final isFollow = tl.contains('follow') ||
        tl.contains('confirm') ||
        tl.contains('callback');
    final dateLabel =
        isPtp ? 'Promise Date' : (isFollow ? 'Follow-up Date' : 'Date');
    final timeLabel =
        isPtp ? 'Promise Time' : (isFollow ? 'Follow-up Time' : 'Time');
    final amountLabel = isPtp
        ? 'Promise Amount'
        : (tl.contains('dispute') ? 'Disputed Amount' : 'Amount');

    var work = ' $desc ';
    String? grab(RegExp re) {
      final m = re.firstMatch(work);
      if (m == null) return null;
      work = work.replaceRange(m.start, m.end, '  ');
      final v = m.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final amtField = grab(RegExp(
        r'(?:Amount|Amt)\s*:\s*(₹?\s*[\d,][\d,.]*)',
        caseSensitive: false));
    final amtInline = grab(RegExp(
        r'(?:PTP|Payment)\s+of\s+(₹?\s*[\d,][\d,.]*)',
        caseSensitive: false));
    final mode = grab(RegExp(
        r'\bvia\s+([A-Za-z][\w /&+.\-]*?)\s*(?=[.\n]|—|Contact\s*:|$)',
        caseSensitive: false));
    final person = grab(RegExp(
        r'Contact(?:\s*Person)?\s*:\s*([^\n—]+?)\s*(?=—|Date\s*:|Notes?\s*:|$)',
        caseSensitive: false));
    final date = grab(RegExp(
        r'\bDate\s*:\s*([^\n—]+?)\s*(?=Time\s*:|—|Notes?\s*:|$)',
        caseSensitive: false));
    final time = grab(RegExp(
        r'\bTime\s*:\s*([^\n—]+?)\s*(?=—|Notes?\s*:|$)',
        caseSensitive: false));
    final note =
        grab(RegExp(r'Notes?\s*:\s*(.+?)\s*$', caseSensitive: false));
    final reason = grab(RegExp(
        r'Reason\s*:\s*([^\n—]+?)\s*(?=,\s*Amt|—|Notes?\s*:|$)',
        caseSensitive: false));
    final details =
        grab(RegExp(r'Details?\s*:\s*(.+?)\s*$', caseSensitive: false));

    final amount = amtField ?? amtInline;

    var summary = work
        .replaceAll(
            RegExp(r'(?:PTP|Payment)\s+of\s+₹?\s*[\d,][\d,.]*',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s*—\s*'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s.,]+|[\s.,]+$'), '')
        .trim();

    final structured = mode != null ||
        person != null ||
        date != null ||
        time != null ||
        note != null ||
        amount != null ||
        reason != null ||
        details != null;
    if (!structured) return [MapEntry('Details', desc.trim())];

    final out = <MapEntry<String, String>>[];
    void add(String k, String? v) {
      if (v != null && v.trim().isNotEmpty) out.add(MapEntry(k, v.trim()));
    }

    if (summary.length > 3) add('Summary', summary);
    add(amountLabel, amount);
    add('Reason', reason);
    add('Mode of Communication', mode);
    add('Spoken To', person);
    add(dateLabel, date);
    add(timeLabel, time);
    add('Notes', note);
    add('Details', details);
    return out;
  }

  /// Icon + colour for an audit event, by type keyword. Shared by the
  /// History card and the timeline rail so the node dot matches the card.
  ({Color color, Color bg, IconData icon}) _auditVisuals(String type) {
    final t = type.toLowerCase();
    if (t.contains('no answer') || t.contains('no response')) {
      return (color: const Color(0xFFE53935), bg: const Color(0xFFFFEBEE), icon: Icons.phone_missed);
    } else if (t.contains('broken') || t.contains('reject')) {
      return (color: const Color(0xFFE53935), bg: const Color(0xFFFFEBEE), icon: Icons.link_off);
    } else if (t.contains('ptp') ||
        t.contains('promise to pay') ||
        t.contains('payment') ||
        t.contains('paid') ||
        t.contains('receipt')) {
      return (color: const Color(0xFF388E3C), bg: const Color(0xFFE8F5E9), icon: Icons.check_circle_outline);
    } else if (t.contains('approv')) {
      return (color: const Color(0xFF388E3C), bg: const Color(0xFFE8F5E9), icon: Icons.thumb_up_outlined);
    } else if (t.contains('escalat')) {
      return (color: const Color(0xFFDC2626), bg: const Color(0xFFFDECEC), icon: Icons.priority_high);
    } else if (t.contains('dispute')) {
      return (color: const Color(0xFF4F46E5), bg: const Color(0xFFEEF0FF), icon: Icons.gavel_outlined);
    } else if (t.contains('control') || t.contains('supervis')) {
      return (color: const Color(0xFF0052CC), bg: const Color(0xFFE3EDFB), icon: Icons.shield_outlined);
    } else if (t.contains('reassign') || t.contains('owner') || t.contains('instruction')) {
      return (color: const Color(0xFF0D9488), bg: const Color(0xFFE0F2F1), icon: Icons.swap_horiz);
    } else if (t.contains('task')) {
      return (color: const Color(0xFF8E24AA), bg: const Color(0xFFF3E5F5), icon: Icons.check_box_outlined);
    } else if (t.contains('snapshot') || t.contains('reopen')) {
      return (color: const Color(0xFF8E24AA), bg: const Color(0xFFF3E5F5), icon: Icons.autorenew);
    } else if (t.contains('callback') || t.contains('follow-up') || t.contains('confirm')) {
      return (color: const Color(0xFFF57C00), bg: const Color(0xFFFFF3E0), icon: Icons.phone_callback);
    }
    return (color: const Color(0xFF8E24AA), bg: const Color(0xFFF3E5F5), icon: Icons.bolt_outlined);
  }

  /// Wraps a History card in a vertical timeline rail (node dot + connector).
  Widget _timelineEntry({
    required Color color,
    required bool isFirst,
    required bool isLast,
    required Widget child,
  }) {
    const railColor = Color(0xFFD8DEE8);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(width: 2, height: 16, color: isFirst ? Colors.transparent : railColor),
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4)],
                  ),
                ),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : railColor)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(AuditEvent audit) {
    final visuals = _auditVisuals(audit.type);
    final Color iconColor = visuals.color;
    final Color iconBg = visuals.bg;
    final IconData icon = visuals.icon;

    final showTransition = audit.previousState != null &&
        audit.newState != null &&
        audit.previousState!.trim().isNotEmpty &&
        audit.previousState != audit.newState;

    final descParts = _parseAuditDescription(audit);
    final plainOnly = descParts.length == 1 && descParts.first.key == 'Details';
    final tag = _typeTag(audit);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EBF2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: iconColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header — icon, title + type tag, timestamp pill.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration:
                            BoxDecoration(color: iconBg, shape: BoxShape.circle),
                        child: Icon(icon, color: iconColor, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _humanizeAuditType(audit.type),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  height: 1.25,
                                  color: Color(0xFF1B2B48)),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                    color: iconColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('dd MMM yyyy').format(audit.timestamp),
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF64748B)),
                            ),
                            Text(
                              DateFormat('hh:mm a').format(audit.timestamp),
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFF97A3B6)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Body — free-form paragraph, or the labelled detail block.
                  if (plainOnly)
                    Text(
                      descParts.first.value,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Color(0xFF475569)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEDF2F7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < descParts.length; i++) ...[
                            if (i > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 7),
                                child: Divider(
                                    height: 1, color: Color(0xFFEDF2F7)),
                              ),
                            // Title on the left, value on the right.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                    _detailIcon(descParts[i].key,
                                        descParts[i].value),
                                    size: 13,
                                    color: iconColor.withValues(alpha: 0.75)),
                                const SizedBox(width: 7),
                                SizedBox(
                                  width: 108,
                                  child: Text(
                                    descParts[i].key,
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                        color: Color(0xFF64748B)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    descParts[i].value,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: descParts[i].key == 'Notes'
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                      color: const Color(0xFF1F2937),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                  if (showTransition) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _statePill(audit.previousState!, const Color(0xFF94A3B8)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward,
                              size: 12, color: Color(0xFF94A3B8)),
                        ),
                        _statePill(audit.newState!, iconColor),
                      ],
                    ),
                  ],

                  if (audit.attachmentPath != null) ...[
                    const SizedBox(height: 10),
                    _AttachmentThumbnail(path: audit.attachmentPath!),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFEDF2F7)),
                  const SizedBox(height: 10),

                  // Footer — actor + where it came from.
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: iconColor.withValues(alpha: 0.12),
                        child: Text(
                          audit.actor.isNotEmpty
                              ? audit.actor[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: iconColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          audit.actor,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                              color: Color(0xFF1B2B48)),
                        ),
                      ),
                      if (audit.source != 'App') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            audit.source,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statePill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  IconData _detailIcon(String label, String value) {
    final l = label.toLowerCase();
    if (l.contains('summary')) return Icons.notes_outlined;
    if (l.contains('reason')) return Icons.help_outline;
    if (l.contains('amount')) return Icons.currency_rupee;
    if (l.contains('details')) return Icons.description_outlined;
    if (l.contains('spoken') || l.contains('contact person')) {
      return Icons.person_outline;
    }
    if (l.contains('date')) return Icons.event_outlined;
    if (l.contains('time')) return Icons.schedule;
    if (l.contains('note')) return Icons.sticky_note_2_outlined;
    if (l.contains('mode') || l.contains('medium') || l.contains('communication')) {
      final v = value.toLowerCase();
      if (v.contains('whatsapp')) return Icons.chat_outlined;
      if (v.contains('call') || v.contains('phone') || v.contains('mobile')) {
        return Icons.call_outlined;
      }
      if (v.contains('sms') || v.contains('text')) return Icons.sms_outlined;
      if (v.contains('mail')) return Icons.mail_outline;
      if (v.contains('visit') || v.contains('field') || v.contains('person')) {
        return Icons.directions_walk;
      }
      return Icons.forum_outlined;
    }
    return Icons.fiber_manual_record;
  }

  String _typeTag(AuditEvent a) {
    if (a.source.toLowerCase().contains('snapshot') ||
        a.actor.toLowerCase() == 'system') {
      return 'SYSTEM';
    }
    final t = a.type.toLowerCase();
    if (t.contains('ptp') || t.contains('promise to pay')) return 'PTP';
    if (t.contains('payment') || t.contains('paid') || t.contains('receipt')) {
      return 'PAYMENT';
    }
    if (t.contains('dispute')) return 'DISPUTE';
    if (t.contains('escalat')) return 'ESCALATION';
    if (t.contains('no answer')) return 'NO ANSWER';
    if (t.contains('task')) return 'TASK';
    if (t.contains('control') || t.contains('supervis')) return 'RE CONTROL';
    if (t.contains('reassign') || t.contains('owner')) return 'OWNERSHIP';
    if (t.contains('follow') ||
        t.contains('confirm') ||
        t.contains('callback')) {
      return 'FOLLOW-UP';
    }
    return 'UPDATE';
  }

  Widget _buildFullHistory(Customer c) {
    final items = [...c.auditHistory]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    int total = items.length;
    int ptpPaid = items
        .where((a) =>
            a.type.toLowerCase().contains('ptp') ||
            a.type.toLowerCase().contains('payment'))
        .length;
    int noAnswer =
        items.where((a) => a.type.toLowerCase().contains('no answer')).length;
    int others = total - ptpPaid - noAnswer;

    // "Last Contact" — how long since the most recent recorded action.
    String lastContact;
    if (items.isEmpty) {
      lastContact = '—';
    } else {
      final d = DateTime.now().difference(items.first.timestamp);
      if (d.inDays >= 30) {
        lastContact = '${(d.inDays / 30).floor()}mo';
      } else if (d.inDays >= 7) {
        lastContact = '${(d.inDays / 7).floor()}w';
      } else if (d.inDays >= 1) {
        lastContact = '${d.inDays}d';
      } else if (d.inHours >= 1) {
        lastContact = '${d.inHours}h';
      } else {
        lastContact = 'now';
      }
    }

    // The scrollable feed itself is server-paginated (_historyItems,
    // loaded via _loadMoreHistory) — `items`/`total` above stay sourced
    // from the customer detail fetch's full auditHistory purely for the
    // aggregate stat cards and the "History (N)" header count, which need
    // a true total, not just what's been paged in so far.
    final shown = _historyItems;
    final hasMore = _historyHasMore;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            !_historyLoading &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 300) {
          // Deferred to after this frame — scroll notifications fire
          // during layout/paint, and calling setState synchronously here
          // trips Flutter's "setState called during build" assertion.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadMoreHistory();
          });
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSummaryStat(
                            Icons.update,
                            lastContact,
                            'Last Contact',
                            const Color(0xFF0052CC),
                            const Color(0xFFE3F2FD)),
                        _buildSummaryStat(
                            Icons.check_circle_outline,
                            ptpPaid.toString(),
                            'PTP / Paid',
                            const Color(0xFF388E3C),
                            const Color(0xFFE8F5E9)),
                        _buildSummaryStat(
                            Icons.phone_missed,
                            noAnswer.toString(),
                            'No Answer',
                            const Color(0xFFE53935),
                            const Color(0xFFFFEBEE)),
                        _buildSummaryStat(
                            Icons.more_horiz,
                            others.toString(),
                            'Other',
                            const Color(0xFF8E24AA),
                            const Color(0xFFF3E5F5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('History (${items.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF1B2B48))),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (shown.isEmpty && _historyLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0052CC)))),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _timelineEntry(
                    color: _auditVisuals(shown[i].type).color,
                    isFirst: i == 0,
                    isLast: i == shown.length - 1 && !hasMore,
                    child: _buildHistoryRow(shown[i]),
                  ),
                  childCount: shown.length,
                ),
              ),
            ),
          if (_historyLoading && shown.isNotEmpty)
            const SliverPadding(
              padding: EdgeInsets.symmetric(vertical: 16),
              sliver: SliverToBoxAdapter(
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF0052CC)))),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }

  Future<void> _showOutcomeBottomSheet() async {
    final store = context.read<AppStore>();
    final c = store.customers.firstWhere((x) => x.id == widget.customer.id, orElse: () => widget.customer);
    final hasOpenPhysicalVisit = store.tasks.any((t) =>
        t.customerId == c.id &&
        t.type == TaskType.physicalVisit &&
        t.status != TaskStatus.completed);

    // A Physical Visit needs photo proof regardless of what the customer
    // said — ask for it before showing any outcome option, since PTP / Will
    // Confirm / Unable-Refused don't collect their own attachment at all
    // (see _finish, which falls back to this for whichever outcome gets
    // picked). Cancelling the picker cancels recording the outcome too.
    if (hasOpenPhysicalVisit) {
      final photo = await pickEvidenceFile(context);
      if (photo == null) return;
      if (!mounted) return;
      _pendingVisitPhoto = photo;
    } else {
      _pendingVisitPhoto = null;
    }

    final outcomes = [
      {
        'title': 'Promise to Pay (PTP)',
        'desc': 'Schedule a payment promise',
        'icon': Icons.handshake,
        'color': const Color(0xFF8E24AA)
      },
      {
        'title': 'Payment Already Made',
        'desc': 'Record a payment that was already made',
        'icon': Icons.check_circle,
        'color': const Color(0xFF388E3C)
      },
      {
        'title': 'Will Confirm',
        'desc': 'Customer needs time to check',
        'icon': Icons.watch_later,
        'color': const Color(0xFF0052CC)
      },
      {
        'title': 'No Answer',
        'desc': 'Customer did not pick up',
        'icon': Icons.phone_missed,
        'color': const Color(0xFFE53935)
      },
      {
        'title': 'Dispute Raised',
        'desc': 'Customer raised an issue',
        'icon': Icons.warning,
        'color': const Color(0xFFF57C00)
      },
      {
        'title': 'Unable / Refused',
        'desc': 'Customer refused to commit',
        'icon': Icons.cancel,
        'color': const Color(0xFF5A6B87)
      },
      {
        'title': 'Internal Action',
        'desc': 'Requires internal follow-up',
        'icon': Icons.assignment,
        'color': const Color(0xFF00897B)
      },
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                            color: Color(0xFFF8F9FB),
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20))),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                  color: Color(0xFFE3F2FD),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.record_voice_over,
                                  color: Color(0xFF0052CC), size: 18),
                            ),
                            const SizedBox(width: 12),
                            const Text('Record Outcome',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFF1B2B48))),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Color(0xFF5A6B87)),
                              onPressed: () => Navigator.pop(ctx),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      if (_pendingVisitPhoto != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
                                SizedBox(width: 8),
                                Text('Visit photo attached', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                              ],
                            ),
                          ),
                        ),
                      if (_selectedOutcome == null)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: outcomes.map((o) {
                              final title = o['title'] as String;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.grey.withValues(alpha: 0.2)),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setModalState(
                                        () => _selectedOutcome = title);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                              color: (o['color'] as Color)
                                                  .withValues(alpha: 0.1),
                                              shape: BoxShape.circle),
                                          child: Icon(o['icon'] as IconData,
                                              color: o['color'] as Color,
                                              size: 24),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(title,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color:
                                                          Color(0xFF1B2B48))),
                                              const SizedBox(height: 2),
                                              Text(o['desc'] as String,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Color(0xFF5A6B87))),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right,
                                            color: Color(0xFFA0AEC0)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => setModalState(
                                      () => _selectedOutcome = null),
                                  icon: const Icon(Icons.arrow_back,
                                      color: Color(0xFF0052CC), size: 18),
                                  label: const Text('Back to Outcomes',
                                      style: TextStyle(
                                          color: Color(0xFF0052CC),
                                          fontWeight: FontWeight.bold)),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildOutcomeForm(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Advancing the recovery queue tears this screen down along with the
      // sheet — don't setState on a defunct State.
      if (mounted) setState(() => _selectedOutcome = null);
    });
  }

  /// The contact name from this customer's most recent interaction that
  /// recorded one ("… Contact: `<name>` …" in the audit description) — used to
  /// pre-fill "Person Spoken To" on the PTP form. Null if none on record.
  String? _lastContactPerson() {
    final store = context.read<AppStore>();
    final c = store.customers.firstWhere((x) => x.id == widget.customer.id,
        orElse: () => widget.customer);
    final items = [...c.auditHistory]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final re = RegExp(r'Contact:\s*([^—\n]+)');
    for (final e in items) {
      final m = re.firstMatch(e.description);
      if (m != null) {
        final name = m.group(1)!.trim().replaceAll(RegExp(r'[.\s]+$'), '');
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  Widget _buildOutcomeForm() {
    // Cap the amount fields at the still-uncovered slice of the overdue.
    // While part of the balance is already under a PTP / dispute / payment
    // claim, the salesperson can only act on what's left — actionableAmount
    // (server-derived, customer detail only; 0 on plain list rows, in which
    // case fall back to the full outstanding).
    final fresh = context.read<AppStore>().customers.firstWhere(
        (x) => x.id == widget.customer.id,
        orElse: () => widget.customer);
    final amountCeiling = fresh.actionableAmount > 0
        ? fresh.actionableAmount
        : fresh.totalOutstanding;
    switch (_selectedOutcome) {
      case 'Promise to Pay (PTP)':
        return PtpOutcomeForm(
            maxOutstanding: amountCeiling,
            initialPerson: _lastContactPerson() ?? widget.customer.name,
            onSubmit: (data) {
          final amt = data['amount'];
          final DateTime? pickedDate = data['date'];
          final TimeOfDay? pickedTime = data['time'];
          final date = pickedDate != null
              ? '${pickedDate.day}/${pickedDate.month}/${pickedDate.year}'
              : '';
          final time = pickedTime != null
              ? '${pickedTime.hour}:${pickedTime.minute}'
              : '';
          final contact = data['person'];
          final mode = data['mode'];
          final notes = (data['notes'] as String?) ?? '';
          final combinedDateTime = pickedDate != null && pickedTime != null
              ? DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
                  pickedTime.hour, pickedTime.minute)
              : null;
          return _finish(
            context,
            'PTP Scheduled',
            'PTP of ₹$amt via $mode. Contact: $contact',
            'Date: $date Time: $time${notes.isNotEmpty ? ' — Notes: $notes' : ''}',
            ptpAmountValue: (amt as num?)?.toDouble(),
            ptpDate: combinedDateTime,
            ptpMode: mode as String?,
          );
        });
      case 'Will Confirm':
        return WillConfirmForm(onSubmit: (date, time) {
          final followUpAt =
              DateTime(date.year, date.month, date.day, time.hour, time.minute);
          return _finish(context, 'Follow-up Scheduled', 'Customer will confirm',
              'Date: ${DateFormat('yyyy-MM-dd').format(date)} Time: ${time.format(context)}',
              followUpAt: followUpAt);
        });
      case 'Payment Already Made':
        return PaymentAlreadyMadeForm(
            maxOutstanding: amountCeiling,
            onSubmit: (amt, file) => _finish(context, 'Verification Pending',
                'Payment claimed', 'Amount: ₹$amt', screenshot: file));
      case 'No Answer':
        return NoAnswerForm(
          attemptNumber:
              context.read<AppStore>().noAnswerAttemptCount(widget.customer.id),
          onSubmit: (screenshot) => _finish(
              context, 'Call Customer', 'No Answer', 'Next Call needed',
              screenshot: screenshot),
        );
      case 'Dispute Raised':
        return DisputeForm(
            maxOutstanding: amountCeiling,
            onSubmit: (amt, reason, file) => _finish(
                context,
                'Management Instruction',
                'Dispute Raised',
                'Reason: $reason, Amt: ₹$amt',
                screenshot: file));
      case 'Unable / Refused':
        return UnableToCommitForm(
            onSubmit: (reason, notes) => _finish(
                context,
                // Was 'Management Instruction' — a name collision with the
                // unrelated real RE/Manager-issued directive feature (see
                // manager_management_attention_screen.dart), which made the
                // NEXT ACTION card show that meaningless label instead of
                // reflecting the call-back this outcome actually drives.
                'Call Customer',
                'Customer Refused',
                'Reason: $reason Notes: $notes'));
      case 'Internal Action':
        return InternalActionForm(
            onSubmit: (action, file) => _finish(context, 'Action Required',
                'Internal Task', 'Details: $action',
                screenshot: file));
      default:
        return const SizedBox();
    }
  }

  Future<void> _finish(
      BuildContext context, String nextAction, String reason, String details,
      {DateTime? followUpAt,
      double? ptpAmountValue,
      DateTime? ptpDate,
      String? ptpMode,
      XFile? screenshot}) async {
    final store = context.read<AppStore>();
    final navigator = Navigator.of(context);
    var queuedForSync = false;
    // The chosen outcome form's own attachment (e.g. Payment Already Made's
    // payment screenshot) takes priority when there is one; otherwise fall
    // back to the visit photo collected up front in _showOutcomeBottomSheet
    // — outcomes like PTP / Will Confirm / Unable-Refused never collect
    // their own, so without this a Physical Visit could go through with no
    // evidence attached at all.
    final effectiveScreenshot = screenshot ?? _pendingVisitPhoto;

    try {
      try {
        await store.recordOutcome(widget.customer.id, nextAction, reason, details,
            followUpAt: followUpAt,
            ptpAmountValue: ptpAmountValue,
            ptpDate: ptpDate,
            ptpMode: ptpMode,
            screenshot: effectiveScreenshot);
      } on QueuedForSyncException {
        // No network right now — the outcome is saved locally and will
        // sync automatically once signal returns (see AppStore's offline
        // write queue). Treat this the same as a successful submission for
        // navigation purposes; only the message differs below.
        queuedForSync = true;
      }

      if (widget.recoveryQueue) {
        final visited = <String>{
          ...?widget.queueVisitedIds,
          widget.customer.id,
        };
        final next = store.getNextCustomer(excludeIds: visited);
        if (next != null) {
          // Advance to the next customer, but drop every earlier queue
          // screen (and this outcome sheet) so Back always returns to the
          // dashboard — never to an already-completed customer.
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => Customer360Screen(
                      customer: next,
                      recoveryQueue: true,
                      queueVisitedIds: visited,
                    )),
            (route) => route.isFirst,
          );
          showAppMessageAfter(navigator,
              message: queuedForSync
                  ? 'Saved — will sync once you\'re back online. Next customer.'
                  : 'Outcome recorded: $nextAction — next customer');
          return;
        }
        navigator.popUntil((route) => route.isFirst);
        showAppMessageAfter(navigator,
            message: queuedForSync
                ? 'Saved — will sync once you\'re back online. All customers processed — great work!'
                : 'Outcome recorded: $nextAction. All customers processed — great work!');
        return;
      }

      navigator.pop();
      showAppMessageAfter(navigator,
          message: queuedForSync ? 'Saved — will sync once you\'re back online' : 'Outcome recorded: $nextAction',
          type: AppMessageType.success);
    } catch (e) {
      showAppMessageAfter(navigator,
          message: 'Could not record outcome: $e', type: AppMessageType.error);
    }
  }

  /// RE creates a routine follow-up task for the salesperson on this
  /// customer — Call Customer or Physical Visit.
  void _showCreateTaskDialog(
      BuildContext context, AppStore store, Customer customer) {
    final reasonController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    String priority = 'Normal';
    String taskType = 'customerCall';
    String? reasonError;
    final salesmanId = customer.assignedSalesmanId;
    final salesmanName = salesmanId.isEmpty
        ? 'the assigned salesperson'
        : store.salesmanDisplayName(salesmanId);
    final salesmanPhone = salesmanId.isEmpty ? null : store.salesmanPhone(salesmanId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(builder: (context, setState) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                          color: const Color(0xFF0052CC).withValues(alpha: 0.08),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.add_task,
                          color: Color(0xFF0052CC), size: 18)),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text('Create Task',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1B2B48)))),
                  IconButton(
                      icon: const Icon(Icons.close,
                          size: 20, color: Color(0xFF5A6B87)),
                      onPressed: () => Navigator.pop(sheetCtx)),
                ]),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Assigns a follow-up task to $salesmanName on ${customer.name}.',
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF5A6B87), height: 1.4),
                      ),
                    ),
                    if (salesmanPhone != null && salesmanPhone.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => contactActions(context, salesmanPhone),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.call, size: 18, color: Color(0xFF0052CC)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Task Type *',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B2B48))),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Call Customer'),
                      selected: taskType == 'customerCall',
                      onSelected: (_) => setState(() => taskType = 'customerCall'),
                      selectedColor: const Color(0xFF0052CC).withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: taskType == 'customerCall'
                              ? const Color(0xFF0052CC)
                              : const Color(0xFF5A6B87)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Physical Visit'),
                      selected: taskType == 'physicalVisit',
                      onSelected: (_) => setState(() => taskType = 'physicalVisit'),
                      selectedColor: const Color(0xFF0052CC).withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: taskType == 'physicalVisit'
                              ? const Color(0xFF0052CC)
                              : const Color(0xFF5A6B87)),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('Task Details *',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B2B48))),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                      hintText: taskType == 'physicalVisit'
                          ? 'e.g. Visit the customer premises and collect payment'
                          : 'e.g. Call the customer and confirm payment position',
                      border: const OutlineInputBorder(),
                      errorText: reasonError),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Priority *',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B2B48))),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10)),
                          items: ['Critical', 'High', 'Normal', 'Low']
                              .map((p) =>
                                  DropdownMenuItem(value: p, child: Text(p)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => priority = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Deadline *',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B2B48))),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 30)));
                            if (picked != null) {
                              setState(() => selectedDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 13),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(4)),
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(selectedDate),
                                      style: const TextStyle(fontSize: 13)),
                                  const Icon(Icons.calendar_today,
                                      size: 15, color: Color(0xFF5A6B87)),
                                ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: LoadingElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0052CC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      if (reasonController.text.trim().isEmpty) {
                        setState(() => reasonError = 'Task details are required');
                        return;
                      }
                      final navigator = Navigator.of(context);
                      try {
                        await store.assignManagementInstruction(
                            customer.id,
                            salesmanId,
                            reasonController.text.trim(),
                            selectedDate,
                            priority: priority,
                            taskType: taskType);
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        showAppMessageAfter(navigator,
                            message: 'Task assigned to agent.');
                      } catch (e) {
                        showAppMessageAfter(navigator,
                            message: 'Could not create task: $e',
                            isError: true);
                      }
                    },
                    child: const Text('Create Task',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

}

/// A small call-evidence thumbnail on a History row, tap-to-enlarge. The
/// attachments endpoint requires authentication (see
/// ApiClient.attachmentUrl/attachmentAuthHeaders), which Image.network
/// doesn't send by default — passed explicitly as `headers` here.
class _AttachmentThumbnail extends StatelessWidget {
  final String path;
  const _AttachmentThumbnail({required this.path});

  @override
  Widget build(BuildContext context) {
    final apiClient = context.read<AppStore>().apiClient;
    final url = apiClient.attachmentUrl(path);
    final headers = apiClient.attachmentAuthHeaders;

    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(url, headers: headers, fit: BoxFit.contain),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          headers: headers,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) =>
              progress == null ? child : const SizedBox(width: 72, height: 72, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          errorBuilder: (ctx, error, stack) => Container(
            width: 72,
            height: 72,
            color: const Color(0xFFF3F4F6),
            child: const Icon(Icons.broken_image_outlined, color: Color(0xFFA0AEC0), size: 20),
          ),
        ),
      ),
    );
  }
}
