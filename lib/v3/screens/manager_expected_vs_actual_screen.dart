import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/v3/screens/company_recovery_queue_screen.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _crore(double v) => '${(v / 10000000).toStringAsFixed(2)} Cr';

// Branch table columns — fixed widths (not Expanded/flex) so a branch name
// gets real room instead of being squeezed by the currency columns; the
// table scrolls horizontally when it doesn't fit instead of shrinking
// everything down to illegible text.
const double _evaColBranch = 110;
const double _evaColExpected = 100;
const double _evaColActual = 100;
const double _evaColAchv = 70;
const double _evaColGap = 10;
const double _evaTableWidth = _evaColBranch + _evaColExpected + _evaColActual + _evaColAchv + _evaColGap * 3;

/// Manager's Expected vs Actual Collection report — company/branch/customer
/// level comparison of what was promised (PTP-derived expected) against
/// what was actually collected, all derived live from the real store.
class ManagerExpectedVsActualScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerExpectedVsActualScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerExpectedVsActualScreen> createState() => _ManagerExpectedVsActualScreenState();
}

enum _CustSortBy { varianceDesc, achievementAsc, nameAsc }

class _ManagerExpectedVsActualScreenState extends State<ManagerExpectedVsActualScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _CustSortBy _sort = _CustSortBy.varianceDesc;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];

    final salesmen = store.salesmen.where((s) => (_branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == _branch) && (_salesman == 'All Salesmen' || s['name'] == _salesman)).toList();
    final totalExpected = salesmen.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));
    final totalActual = salesmen.fold(0.0, (s, m) => s + ((m['collectionAchieved'] as num).toDouble()));
    final variance = totalExpected - totalActual;
    final achievementPercent = totalExpected <= 0 ? 0.0 : (totalActual / totalExpected * 100).clamp(0, 999).toDouble();

    final salesmenNamesInScope = salesmen.map((s) => s['name'] as String).toSet();
    final customersInScope = store.customers.where((c) => salesmenNamesInScope.contains(c.assignedSalesmanId)).toList();
    final customerIds = customersInScope.map((c) => c.id).toSet();
    final matured = store.ptps.where((p) => customerIds.contains(p.customerId) && (p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept)).toList();
    final paymentsCount = matured.length;
    final payingCustomerCount = matured.map((p) => p.customerId).toSet().length;

    final trend = store.collectionsTrendLast7Days;
    final avgExpected = trend.isEmpty ? 0.0 : trend.fold(0.0, (s, t) => s + ((t['expected'] as num).toDouble())) / trend.length;
    final avgActual = trend.isEmpty ? 0.0 : trend.fold(0.0, (s, t) => s + ((t['actual'] as num).toDouble())) / trend.length;
    final avgVariance = avgExpected - avgActual;
    final maxTrend = trend.fold<double>(0, (m, t) => [m, (t['expected'] as num).toDouble(), (t['actual'] as num).toDouble()].reduce((a, b) => a > b ? a : b));
    final chartMax = maxTrend <= 0 ? 100000.0 : maxTrend * 1.25;

    // Branch-wise breakdown.
    final branchNames = {for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}.toList()..sort();
    final branchRows = branchNames.map((b) {
      final inBranch = store.salesmen.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == b);
      final expected = inBranch.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));
      final actual = inBranch.fold(0.0, (s, m) => s + ((m['collectionAchieved'] as num).toDouble()));
      return (branch: b, expected: expected, actual: actual, variance: expected - actual, achievement: expected <= 0 ? 0.0 : (actual / expected * 100).clamp(0, 999).toDouble());
    }).where((r) => _branch == 'All Branches' || r.branch == _branch).toList();
    final rankedByAchievement = List.of(branchRows)..sort((a, b) => b.achievement.compareTo(a.achievement));
    final overPerformers = rankedByAchievement.take(3).toList();
    final underPerformers = rankedByAchievement.reversed.take(3).toList();

    // Customer-level Expected vs Actual, derived from real PTPs.
    final custRows = customersInScope.map((c) {
      final custPtps = store.ptps.where((p) => p.customerId == c.id).toList();
      final expected = custPtps.fold(0.0, (s, p) => s + p.amountPromised);
      final actual = custPtps.where((p) => p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept).fold(0.0, (s, p) => s + (p.amountReceived ?? 0));
      return (customer: c, expected: expected, actual: actual, variance: expected - actual, achievement: expected <= 0 ? 0.0 : (actual / expected * 100).clamp(0, 999).toDouble());
    }).where((r) => r.expected > 0).toList();
    var filteredCustRows = custRows.where((r) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return r.customer.name.toLowerCase().contains(q) || r.customer.assignedSalesmanId.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _CustSortBy.varianceDesc:
        filteredCustRows.sort((a, b) => b.variance.compareTo(a.variance));
        break;
      case _CustSortBy.achievementAsc:
        filteredCustRows.sort((a, b) => a.achievement.compareTo(b.achievement));
        break;
      case _CustSortBy.nameAsc:
        filteredCustRows.sort((a, b) => a.customer.name.compareTo(b.customer.name));
        break;
    }

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              children: [
                _header(context, store),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _filterRow(branches, salesmenNames),
                      const SizedBox(height: 14),
                      _statCards(totalExpected, totalActual, variance, achievementPercent, paymentsCount, payingCustomerCount),
                      const SizedBox(height: 20),
                      _trendCard(trend, chartMax, avgExpected, avgActual, avgVariance, achievementPercent),
                      const SizedBox(height: 20),
                      _branchTable(context, branchRows, totalExpected, totalActual, variance, achievementPercent),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _performersCard(context, 'Top Over Performers', overPerformers, kGreen)),
                          const SizedBox(width: 12),
                          Expanded(child: _performersCard(context, 'Top Under Performers', underPerformers, kRed)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _customerTable(store, filteredCustRows),
                      const SizedBox(height: 20),
                      _footer(store),
                    ],
                  ),
                ),
              ],
            );
            if (constraints.maxWidth <= 700) return content;
            return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: content));
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------
  Widget _header(BuildContext context, AppStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: kNavy), tooltip: 'Back', onPressed: () => Navigator.pop(context)),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expected vs Actual Collection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
                Text('Compare expected collections against actual receipts', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _snack(context, 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.')),
          const SizedBox(width: 8),
          _headerIcon(Icons.filter_alt_outlined, () => _snack(context, 'Use the Branch and Salesman filters below to scope this report.')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              store.incrementReportsGenerated();
              _snack(context, 'Report export started — you will be notified when it is ready.');
            },
            icon: const Icon(Icons.ios_share, size: 15),
            label: const Text('Export', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
        child: Icon(icon, size: 17, color: kNavy),
      ),
    );
  }

  void _snack(BuildContext context, String message) => showAppMessage(context, message: message);

  // -------------------------------------------------------------------
  // Filters
  // -------------------------------------------------------------------
  Widget _filterRow(List<String> branches, List<String> salesmenNames) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 14, color: kPurple),
              const SizedBox(width: 6),
              Flexible(child: Text('As on ${DateFormat('dd MMM yyyy').format(DateTime.now())}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dropdownPill(Icons.apartment_outlined, kBlue, _branch, branches, (v) { context.read<AppStore>().setBranchFilter(v); setState(() {}); })),
            const SizedBox(width: 10),
            Expanded(child: _dropdownPill(Icons.person_outline, kGreen, _salesman, salesmenNames, (v) => setState(() => _salesman = v))),
          ],
        ),
      ],
    );
  }

  Widget _dropdownPill(IconData icon, Color color, String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 15, color: kMuted),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark),
                items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) { if (v != null) onChanged(v); },
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
  Widget _statCards(double expected, double actual, double variance, double achievement, int payments, int customers) {
    final cards = [
      (Icons.calendar_month_outlined, kBlue, _rupee.format(expected), 'Total Expected (₹)', '100%'),
      (Icons.account_balance_wallet_outlined, kGreen, _rupee.format(actual), 'Total Actual (₹)', '${achievement.toStringAsFixed(2)}%'),
      (Icons.swap_vert, kRed, _rupee.format(variance), 'Variance (₹)', expected <= 0 ? '0%' : '${(variance / expected * 100).clamp(0, 999).toStringAsFixed(2)}%'),
      (Icons.gps_fixed, kOrange, '${achievement.toStringAsFixed(2)}%', 'Achievement (%)', 'vs Target'),
      (Icons.groups_outlined, kPurple, '$payments', 'No. of Payments', 'Customers: $customers'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: cards.map((c) {
        final (icon, color, value, label, sub) = c;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.15))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 18),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: color))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(fontSize: 9, color: kMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // -------------------------------------------------------------------
  // Trend: Expected/Actual lines + Variance bars, overlaid
  // -------------------------------------------------------------------
  Widget _trendCard(List<Map<String, dynamic>> trend, double chartMax, double avgExpected, double avgActual, double avgVariance, double achievement) {
    return InfoCard(
      children: [
        const Row(
          children: [
            Expanded(child: Text('Expected vs Actual Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavy))),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          children: [
            _legendDash(kBlue, 'Expected (₹)'),
            _legendDot(kGreen, 'Actual (₹)'),
            _legendBar(kRed, 'Variance (₹)'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: Stack(
            children: [
              BarChart(
                BarChartData(
                  minY: 0,
                  maxY: chartMax,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  alignment: BarChartAlignment.spaceEvenly,
                  titlesData: const FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false, reservedSize: 32)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false, reservedSize: 24)),
                  ),
                  barGroups: [
                    for (var i = 0; i < trend.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(toY: (((trend[i]['expected'] as num).toDouble()) - ((trend[i]['actual'] as num).toDouble())).clamp(0, chartMax), color: kRed.withValues(alpha: 0.75), width: 14, borderRadius: BorderRadius.circular(3)),
                      ]),
                  ],
                ),
              ),
              LineChart(
                LineChartData(
                  minY: 0,
                  maxY: chartMax,
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) => Text(_crore(v), style: const TextStyle(fontSize: 8, color: kMuted)))),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, m) {
                          final i = v.toInt();
                          if (i < 0 || i >= trend.length) return const SizedBox();
                          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'] as String, style: const TextStyle(fontSize: 8.5, color: kMuted)));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['expected'] as num).toDouble())], isCurved: true, color: kBlue, barWidth: 2, dashArray: [6, 4], dotData: const FlDotData(show: true)),
                    LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['actual'] as num).toDouble())], isCurved: true, color: kGreen, barWidth: 2.5, dotData: const FlDotData(show: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: kBorder)),
        Row(
          children: [
            Expanded(child: _trendMetric('Average Daily Expected', _crore(avgExpected), kBlue)),
            Expanded(child: _trendMetric('Average Daily Actual', _crore(avgActual), kGreen)),
            Expanded(child: _trendMetric('Average Daily Variance', _crore(avgVariance), kRed)),
            Expanded(child: _trendMetric('Achievement', '${achievement.toStringAsFixed(2)}%', kOrange)),
          ],
        ),
      ],
    );
  }

  Widget _trendMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8.5, color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color))),
      ],
    );
  }

  Widget _legendDash(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 14, height: 2, child: CustomPaint(painter: _DashPainter(color))),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _legendBar(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
    ]);
  }

  // -------------------------------------------------------------------
  // Branch table
  // -------------------------------------------------------------------
  Widget _branchTable(BuildContext context, List<({String branch, double expected, double actual, double variance, double achievement})> rows, double totalExpected, double totalActual, double totalVariance, double totalAchievement) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('Expected vs Actual by Branch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy))),
            if (rows.isNotEmpty)
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen())),
                child: const Text('View All', style: TextStyle(color: kBlue, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _evaTableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(width: _evaColBranch, child: Text('Branch', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _evaColGap),
                    SizedBox(width: _evaColExpected, child: Text('Expected (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _evaColGap),
                    SizedBox(width: _evaColActual, child: Text('Actual (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _evaColGap),
                    SizedBox(width: _evaColAchv, child: Text('Achv %', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                ...rows.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          SizedBox(width: _evaColBranch, child: Text(r.branch, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark))),
                          const SizedBox(width: _evaColGap),
                          SizedBox(width: _evaColExpected, child: Text(_rupee.format(r.expected), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kBlue))),
                          const SizedBox(width: _evaColGap),
                          SizedBox(width: _evaColActual, child: Text(_rupee.format(r.actual), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen))),
                          const SizedBox(width: _evaColGap),
                          SizedBox(
                            width: _evaColAchv,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${r.achievement.toStringAsFixed(2)}%', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark)),
                                ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 60, child: LinearProgressIndicator(value: (r.achievement / 100).clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(r.achievement >= 60 ? kGreen : (r.achievement >= 35 ? kOrange : kRed))))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                Row(
                  children: [
                    const SizedBox(width: _evaColBranch, child: Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kNavy))),
                    const SizedBox(width: _evaColGap),
                    SizedBox(width: _evaColExpected, child: Text(_rupee.format(totalExpected), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kBlue))),
                    const SizedBox(width: _evaColGap),
                    SizedBox(width: _evaColActual, child: Text(_rupee.format(totalActual), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kGreen))),
                    const SizedBox(width: _evaColGap),
                    SizedBox(width: _evaColAchv, child: Text('${totalAchievement.toStringAsFixed(1)}%', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kOrange))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Over / Under performers
  // -------------------------------------------------------------------
  Widget _performersCard(BuildContext context, String title, List<({String branch, double expected, double actual, double variance, double achievement})> rows, Color color) {
    return InfoCard(
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kNavy))),
            if (rows.isNotEmpty)
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen())),
                child: const Text('View All', style: TextStyle(color: kBlue, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Text('No branches in this view.', style: TextStyle(fontSize: 10.5, color: kMuted))
        else
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.branch, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
                        Text('${r.achievement.toStringAsFixed(2)}%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (r.achievement / 100).clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(color))),
                        ),
                        const SizedBox(width: 6),
                        Text(_rupee.format(r.variance), style: const TextStyle(fontSize: 9, color: kMuted)),
                      ],
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Customer table
  // -------------------------------------------------------------------
  Widget _customerTable(AppStore store, List<({Customer customer, double expected, double actual, double variance, double achievement})> rows) {
    return InfoCard(
      children: [
        const Text('Customer Expected vs Actual (Due in Selected Period)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavy)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 11.5, color: kDark),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: kBg,
                    prefixIcon: const Icon(Icons.search, size: 16, color: kMuted),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    hintText: 'Search customer',
                    hintStyle: const TextStyle(fontSize: 11, color: kMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _sort = _sort == _CustSortBy.varianceDesc ? _CustSortBy.achievementAsc : (_sort == _CustSortBy.achievementAsc ? _CustSortBy.nameAsc : _CustSortBy.varianceDesc);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sort == _CustSortBy.nameAsc ? Icons.sort_by_alpha : (_sort == _CustSortBy.achievementAsc ? Icons.arrow_upward : Icons.arrow_downward), size: 13, color: kNavy),
                    const SizedBox(width: 4),
                    const Text('Sort', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kNavy)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No customers match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.take(30).map((r) => _customerRow(store, r)),
      ],
    );
  }

  Widget _customerRow(AppStore store, ({Customer customer, double expected, double actual, double variance, double achievement}) r) {
    final good = r.achievement >= 90;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.customer.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                Text('${r.customer.branch}  ·  ${store.salesmanDisplayName(r.customer.assignedSalesmanId)}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(r.actual), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen))),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 60, child: LinearProgressIndicator(value: (r.achievement / 100).clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(good ? kGreen : kOrange)))),
                Text('${r.achievement.toStringAsFixed(2)}%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: good ? kGreen : kOrange)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(r.variance <= 0 ? '(${_rupee.format(r.variance.abs())})' : _rupee.format(r.variance), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: r.variance <= 0 ? kGreen : kRed)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(good ? Icons.check_circle : Icons.warning_amber_rounded, size: 16, color: good ? kGreen : kOrange),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Footer
  // -------------------------------------------------------------------
  Widget _footer(AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withValues(alpha: 0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          const Expanded(child: Text('Expected amount is calculated based on due dates and PTPs.', style: TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(onTap: () => setState(() => store.refreshBusySync()), child: const Icon(Icons.refresh, size: 15, color: kBlue)),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + dashWidth, size.height / 2), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
