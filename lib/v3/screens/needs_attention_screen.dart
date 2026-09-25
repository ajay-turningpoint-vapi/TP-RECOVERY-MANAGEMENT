import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/escalation_case.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v3/screens/task_details_screen_v3.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/escalations_screen.dart';
import 'package:salesman_mobile/widgets/data_loading.dart'
    show LoadingAppBarStrip;

const _dark = Color(0xFF0F172A);
const _navy = Color(0xFF1B2B48);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFEEF1F5);
const _bg = Color(0xFFF8FAFC);

final _rupee =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

const _red = Color(0xFFDC2626);
const _purple = Color(0xFF9333EA);
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

Color _avatarColorFor(String name) =>
    _avatarPalette[name.hashCode.abs() % _avatarPalette.length];

String _initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts
      .map((p) => p.isNotEmpty ? p[0] : '')
      .take(2)
      .join()
      .toUpperCase();
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
  // Only the account-health tabs live here now — every discrete actionable
  // item (tasks, visits, disputes, PTP corrections, outcome edits, broken
  // PTPs, underperformers) lives in RE Tasks. Deep-links for removed tabs
  // fall back to "All".
  static const _liveTabs = {0, 9, 10, 12, 13, 14};
  late int _activeTab =
      _liveTabs.contains(widget.initialTab) ? widget.initialTab : 0;
  String _query = '';
  String get _branchFilter => context.read<AppStore>().branchFilter;
  _SortOrder _sort = _SortOrder.amountDesc;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // Shared filter for the customer-centric problem queues below.
    final q = _query.toLowerCase();
    bool custMatches(Customer c) {
      if (_branchFilter != 'All Branches' && c.branch != _branchFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          store
              .salesmanDisplayName(c.assignedSalesmanId)
              .toLowerCase()
              .contains(q) ||
          c.contactNumber.contains(q);
    }

    List<Customer> filterCust(List<Customer> src) {
      final list = src.where(custMatches).toList()
        ..sort((a, b) => b.totalDue.compareTo(a.totalDue));
      return list;
    }

    // ---- Section 9: Customers with No Next Action set (recovery not being driven) ----
    final noNextAction = filterCust(store.noValidNextActionCustomers);

    // ---- Section 10: Stalled — no follow-up in days ----
    final stalled = filterCust(store.noFollowUpAccounts);

    // ---- Section 12: Open Escalations (RE-owned recovery) ----
    var escalations = store.openEscalationCases.where((e) {
      if (q.isEmpty) return true;
      return e.customerName.toLowerCase().contains(q) ||
          store.salesmanDisplayName(e.ownerId).toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    // ---- Section 13: Ownerless accounts (money due, nobody assigned) ----
    final ownerless = filterCust(store.ownerMappingRequiredCustomers);

    // ---- Section 14: High-risk / critical accounts ----
    final highRisk = filterCust(store.atRiskAccounts);

    final total = noNextAction.length +
        stalled.length +
        escalations.length +
        ownerless.length +
        highRisk.length;
    final branches = store.branchOptions;

    final tabs = <_TabData>[
      _TabData('All ($total)', null, null, 0),
      _TabData('No Next Action (${noNextAction.length})', Icons.help_outline,
          _amber, 9),
      _TabData(
          'Stalled (${stalled.length})', Icons.hourglass_bottom, _amber, 10),
      _TabData('Escalations (${escalations.length})', Icons.priority_high,
          _purple, 12),
      _TabData('Ownerless (${ownerless.length})', Icons.person_off_outlined,
          _pink, 13),
      _TabData('High Risk (${highRisk.length})', Icons.warning_amber_rounded,
          _red, 14),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _navy,
        centerTitle: true,
        title: const Text('NEEDS YOUR ATTENTION',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: _navy,
                letterSpacing: 0.3)),
        actions: [
          TextButton.icon(
            onPressed: () => _showFilterSheet(context, branches),
            icon: const Icon(Icons.filter_alt_outlined,
                size: 16, color: Color(0xFF2563EB)),
            label: const Text('Filter',
                style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ],
        bottom: const LoadingAppBarStrip(color: Color(0xFF2563EB)),
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
                              Icon(Icons.verified_outlined,
                                  size: 44, color: Color(0xFF16A34A)),
                              SizedBox(height: 10),
                              Text('Nothing needs your attention right now.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: _muted,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        if (_activeTab == 0 || _activeTab == 9)
                          _sectionCustomers(
                              context,
                              'NO NEXT ACTION SET',
                              'Salesman has not decided a recovery step',
                              noNextAction,
                              _amber,
                              Icons.help_outline,
                              9,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 10)
                          _sectionCustomers(
                              context,
                              'STALLED — NO FOLLOW-UP',
                              'No contact logged in 4+ days',
                              stalled,
                              _amber,
                              Icons.hourglass_bottom,
                              10,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 12)
                          _sectionEscalations(context, store, escalations,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 13)
                          _sectionCustomers(
                              context,
                              'OWNERLESS ACCOUNTS',
                              'Money due with no salesman assigned',
                              ownerless,
                              _pink,
                              Icons.person_off_outlined,
                              13,
                              limit: _activeTab == 0 ? 3 : null),
                        if (_activeTab == 0 || _activeTab == 14)
                          _sectionCustomers(
                              context,
                              'HIGH-RISK ACCOUNTS',
                              'Escalated, 60+ days overdue, or critical credit health',
                              highRisk,
                              _red,
                              Icons.warning_amber_rounded,
                              14,
                              limit: _activeTab == 0 ? 3 : null),
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
                  color: active ? color.withValues(alpha: 0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: active ? color.withValues(alpha: 0.4) : _border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.icon != null) ...[
                      Icon(t.icon, size: 13, color: color),
                      const SizedBox(width: 5)
                    ],
                    Text(t.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: active ? color : _muted)),
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
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 12, color: _dark),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _bg,
                  prefixIcon: const Icon(Icons.search, size: 18, color: _muted),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  hintText: 'Search by Salesman / Customer / Mobile / Invoice',
                  hintStyle: const TextStyle(fontSize: 11.5, color: _muted),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _border)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showSortSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border)),
              child: const Row(
                children: [
                  Icon(Icons.swap_vert, size: 15, color: Color(0xFF2563EB)),
                  SizedBox(width: 4),
                  Text('Sort by',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _dark)),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
      title: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: _sort == order
          ? const Icon(Icons.check, color: Color(0xFF2563EB))
          : null,
      onTap: () {
        setState(() => _sort = order);
        Navigator.pop(context);
      },
    );
  }

  void _showFilterSheet(BuildContext context, List<String> branches) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter by Branch',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                      context.read<AppStore>().setBranchFilter(b);
                      setState(() {});
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
  Widget _sectionHeader(String title, int count, Color color, IconData icon,
      VoidCallback onViewAll) {
    return Container(
      color: color.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color,
                    letterSpacing: 0.3)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(20)),
            constraints: const BoxConstraints(minWidth: 20),
            child: Text('$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onViewAll,
            child: Text('View All',
                style: TextStyle(
                    color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border)),
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
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ---- Section hint line under a header ----
  Widget _sectionHint(String text) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5, color: _muted, fontStyle: FontStyle.italic)),
      );

  // ---- Generic customer-problem section (No Next Action / Stalled / Ownerless / High Risk) ----
  Widget _sectionCustomers(BuildContext context, String title, String hint,
      List<Customer> list, Color color, IconData icon, int tabIndex,
      {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown =
        limit != null && list.length > limit ? list.take(limit).toList() : list;
    final store = context.read<AppStore>();
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(title, list.length, color, icon,
            () => setState(() => _activeTab = tabIndex)),
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
              onTap: () => _openCustomer(context, store, c),
            )),
        if (limit != null && list.length > limit)
          _sectionFooter('View All (${list.length}) ›', color,
              () => setState(() => _activeTab = tabIndex)),
      ],
    ));
  }

  /// A customer with an open task opens that task's details; one without
  /// falls through to the customer screen, where the RE can create one.
  void _openCustomer(BuildContext context, AppStore store, Customer c) {
    final open = store.tasks
        .where((t) => t.customerId == c.id && t.status != TaskStatus.completed)
        .toList()
      ..sort((a, b) => a.deadline.compareTo(b.deadline));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => open.isEmpty
            ? Customer360Screen(customer: c)
            : TaskDetailsScreenV3(task: open.first),
      ),
    );
  }

  String _levelLabel(String level) => level == 'L4'
      ? 'L4 · MANAGEMENT'
      : (level == 'L3' ? 'L3 · RE CONTROL' : 'L2 · RE SUPERVISION');

  Widget _escalationCard(AppStore store, EscalationCase e, VoidCallback onTap) {
    final color = levelColor(e.level);
    final overdue = e.deadline.isBefore(DateTime.now());
    final owner =
        e.ownerId.isEmpty ? 'Unassigned' : store.salesmanDisplayName(e.ownerId);
    Widget detail(IconData icon, String label, String value,
            {Color? valueColor}) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: _muted),
              const SizedBox(width: 8),
              SizedBox(
                  width: 58,
                  child: Text(label,
                      style: const TextStyle(fontSize: 11, color: _muted))),
              Expanded(
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: valueColor ?? _dark))),
            ],
          ),
        );
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border))),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                  width: 4,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2))),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(_levelLabel(e.level),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: color)),
                        ),
                        const Spacer(),
                        Text(_rupee.format(e.moneyAtRisk),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _red)),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right,
                            size: 18, color: _muted),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(e.customerName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: _dark)),
                    if (e.reason.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(e.reason,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: _muted, height: 1.35)),
                    ],
                    const SizedBox(height: 4),
                    detail(Icons.person_outline, 'Owner', owner),
                    if (e.plan.trim().isNotEmpty)
                      detail(Icons.assignment_outlined, 'Plan', e.plan),
                    detail(
                      Icons.schedule,
                      'Deadline',
                      overdue
                          ? '${DateFormat('dd MMM, hh:mm a').format(e.deadline)} · Overdue'
                          : DateFormat('dd MMM, hh:mm a').format(e.deadline),
                      valueColor: overdue ? _red : _dark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Section 12: Open Escalations ----
  Widget _sectionEscalations(
      BuildContext context, AppStore store, List<EscalationCase> list,
      {int? limit}) {
    if (list.isEmpty) return const SizedBox();
    final shown =
        limit != null && list.length > limit ? list.take(limit).toList() : list;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('OPEN ESCALATIONS', list.length, _purple,
            Icons.priority_high, () => setState(() => _activeTab = 12)),
        _sectionHint(
            'RE-owned recovery cases — action per the escalation plan before the deadline.'),
        ...shown.map((e) => _escalationCard(
              store,
              e,
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EscalationsScreen(focusCaseId: e.id))),
            )),
        if (limit != null && list.length > limit)
          _sectionFooter('View All (${list.length}) ›', _purple,
              () => setState(() => _activeTab = 12)),
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
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border))),
        child: Row(
          children: [
            CircleAvatar(
                radius: 16,
                backgroundColor: avatarColor.withValues(alpha: 0.15),
                child: Text(avatarText,
                    style: TextStyle(
                        color: avatarColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: _dark)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 10.5, color: _muted)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col2Label,
                      style: const TextStyle(fontSize: 9.5, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(col2Value,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: col2Color))),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col3Label,
                      style: const TextStyle(fontSize: 9.5, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(col3Value,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: col3Color))),
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
