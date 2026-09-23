import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v3/screens/disputes_tab.dart';
import 'package:salesman_mobile/v3/screens/company_recovery_queue_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_team_recovery_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_priority_accounts_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_alerts_reminders_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_management_attention_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_daily_recovery_summary_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_ptp_report_screen.dart';

const _bg = Color(0xFFF7F8FA);
const _dark = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _border = Color(0xFFEEF1F5);
const _blue = Color(0xFF2563EB);
const _green = Color(0xFF16A34A);
const _orange = Color(0xFFEA580C);
const _red = Color(0xFFDC2626);
const _purple = Color(0xFF9333EA);

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _lakh(double v) => '₹${(v / 100000).toStringAsFixed(2)}L';

// Sales Team Performance table columns — fixed widths (not Expanded/flex)
// so a salesman name gets real room instead of being squeezed by the
// numeric columns; scrolls horizontally when it doesn't fit instead of
// shrinking everything down to illegible text.
const double _perfColName = 120;
const double _perfColTarget = 90;
const double _perfColCollected = 90;
const double _perfColAchv = 55;
const double _perfColScore = 70;
const double _perfColGap = 8;
const double _perfTableWidth = _perfColName + _perfColTarget + _perfColCollected + _perfColAchv + _perfColScore + _perfColGap * 4;

// Top 5 Overdue Customers table columns — same reasoning.
const double _overdueColName = 150;
const double _overdueColAmount = 100;
const double _overdueColDays = 50;
const double _overdueColGap = 10;
const double _overdueTableWidth = _overdueColName + _overdueColAmount + _overdueColDays + _overdueColGap * 2;

class ManagerDashboardScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  const ManagerDashboardScreen({super.key, required this.onNavigate});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  String _branchFilter = 'All Branches';
  int _visibleSalesmen = 5;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    List<Map<String, dynamic>> salesmen = store.salesmen;
    List<Customer> topOverdue = store.topOverdueCustomers;
    if (_branchFilter != 'All Branches') {
      // Same null-safe fallback as the filter's own option list below —
      // otherwise selecting 'Turning Point' would compare it against a raw
      // null and match nobody.
      salesmen = salesmen.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == _branchFilter).toList();
      topOverdue = store.customers.where((c) => c.totalDue > 0 && c.branch == _branchFilter).toList()
        ..sort((a, b) => b.totalDue.compareTo(a.totalDue));
      topOverdue = topOverdue.take(5).toList();
    }
    final visibleSalesmen = salesmen.take(_visibleSalesmen).toList();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(store),
                  _buildDateBranchRow(store),
                  const SizedBox(height: 14),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildStatCards(context, store)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildManagementAttention(context, store)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildCollectionsTrend(store)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildOutstandingAgeing(store)),
                  const SizedBox(height: 20),
                  // Dispute Overview and PTP Overview stacked one below another.
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildDisputeOverview(store)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildPtpOverview(store)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildPerformanceSection(context, salesmen, visibleSalesmen)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildTopOverdueCustomers(context, topOverdue)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildAlerts(context, store)),
                  const SizedBox(height: 20),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildQuickActions(context, store)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header (no hamburger, no notification bell)
  // -------------------------------------------------------------------
  Widget _buildHeader(AppStore store) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manager Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: _dark)),
          SizedBox(height: 2),
          Text("Welcome back! Here's the overview of today's recovery.", style: TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDateBranchRow(AppStore store) {
    // s['branch'] is null for the overwhelming majority of real salesmen
    // (BUSY sync never populates it — confirmed live: 30 of 32 users) — an
    // unguarded `as String` here crashed this whole screen for every
    // Manager on load. 'Turning Point' groups them under one real, honest
    // filter option rather than a crash.
    final branches = store.branchOptions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_outlined, size: 14, color: _dark),
                const SizedBox(width: 6),
                Text(DateFormat('dd MMM yyyy').format(DateTime.now()), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _branchFilter,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 15, color: _muted),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark),
                items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                onChanged: (v) => setState(() {
                  _branchFilter = v!;
                  _visibleSalesmen = 5;
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Stat cards
  // -------------------------------------------------------------------
  Widget _buildStatCards(BuildContext context, AppStore store) {
    final cards = [
      _StatCardData(Icons.currency_rupee, _blue, 'Total Outstanding', _rupee.format(store.teamTotalOutstanding), 'From ${store.visibleCustomers.length} Customers',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen()))),
      _StatCardData(Icons.fact_check_outlined, _green, 'Amount Collected Today', _rupee.format(store.todaysCollectedAmount), 'From ${store.todaysCollectedCustomerCount} Customers',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerDailyRecoverySummaryScreen()))),
      _StatCardData(Icons.gps_fixed, _purple, "Today's Target (All)", _rupee.format(store.companyCollectionTargetToday), 'Achieved ${store.companyCollectionAchievedTodayPercent}%',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerDailyRecoverySummaryScreen()))),
      _StatCardData(Icons.hourglass_empty, _orange, 'PTP Due Today', _rupee.format(store.dueTodayPtpAmount), 'From ${store.dueTodayPtpCount} PTPs',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerPtpReportScreen()))),
      _StatCardData(Icons.warning_amber_rounded, _red, 'Overdue Amount', _rupee.format(store.overdueCustomersAmount), 'From ${store.overdueCustomersCount} Customers',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen()))),
      _StatCardData(Icons.shield_outlined, _red, 'Money at Risk', _rupee.format(store.moneyAtRisk), 'From ${store.atRiskAccounts.length} Accounts (de-duplicated)',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerPriorityAccountsScreen()))),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: cards.map((c) => _statCard(c)).toList(),
    );
  }

  Widget _statCard(_StatCardData c) {
    return InkWell(
      onTap: c.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: c.color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(c.icon, color: c.color, size: 15),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(c.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _muted, fontWeight: FontWeight.w600, height: 1.2))),
              ],
            ),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(c.value, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: _dark))),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(c.sub, style: const TextStyle(fontSize: 10, color: _muted, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Management Attention (L4 cases — top of the escalation ladder)
  // -------------------------------------------------------------------
  Widget _buildManagementAttention(BuildContext context, AppStore store) {
    final l4Cases = store.l4Cases;
    final moneyAtRisk = l4Cases.fold<double>(0.0, (s, c) => s + c.moneyAtRisk);
    return _card(
      title: 'Management Attention',
      onViewDetails: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerManagementAttentionScreen())),
      child: Row(
        children: [
          // Each figure drills into the same detail screen the card's own
          // "View Details" link goes to — a manager reaching for the
          // specific number they care about (e.g. "Money at Risk") no
          // longer has to first find the small header link instead.
          Expanded(child: _attentionStat(context, 'L4 Cases', '${l4Cases.length}', _red)),
          Expanded(child: _attentionStat(context, 'Money at Risk', _lakh(moneyAtRisk), _red)),
          Expanded(child: _attentionStat(context, 'Pending Instr.', '${store.mgmtInstructionCount}', _purple)),
          Expanded(child: _attentionStat(context, 'High-Risk A/Cs', '${store.highRiskAccounts.length}', _orange)),
        ],
      ),
    );
  }

  Widget _attentionStat(BuildContext context, String label, String value, Color color) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerManagementAttentionScreen())),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Collections Trend
  // -------------------------------------------------------------------
  Widget _buildCollectionsTrend(AppStore store) {
    final trend = store.collectionsTrendLast7Days;
    final maxVal = trend.fold<double>(0, (m, t) => [m, (t['expected'] as num).toDouble(), (t['actual'] as num).toDouble()].reduce((a, b) => a > b ? a : b));
    final chartMax = maxVal <= 0 ? 100000.0 : maxVal * 1.2;

    return _card(
      title: 'Collections Trend (Last 7 Days)',
      onViewDetails: () => widget.onNavigate(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legendDot(_blue, 'Expected'),
              const SizedBox(width: 14),
              _legendDot(_green, 'Actual'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: chartMax,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, m) => Text(_lakh(v), style: const TextStyle(fontSize: 8.5, color: _muted)))),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= trend.length) return const SizedBox();
                        return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'] as String, style: const TextStyle(fontSize: 8.5, color: _muted)));
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['expected'] as num).toDouble())],
                    isCurved: true,
                    color: _blue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['actual'] as num).toDouble())],
                    isCurved: true,
                    color: _green,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: _green.withValues(alpha: 0.08)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Outstanding Ageing
  // -------------------------------------------------------------------
  Widget _buildOutstandingAgeing(AppStore store) {
    final buckets = store.outstandingAgeingBuckets;
    final total = buckets.values.fold(0.0, (a, b) => a + b);
    final colors = {'Not Due': _green, '0 - 30 Days': _orange, '31 - 60 Days': _red, '61 - 90 Days': _purple, '90+ Days': const Color(0xFF7F1D1D)};

    return _card(
      title: 'Outstanding Ageing',
      onViewDetails: () => widget.onNavigate(3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 38,
                    sectionsSpace: 2,
                    sections: buckets.entries.where((e) => e.value > 0).map((e) {
                      return PieChartSectionData(value: e.value, color: colors[e.key], radius: 24, showTitle: false);
                    }).toList(),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _dark))),
                    const Text('Total Outstanding', textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: _muted, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: buckets.entries.map((e) {
                final pct = total <= 0 ? 0.0 : (e.value / total * 100);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[e.key], shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: _dark, fontWeight: FontWeight.w600))),
                      Text('${_rupee.format(e.value)} (${pct.toStringAsFixed(2)}%)', style: const TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Dispute Overview
  // -------------------------------------------------------------------
  Widget _buildDisputeOverview(AppStore store) {
    final overview = store.disputeOverviewByStatus;
    final tiles = [
      _MiniStat(Icons.hourglass_empty, _orange, '${overview['Awaiting Review']!['count']}', _rupee.format((overview['Awaiting Review']!['amount'] as num).toDouble()), 'Awaiting Review'),
      _MiniStat(Icons.autorenew, _purple, '${overview['In Progress']!['count']}', _rupee.format((overview['In Progress']!['amount'] as num).toDouble()), 'In Progress'),
      _MiniStat(Icons.check_circle_outline, _green, '${overview['Resolved']!['count']}', _rupee.format((overview['Resolved']!['amount'] as num).toDouble()), 'Resolved'),
      _MiniStat(Icons.cancel_outlined, _red, '${overview['Rejected']!['count']}', _rupee.format((overview['Rejected']!['amount'] as num).toDouble()), 'Rejected'),
    ];

    return _card(
      title: 'Dispute Overview',
      onViewDetails: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DisputesTab())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniStatRow(tiles),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _footerStat('Total Disputes', '${store.totalDisputesCount}')),
              Expanded(child: _footerStat('Amount', _rupee.format(store.totalDisputesAmount))),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // PTP Overview
  // -------------------------------------------------------------------
  Widget _buildPtpOverview(AppStore store) {
    final p = store.ptpOverviewStats;
    final tiles = [
      _MiniStat(Icons.swap_horiz, _blue, '${p['givenCount']}', _rupee.format(((p['givenAmount'] as num).toDouble())), 'PTP Given'),
      _MiniStat(Icons.check_circle_outline, _green, '${p['keptCount']}', _rupee.format(((p['keptAmount'] as num).toDouble())), 'Kept'),
      _MiniStat(Icons.close, _red, '${p['brokenCount']}', _rupee.format(((p['brokenAmount'] as num).toDouble())), 'Broken'),
      _MiniStat(Icons.event_outlined, _orange, '${p['dueTodayCount']}', _rupee.format(((p['dueTodayAmount'] as num).toDouble())), 'Due Today'),
    ];

    return _card(
      title: 'PTP Overview',
      onViewDetails: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniStatRow(tiles),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _footerStat('PTP Success Rate', '${p['successRatePercent']}%', color: _green)),
              Expanded(child: _footerStat('Breakage Rate', '${p['breakageRatePercent']}%', color: _red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatRow(List<_MiniStat> tiles) {
    return Row(
      children: tiles
          .map((t) => Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: t.color.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(t.icon, color: t.color, size: 16),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(t.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: t.color))),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(t.amount, style: const TextStyle(fontSize: 9, color: _muted, fontWeight: FontWeight.w600))),
                    const SizedBox(height: 2),
                    Text(t.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, color: _dark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _footerStat(String label, String value, {Color color = _dark}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: _muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Sales Team Performance
  // -------------------------------------------------------------------
  Widget _buildPerformanceSection(BuildContext context, List<Map<String, dynamic>> all, List<Map<String, dynamic>> visible) {
    return _card(
      title: 'Sales Team Performance (Today)',
      onViewDetails: all.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerTeamRecoveryScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (all.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No salesmen match this filter.', style: TextStyle(fontSize: 12, color: _muted)))
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _perfTableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        SizedBox(width: _perfColName, child: Text('Salesman', style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                        SizedBox(width: _perfColGap),
                        SizedBox(width: _perfColTarget, child: Text('Target (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                        SizedBox(width: _perfColGap),
                        SizedBox(width: _perfColCollected, child: Text('Collected (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                        SizedBox(width: _perfColGap),
                        SizedBox(width: _perfColAchv, child: Text('Achv %', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                        SizedBox(width: _perfColGap),
                        SizedBox(width: _perfColScore, child: Text('Score', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: _border)),
                    ...visible.map((s) => _performanceRow(s)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Showing 1 to ${visible.length} of ${all.length} Salesmen', style: const TextStyle(fontSize: 11, color: _muted)),
                if (visible.length < all.length)
                  GestureDetector(
                    onTap: () => setState(() => _visibleSalesmen = (_visibleSalesmen + 5).clamp(0, all.length)),
                    child: const Text('Load More  ⌄', style: TextStyle(fontSize: 11, color: _blue, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _performanceRow(Map<String, dynamic> s) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    final target = (s['collectionTarget'] as num).toDouble();
    final collected = (s['collectionAchieved'] as num).toDouble();
    final achieved = s['collectionAchievedPercent'] as int;
    final scoreLabel = achieved >= 75 ? 'Good' : (achieved >= 50 ? 'Average' : 'Poor');
    final scoreColor = achieved >= 75 ? _green : (achieved >= 50 ? _orange : _red);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: _perfColName, child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark))),
          const SizedBox(width: _perfColGap),
          SizedBox(width: _perfColTarget, child: Text(_rupee.format(target), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark))),
          const SizedBox(width: _perfColGap),
          SizedBox(width: _perfColCollected, child: Text(_rupee.format(collected), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _green))),
          const SizedBox(width: _perfColGap),
          SizedBox(width: _perfColAchv, child: Text('$achieved%', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark))),
          const SizedBox(width: _perfColGap),
          SizedBox(
            width: _perfColScore,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(scoreLabel, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: scoreColor)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Top 5 Overdue Customers
  // -------------------------------------------------------------------
  Widget _buildTopOverdueCustomers(BuildContext context, List<Customer> customers) {
    return _card(
      title: 'Top 5 Overdue Customers',
      onViewDetails: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerPriorityAccountsScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customers.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No overdue customers in this view.', style: TextStyle(fontSize: 12, color: _muted)))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _overdueTableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        SizedBox(width: _overdueColName, child: Text('Customer', style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                        SizedBox(width: _overdueColGap),
                        SizedBox(width: _overdueColAmount, child: Text('Overdue (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                        SizedBox(width: _overdueColGap),
                        SizedBox(width: _overdueColDays, child: Text('Days', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: _border)),
                    ...customers.map((c) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: _overdueColName, child: Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark))),
                              const SizedBox(width: _overdueColGap),
                              SizedBox(width: _overdueColAmount, child: Text(_rupee.format(c.totalDue), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _red))),
                              const SizedBox(width: _overdueColGap),
                              SizedBox(width: _overdueColDays, child: Text('${c.oldestOverdueDays}d', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark))),
                            ],
                          ),
                        )),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: _border)),
                    Row(
                      children: [
                        const SizedBox(width: _overdueColName, child: Text('Total', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark))),
                        const SizedBox(width: _overdueColGap),
                        SizedBox(width: _overdueColAmount, child: Text(_rupee.format(customers.fold(0.0, (s, c) => s + c.totalDue)), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark))),
                        const SizedBox(width: _overdueColGap),
                        const SizedBox(width: _overdueColDays),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Alerts & Reminders
  // -------------------------------------------------------------------
  Widget _buildAlerts(BuildContext context, AppStore store) {
    final rows = [
      _AlertRow(Icons.warning_amber_rounded, _red, 'Customers with 30+ days overdue', 'Need immediate attention', store.customers30PlusOverdueCount, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen()))),
      _AlertRow(Icons.hourglass_empty, _orange, 'PTP due today', 'Follow-up required', store.dueTodayPtpCount, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen()))),
      _AlertRow(Icons.phone_disabled_outlined, _blue, 'No follow-up accounts', 'No activity in last 3 days', store.noFollowUpAccounts.length, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerAlertsRemindersScreen()))),
      _AlertRow(Icons.description_outlined, _purple, 'Disputes awaiting review', 'Pending your action', store.disputesAwaitingReviewCount, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DisputesTab()))),
    ];

    return _card(
      title: 'Alerts & Reminders',
      onViewDetails: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerAlertsRemindersScreen())),
      child: Column(
        children: rows
            .map((r) => InkWell(
                  onTap: r.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: r.color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(r.icon, color: r.color, size: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _dark)),
                              Text(r.subtitle, style: const TextStyle(fontSize: 10.5, color: _muted)),
                            ],
                          ),
                        ),
                        Text('${r.count}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _dark)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 16, color: _muted),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Quick actions
  // -------------------------------------------------------------------
  Widget _buildQuickActions(BuildContext context, AppStore store) {
    final actions = [
      _QuickAction(Icons.event_available_outlined, _blue, 'View Recovery Today', "See today's tasks", () => widget.onNavigate(2)),
      _QuickAction(Icons.groups_outlined, _purple, 'Salesman Performance', 'Detailed performance', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerTeamRecoveryScreen()))),
      _QuickAction(Icons.emoji_events_outlined, _orange, 'Dispute Management', 'Review & assign', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DisputesTab()))),
      _QuickAction(Icons.bar_chart_outlined, _green, 'Reports', 'View all reports', () => widget.onNavigate(3)),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: actions
          .map((a) => InkWell(
                onTap: a.onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: a.color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(a.icon, color: a.color, size: 17)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark)),
                            Text(a.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: _muted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 15, color: _muted),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  // -------------------------------------------------------------------
  // Shared card shell
  // -------------------------------------------------------------------
  Widget _card({required String title, required Widget child, VoidCallback? onViewDetails}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: _dark))),
              if (onViewDetails != null)
                GestureDetector(
                  onTap: onViewDetails,
                  child: const Text('View Details', style: TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatCardData {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final VoidCallback? onTap;
  _StatCardData(this.icon, this.color, this.label, this.value, this.sub, {this.onTap});
}

class _MiniStat {
  final IconData icon;
  final Color color;
  final String value;
  final String amount;
  final String label;
  _MiniStat(this.icon, this.color, this.value, this.amount, this.label);
}

class _AlertRow {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;
  _AlertRow(this.icon, this.color, this.title, this.subtitle, this.count, this.onTap);
}

class _QuickAction {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  _QuickAction(this.icon, this.color, this.title, this.subtitle, this.onTap);
}
