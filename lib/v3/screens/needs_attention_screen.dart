import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/escalation_case.dart';
import 'package:salesman_mobile/v2/models/outcome_edit_request.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/attention_detail_screen.dart';
import 'package:salesman_mobile/v3/screens/visit_review_screen.dart';
import 'package:salesman_mobile/v3/screens/dispute_review_screen.dart';
import 'package:salesman_mobile/v3/screens/ptp_correction_review_screen.dart';
import 'package:salesman_mobile/v3/screens/task_extension_review_screen.dart';
import 'package:salesman_mobile/v3/screens/outcome_edit_detail_screen.dart';
import 'package:salesman_mobile/v3/screens/escalations_screen.dart';

const _dark = Color(0xFF0F172A);
const _navy = Color(0xFF1B2B48);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFEEF1F5);
const _bg = Color(0xFFF8FAFC);

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

const _red = Color(0xFFDC2626);
const _orange = Color(0xFFEA580C);
const _purple = Color(0xFF9333EA);
const _indigo = Color(0xFF4F46E5);
const _teal = Color(0xFF0D9488);
const _amber = Color(0xFFB45309);
const _pink = Color(0xFFDB2777);

const List<Color> _avatarPalette = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
];

Color _avatarColorFor(String name) => _avatarPalette[name.hashCode.abs() % _avatarPalette.length];

String _initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase();
}

enum _SortOrder { amountDesc, amountAsc, recent }

class NeedsAttentionScreen extends StatefulWidget {
  // Lets a specific "Needs Your Attention" tile (or stat card) deep-link
  // straight to its own section instead of always landing on "All" —
  // see the tile onTaps in control_dashboard_screen.dart.
  final int initialTab;
  const NeedsAttentionScreen({super.key, this.initialTab = 0});

  @override
  State<NeedsAttentionScreen> createState() => _NeedsAttentionScreenState();
}

class _NeedsAttentionScreenState extends State<NeedsAttentionScreen> {
  late int _activeTab = widget.initialTab; // 0 All, 1 No Call, 2 Overdue Targets, 3 Visits, 4 Disputes
  String _query = '';
  String _branchFilter = 'All Branches';
  _SortOrder _sort = _SortOrder.amountDesc;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // ---- Section 1: Salesmen No Call Today ----
    // No real call-log data source exists anywhere in the server (the old
    // figure was a fabricated client-side Random()), so this section is
    // honestly always empty rather than showing a fake count — kept as its
    // own tab/section (not removed outright) so a real call-log feature can
    // slot in here later without a further UI restructure.
    final List<Map<String, dynamic>> noCall = [];

    // ---- Section 2: Salesmen Overdue Targets ----
    var overdueTargets = store.salesmen.where((s) => (s['collectionAchievedPercent'] as int) < 60).toList();
    if (_branchFilter != 'All Branches') overdueTargets = overdueTargets.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == _branchFilter).toList();
    if (_query.isNotEmpty) overdueTargets = overdueTargets.where((s) => (s['name'] as String).toLowerCase().contains(_query.toLowerCase())).toList();
    overdueTargets.sort((a, b) => (a['collectionAchievedPercent'] as int).compareTo(b['collectionAchievedPercent'] as int));

    // ---- Section 3: Physical Visits Pending Review ----
    var visits = store.physicalVisitsPendingReview;
    if (_query.isNotEmpty) visits = visits.where((t) => t.customerName.toLowerCase().contains(_query.toLowerCase()) || t.ownerId.toLowerCase().contains(_query.toLowerCase())).toList();
    visits = [...visits]..sort((a, b) => _sort == _SortOrder.recent
        ? (b.completedAt ?? b.deadline).compareTo(a.completedAt ?? a.deadline)
        : (b.completedAt ?? b.deadline).compareTo(a.completedAt ?? a.deadline));

    // ---- Section 4: Disputes Awaiting Review ----
    // 'Awaiting Verification' belongs to the canonical in-progress bucket
    // (AppStore._disputeInProgressStatuses), not awaiting-review — matching
    // store.disputesAwaitingReviewCount / needsAttentionBadgeCount exactly,
    // which is what the dashboard tile linking here actually counts.
    var disputesAwaiting = store.disputes.where((d) => d['status'] == 'Pending Approval').toList();
    if (_query.isNotEmpty) disputesAwaiting = disputesAwaiting.where((d) => (d['customer'] as String).toLowerCase().contains(_query.toLowerCase())).toList();
    disputesAwaiting.sort((a, b) => _sort == _SortOrder.amountAsc
        ? ((a['amount'] as num).toDouble()).compareTo((b['amount'] as num).toDouble())
        : ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()));

    // ---- Section 5: PTP Correction Requests ----
    var ptpCorrections = store.ptpCorrectionRequests;
    if (_query.isNotEmpty) {
      ptpCorrections = ptpCorrections.where((p) {
        final c = store.customers.firstWhere((c) => c.id == p.customerId, orElse: () => store.customers.first);
        return c.name.toLowerCase().contains(_query.toLowerCase());
      }).toList();
    }

    // ---- Section 6: Task Extension Requests ----
    var taskExtensions = store.tasks.where((t) => t.approvalStatus == 'Pending').toList();
    if (_query.isNotEmpty) taskExtensions = taskExtensions.where((t) => t.customerName.toLowerCase().contains(_query.toLowerCase())).toList();

    // ---- Section 7: Outcome Correction Requests ----
    var outcomeEdits = store.pendingOutcomeEdits;
    if (_query.isNotEmpty) outcomeEdits = outcomeEdits.where((r) => r.customerName.toLowerCase().contains(_query.toLowerCase())).toList();

    // Shared filter for the customer-centric problem queues below.
    final q = _query.toLowerCase();
    bool custMatches(Customer c) {
      if (_branchFilter != 'All Branches' && c.branch != _branchFilter) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          store.salesmanDisplayName(c.assignedSalesmanId).toLowerCase().contains(q) ||
          c.contactNumber.contains(q);
    }

    List<Customer> filterCust(List<Customer> src) {
      final list = src.where(custMatches).toList()..sort((a, b) => b.totalDue.compareTo(a.totalDue));
      return list;
    }

    // ---- Section 8: Salesmen with Overdue Tasks (not working their queue) ----
    final overdueByOwner = <String, List<AppTask>>{};
    for (final t in store.tasks.where((t) => t.isOverdue)) {
      (overdueByOwner[t.ownerId] ??= []).add(t);
    }
    var overdueTaskGroups = overdueByOwner.entries
        .map((e) => {
              'salesmanId': e.key,
              'name': store.salesmanDisplayName(e.key),
              'count': e.value.length,
              'oldest': e.value.map((t) => t.deadline).reduce((a, b) => a.isBefore(b) ? a : b),
              'exposure': e.value.fold<double>(0, (s, t) {
                final c = store.customers.where((c) => c.id == t.customerId);
                return s + (c.isEmpty ? 0 : c.first.totalDue);
              }),
            })
        .toList();
    if (q.isNotEmpty) overdueTaskGroups = overdueTaskGroups.where((g) => (g['name'] as String).toLowerCase().contains(q)).toList();
    overdueTaskGroups.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    // ---- Section 9: Customers with No Next Action set (recovery not being driven) ----
    final noNextAction = filterCust(store.noValidNextActionCustomers);

    // ---- Section 10: Stalled — no follow-up in days ----
    final stalled = filterCust(store.noFollowUpAccounts);

    // ---- Section 11: Broken PTPs needing RE review / escalation ----
    var brokenPtpRows = store.brokenPtps
        .map((p) {
          final match = store.customers.where((c) => c.id == p.customerId);
          return match.isEmpty ? null : {'ptp': p, 'customer': match.first};
        })
        .whereType<Map<String, dynamic>>()
        .where((m) => custMatches(m['customer'] as Customer))
        .toList();
    brokenPtpRows.sort((a, b) => (b['ptp'] as PromiseToPay).amountPromised.compareTo((a['ptp'] as PromiseToPay).amountPromised));

    // ---- Section 12: Open Escalations (RE-owned recovery) ----
    var escalations = store.openEscalationCases.where((e) {
      if (q.isEmpty) return true;
      return e.customerName.toLowerCase().contains(q) || store.salesmanDisplayName(e.ownerId).toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    // ---- Section 13: Ownerless accounts (money due, nobody assigned) ----
    final ownerless = filterCust(store.ownerMappingRequiredCustomers);

    // ---- Section 14: High-risk / critical accounts ----
    final highRisk = filterCust(store.atRiskAccounts);

    final total = noCall.length +
        overdueTargets.length +
        overdueTaskGroups.length +
        noNextAction.length +
        stalled.length +
        brokenPtpRows.length +
        escalations.length +
        ownerless.length +
        highRisk.length +
        visits.length +
        disputesAwaiting.length +
        ptpCorrections.length +
        taskExtensions.length +
        outcomeEdits.length;
    final branches = ['All Branches', ...{for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}];

    final tabs = <_TabData>[
      _TabData('All ($total)', null, null, 0),
      _TabData('Overdue Targets (${overdueTargets.length})', Icons.trending_down, _orange, 2),
      _TabData('Overdue Tasks (${overdueTaskGroups.length})', Icons.assignment_late_outlined, _red, 8),
      _TabData('No Next Action (${noNextAction.length})', Icons.help_outline, _amber, 9),
      _TabData('Stalled (${stalled.length})', Icons.hourglass_bottom, _amber, 10),
      _TabData('Broken PTPs (${brokenPtpRows.length})', Icons.link_off, _red, 11),
      _TabData('Escalations (${escalations.length})', Icons.priority_high, _purple, 12),
      _TabData('Ownerless (${ownerless.length})', Icons.person_off_outlined, _pink, 13),
      _TabData('High Risk (${highRisk.length})', Icons.warning_amber_rounded, _red, 14),
      _TabData('Visits (${visits.length})', Icons.location_on_outlined, _purple, 3),
      _TabData('Disputes (${disputesAwaiting.length})', Icons.description_outlined, _indigo, 4),
      _TabData('PTP Corrections (${ptpCorrections.length})', Icons.swap_horiz, _teal, 5),
      _TabData('Task Extensions (${taskExtensions.length})', Icons.schedule, _amber, 6),
      _TabData('Outcome Edits (${outcomeEdits.length})', Icons.edit_note, _pink, 7),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _navy,
        centerTitle: true,
        title: const Text('NEEDS YOUR ATTENTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navy, letterSpacing: 0.3)),
        actions: [
          TextButton.icon(
            onPressed: () => _showFilterSheet(context, branches),
            icon: const Icon(Icons.filter_alt_outlined, size: 16, color: Color(0xFF2563EB)),
            label: const Text('Filter', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabs(tabs),
          _buildSearchSort(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (total == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Column(children: [
                              Icon(Icons.verified_outlined, size: 44, color: Color(0xFF16A34A)),
                              SizedBox(height: 10),
                              Text('Nothing needs your attention right now.', style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        if (_activeTab == 0 || _activeTab == 1)
                          _sectionNoCall(context, noCall, limit: _activeTab == 0 ? 5 : null),
                        if (_activeTab == 0 || _activeTab == 2)
                          _sectionOverdueTargets(context, overdueTargets, limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 8)
                          _sectionOverdueTasks(context, overdueTaskGroups, limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 9)
                          _sectionCustomers(context, 'NO NEXT ACTION SET', 'Salesman has not decided a recovery step', noNextAction, _amber, Icons.help_outline, 9,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 10)
                          _sectionCustomers(context, 'STALLED — NO FOLLOW-UP', 'No contact logged in 4+ days', stalled, _amber, Icons.hourglass_bottom, 10,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 11)
                          _sectionBrokenPtps(context, brokenPtpRows, limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 12)
                          _sectionEscalations(context, store, escalations, limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 13)
                          _sectionCustomers(context, 'OWNERLESS ACCOUNTS', 'Money due with no salesman assigned', ownerless, _pink, Icons.person_off_outlined, 13,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 14)
                          _sectionCustomers(context, 'HIGH-RISK ACCOUNTS', 'Escalated, 60+ days overdue, or critical credit health', highRisk, _red, Icons.warning_amber_rounded, 14,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 3)
                          _sectionVisits(context, store, visits, limit: _activeTab == 0 ? 4 : null),
                        if (_activeTab == 0 || _activeTab == 4)
                          _sectionDisputes(context, disputesAwaiting, limit: _activeTab == 0 ? 4 : null),
                        if (_activeTab == 0 || _activeTab == 5)
                          _sectionPtpCorrections(context, store, ptpCorrections, limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 6)
                          _sectionTaskExtensions(context, taskExtensions, limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 7)
                          _sectionOutcomeEdits(context, outcomeEdits, limit: _activeTab == 0 ? 3 : null),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  Widget _buildTabs(List<_TabData> tabs) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final t = tabs[i];
            final active = _activeTab == t.index;
            final color = t.color ?? const Color(0xFF2563EB);
            return GestureDetector(
              onTap: () => setState(() => _activeTab = t.index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? color.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? color.withOpacity(0.4) : _border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.icon != null) ...[Icon(t.icon, size: 13, color: color), const SizedBox(width: 5)],
                    Text(t.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? color : _muted)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchSort() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 16, color: _muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(fontSize: 12, color: _dark),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search by Salesman / Customer / Mobile / Invoice',
                        hintStyle: TextStyle(fontSize: 11.5, color: _muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showSortSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
              child: const Row(
                children: [
                  Icon(Icons.swap_vert, size: 15, color: Color(0xFF2563EB)),
                  SizedBox(width: 4),
                  Text('Sort by', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sortOption('Amount: High to Low', _SortOrder.amountDesc),
            _sortOption('Amount: Low to High', _SortOrder.amountAsc),
            _sortOption('Most Recent', _SortOrder.recent),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(String label, _SortOrder order) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: _sort == order ? const Icon(Icons.check, color: Color(0xFF2563EB)) : null,
      onTap: () {
        setState(() => _sort = order);
        Navigator.pop(context);
      },
    );
  }

  void _showFilterSheet(BuildContext context, List<String> branches) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter by Branch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: branches.map((b) {
                  final selected = _branchFilter == b;
                  return ChoiceChip(
                    label: Text(b, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _branchFilter = b);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  Widget _sectionHeader(String title, int count, Color color, IconData icon, VoidCallback onViewAll) {
    return Container(
      color: color.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color, letterSpacing: 0.3)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            constraints: const BoxConstraints(minWidth: 20),
            child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onViewAll,
            child: Text('View All', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Every section is rendered as its own bordered, rounded white card with
  /// spacing below it — matching the card convention used everywhere else
  /// in the app — instead of edge-to-edge rows with no visual boundary.
  Widget _sectionCard(Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: child,
    );
  }

  Widget _sectionFooter(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ---- Section 1 ----
  Widget _sectionNoCall(BuildContext context, List<Map<String, dynamic>> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('SALESMEN NO CALL TODAY', list.length, _red, Icons.phone_missed_outlined, () => setState(() => _activeTab = 1)),
        ...shown.map((s) {
          final display = (s['fullName'] as String?) ?? (s['name'] as String);
          return _rowTile(
            context: context,
            avatarText: _initialsFor(display),
            avatarColor: _avatarColorFor(display),
            title: display,
            subtitle: '${s['customers']} Customers',
            col2Label: 'Overdue Amount',
            col2Value: _rupee.format(s['totalOverdue']),
            col2Color: _red,
            col3Label: 'Last Call Made',
            col3Value: DateFormat('dd MMM yyyy').format(s['lastCallDate']),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttentionDetailScreen(salesmanName: s['name'], category: AttentionCategory.noCall))),
          );
        }),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _red, () => setState(() => _activeTab = 1)),
      ],
    ));
  }

  // ---- Section 2 ----
  Widget _sectionOverdueTargets(BuildContext context, List<Map<String, dynamic>> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('SALESMEN OVERDUE TARGETS', list.length, _orange, Icons.person_outline, () => setState(() => _activeTab = 2)),
        ...shown.map((s) {
          final display = (s['fullName'] as String?) ?? (s['name'] as String);
          return _rowTile(
            context: context,
            avatarText: _initialsFor(display),
            avatarColor: _avatarColorFor(display),
            title: display,
            subtitle: 'Target: ${_rupee.format(s['collectionTarget'])}',
            col2Label: 'Achieved',
            col2Value: '${_rupee.format(s['collectionAchieved'])} (${s['collectionAchievedPercent']}%)',
            col2Color: _orange,
            col3Label: 'Overdue Amount',
            col3Value: _rupee.format(s['totalOverdue']),
            col3Color: _orange,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttentionDetailScreen(salesmanName: s['name'], category: AttentionCategory.overdueTargets))),
          );
        }),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _orange, () => setState(() => _activeTab = 2)),
      ],
    ));
  }

  // ---- Section 3 ----
  Widget _sectionVisits(BuildContext context, AppStore store, List<AppTask> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('PHYSICAL VISITS PENDING REVIEW', list.length, _purple, Icons.location_on_outlined, () => setState(() => _activeTab = 3)),
        ...shown.map((t) {
          final dispute = store.disputes.cast<Map<String, dynamic>?>().firstWhere((d) => d != null && d['customer'] == t.customerName, orElse: () => null);
          final amountLabel = dispute != null ? 'Amount in Dispute' : 'Outstanding';
          final amountValue = dispute != null ? _rupee.format(dispute['amount']) : _rupee.format(store.customers.firstWhere((c) => c.id == t.customerId, orElse: () => store.customers.first).totalDue);
          return _visitRow(context, t, amountLabel, amountValue);
        }),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _purple, () => setState(() => _activeTab = 3)),
      ],
    ));
  }

  Widget _visitRow(BuildContext context, AppTask t, String amountLabel, String amountValue) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisitReviewScreen(taskId: t.id))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: _avatarColorFor(t.customerName).withOpacity(0.15), child: Text(_initialsFor(t.customerName), style: TextStyle(color: _avatarColorFor(t.customerName), fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                  const SizedBox(height: 2),
                  Text('Visited by: ${context.read<AppStore>().salesmanDisplayName(t.ownerId)}', style: const TextStyle(fontSize: 10.5, color: _muted)),
                  Text(DateFormat('dd MMM yyyy · hh:mm a').format(t.completedAt ?? t.deadline), style: const TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(amountLabel, style: const TextStyle(fontSize: 9.5, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(amountValue, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _purple))),
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Text('AWAITING REVIEW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: _purple)),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: _muted),
          ],
        ),
      ),
    );
  }

  // ---- Section 4 ----
  Widget _sectionDisputes(BuildContext context, List<Map<String, dynamic>> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('DISPUTES AWAITING REVIEW', list.length, _indigo, Icons.description_outlined, () => setState(() => _activeTab = 4)),
        ...shown.map((d) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DisputeReviewScreen(disputeId: d['id']))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
                child: Row(
                  children: [
                    CircleAvatar(radius: 16, backgroundColor: _avatarColorFor(d['customer']).withOpacity(0.15), child: Text(_initialsFor(d['customer']), style: TextStyle(color: _avatarColorFor(d['customer']), fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['customer'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                          const SizedBox(height: 2),
                          Text(d['reason'], style: const TextStyle(fontSize: 10.5, color: _muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_rupee.format(d['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _indigo)),
                        const SizedBox(height: 2),
                        Text(d['status'], style: const TextStyle(fontSize: 9.5, color: _muted)),
                      ],
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                  ],
                ),
              ),
            )),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _indigo, () => setState(() => _activeTab = 4)),
      ],
    ));
  }

  // ---- Section 5: PTP Correction Requests ----
  Widget _sectionPtpCorrections(BuildContext context, AppStore store, List<PromiseToPay> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('PTP CORRECTION REQUESTS', list.length, _teal, Icons.swap_horiz, () => setState(() => _activeTab = 5)),
        ...shown.map((p) {
          final c = store.customers.firstWhere((c) => c.id == p.customerId, orElse: () => store.customers.first);
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PtpCorrectionReviewScreen(ptpId: p.id))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
              child: Row(
                children: [
                  CircleAvatar(radius: 16, backgroundColor: _avatarColorFor(c.name).withOpacity(0.15), child: Text(_initialsFor(c.name), style: TextStyle(color: _avatarColorFor(c.name), fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                        const SizedBox(height: 2),
                        Text('${_rupee.format(p.amountPromised)} → ${_rupee.format(p.correctionRequestedAmount ?? p.amountPromised)}', style: const TextStyle(fontSize: 10.5, color: _muted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text('PENDING', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: _teal)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: _muted),
                ],
              ),
            ),
          );
        }),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _teal, () => setState(() => _activeTab = 5)),
      ],
    ));
  }

  // ---- Section 6: Task Extension Requests ----
  Widget _sectionTaskExtensions(BuildContext context, List<AppTask> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('TASK EXTENSION REQUESTS', list.length, _amber, Icons.schedule, () => setState(() => _activeTab = 6)),
        ...shown.map((t) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskExtensionReviewScreen(taskId: t.id))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
                child: Row(
                  children: [
                    CircleAvatar(radius: 16, backgroundColor: _avatarColorFor(t.customerName).withOpacity(0.15), child: Text(_initialsFor(t.customerName), style: TextStyle(color: _avatarColorFor(t.customerName), fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                          const SizedBox(height: 2),
                          Text('${DateFormat('dd MMM').format(t.deadline)} → ${t.pendingDeadline != null ? DateFormat('dd MMM').format(t.pendingDeadline!) : '-'}', style: const TextStyle(fontSize: 10.5, color: _muted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _amber.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: const Text('PENDING', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: _amber)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                  ],
                ),
              ),
            )),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _amber, () => setState(() => _activeTab = 6)),
      ],
    ));
  }

  // ---- Section 7: Outcome Correction Requests ----
  Widget _sectionOutcomeEdits(BuildContext context, List<OutcomeEditRequest> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('OUTCOME EDIT REQUESTS', list.length, _pink, Icons.edit_note, () => setState(() => _activeTab = 7)),
        ...shown.map((r) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OutcomeEditDetailScreen(requestId: r.id))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
                child: Row(
                  children: [
                    CircleAvatar(radius: 16, backgroundColor: _avatarColorFor(r.customerName).withOpacity(0.15), child: Text(_initialsFor(r.customerName), style: TextStyle(color: _avatarColorFor(r.customerName), fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                          const SizedBox(height: 2),
                          Text('Edit ${r.outcomeKind} outcome', style: const TextStyle(fontSize: 10.5, color: _muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('by ${context.read<AppStore>().salesmanDisplayName(r.salesmanId)}', style: const TextStyle(fontSize: 9.5, color: _muted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _pink.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: const Text('PENDING', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: _pink)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                  ],
                ),
              ),
            )),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _pink, () => setState(() => _activeTab = 7)),
      ],
    ));
  }

  // ---- Section hint line under a header ----
  Widget _sectionHint(String text) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Text(text, style: const TextStyle(fontSize: 10.5, color: _muted, fontStyle: FontStyle.italic)),
      );

  // ---- Section 8: Salesmen with Overdue Tasks ----
  Widget _sectionOverdueTasks(BuildContext context, List<Map<String, dynamic>> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('SALESMEN WITH OVERDUE TASKS', list.length, _red, Icons.assignment_late_outlined, () => setState(() => _activeTab = 8)),
        _sectionHint('Assigned tasks past their deadline — the salesman is not working their queue.'),
        ...shown.map((g) => _rowTile(
              context: context,
              avatarText: _initialsFor(g['name'] as String),
              avatarColor: _avatarColorFor(g['name'] as String),
              title: g['name'] as String,
              subtitle: 'Oldest overdue: ${DateFormat('dd MMM').format(g['oldest'] as DateTime)}',
              col2Label: 'Overdue Tasks',
              col2Value: '${g['count']}',
              col2Color: _red,
              col3Label: 'Exposure',
              col3Value: _rupee.format(g['exposure']),
              col3Color: _red,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttentionDetailScreen(salesmanName: g['salesmanId'] as String, category: AttentionCategory.overdueTargets))),
            )),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _red, () => setState(() => _activeTab = 8)),
      ],
    ));
  }

  // ---- Generic customer-problem section (No Next Action / Stalled / Ownerless / High Risk) ----
  Widget _sectionCustomers(BuildContext context, String title, String hint, List<Customer> list, Color color, IconData icon, int tabIndex, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    final store = context.read<AppStore>();
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(title, list.length, color, icon, () => setState(() => _activeTab = tabIndex)),
        _sectionHint(hint),
        ...shown.map((c) => _rowTile(
              context: context,
              avatarText: _initialsFor(c.name),
              avatarColor: _avatarColorFor(c.name),
              title: c.name,
              subtitle: c.assignedSalesmanId.isEmpty
                  ? 'Unassigned · ${c.branch}'
                  : '${store.salesmanDisplayName(c.assignedSalesmanId)} · ${c.branch}',
              col2Label: 'Outstanding',
              col2Value: _rupee.format(c.totalDue),
              col2Color: color,
              col3Label: 'Overdue Days',
              col3Value: '${c.oldestOverdueDays}d',
              col3Color: c.oldestOverdueDays >= 60 ? _red : _dark,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
            )),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', color, () => setState(() => _activeTab = tabIndex)),
      ],
    ));
  }

  // ---- Section 11: Broken PTPs ----
  Widget _sectionBrokenPtps(BuildContext context, List<Map<String, dynamic>> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    final store = context.read<AppStore>();
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('BROKEN PTPs', list.length, _red, Icons.link_off, () => setState(() => _activeTab = 11)),
        _sectionHint('Promises the customer failed — review and escalate or set the next action.'),
        ...shown.map((m) {
          final p = m['ptp'] as PromiseToPay;
          final c = m['customer'] as Customer;
          return _rowTile(
            context: context,
            avatarText: _initialsFor(c.name),
            avatarColor: _avatarColorFor(c.name),
            title: c.name,
            subtitle: 'Promised ${DateFormat('dd MMM').format(p.promiseDate)} · ${store.salesmanDisplayName(c.assignedSalesmanId)}',
            col2Label: 'PTP Amount',
            col2Value: _rupee.format(p.amountPromised),
            col2Color: _red,
            col3Label: 'Outstanding',
            col3Value: _rupee.format(c.totalDue),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
          );
        }),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _red, () => setState(() => _activeTab = 11)),
      ],
    ));
  }

  // ---- Section 12: Open Escalations ----
  Widget _sectionEscalations(BuildContext context, AppStore store, List<EscalationCase> list, {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown = limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('OPEN ESCALATIONS', list.length, _purple, Icons.priority_high, () => setState(() => _activeTab = 12)),
        _sectionHint('RE-owned recovery cases — action per the escalation plan before the deadline.'),
        ...shown.map((e) {
          final match = store.customers.where((c) => c.id == e.customerId);
          return _rowTile(
            context: context,
            avatarText: _initialsFor(e.customerName),
            avatarColor: _avatarColorFor(e.customerName),
            title: e.customerName,
            subtitle: e.reason,
            col2Label: 'Level',
            col2Value: e.level,
            col2Color: _purple,
            col3Label: 'At Risk',
            col3Value: _rupee.format(e.moneyAtRisk),
            col3Color: _red,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => match.isEmpty ? const EscalationsScreen() : Customer360Screen(customer: match.first))),
          );
        }),
        if (limit != null && list.length > limit) _sectionFooter('View All (${list.length}) ›', _purple, () => setState(() => _activeTab = 12)),
      ],
    ));
  }

  Widget _rowTile({
    required BuildContext context,
    required String avatarText,
    required Color avatarColor,
    required String title,
    required String subtitle,
    required String col2Label,
    required String col2Value,
    required Color col2Color,
    required String col3Label,
    required String col3Value,
    Color col3Color = _dark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: avatarColor.withOpacity(0.15), child: Text(avatarText, style: TextStyle(color: avatarColor, fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 10.5, color: _muted)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col2Label, style: const TextStyle(fontSize: 9.5, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(col2Value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: col2Color))),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col3Label, style: const TextStyle(fontSize: 9.5, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(col3Value, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: col3Color))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _TabData {
  final String label;
  final IconData? icon;
  final Color? color;
  final int index;
  _TabData(this.label, this.icon, this.color, this.index);
}
