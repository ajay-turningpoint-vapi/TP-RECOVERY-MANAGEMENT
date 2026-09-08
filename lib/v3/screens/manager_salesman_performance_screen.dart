import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _crore(double v) => '${(v / 10000000).toStringAsFixed(2)} Cr';

/// Process compliance is judged purely on the salesman's own conduct —
/// task completion and valid-next-action discipline — never on collection
/// %, so a hard portfolio never reads as a process failure.
String _processCompliance(Map<String, dynamic> s) {
  final avg = ((s['taskCompletionRate'] as int) + (s['validNextActionRate'] as int)) / 2;
  if (avg >= 85) return 'Good';
  if (avg >= 65) return 'Fair';
  return 'Poor';
}

Color _processComplianceColor(String v) => v == 'Good' ? kGreen : (v == 'Fair' ? kOrange : kRed);

/// Customer difficulty is judged purely on portfolio composition — broken
/// PTPs and escalated/high-risk accounts — never on the salesman's own
/// task/process discipline.
String _customerDifficulty(Map<String, dynamic> s) {
  final total = s['customers'] as int;
  if (total <= 0) return 'Low';
  final hardCount = (s['brokenPtps'] as int) + (s['escalatedCustomers'] as int) + (s['highRiskCustomers'] as int);
  final ratio = hardCount / total;
  if (ratio >= 0.4) return 'High';
  if (ratio >= 0.15) return 'Moderate';
  return 'Low';
}

Color _customerDifficultyColor(String v) => v == 'High' ? kRed : (v == 'Moderate' ? kOrange : kGreen);

/// Manager's Salesmen Performance report — individual achievement, top/
/// bottom performers and a searchable/sortable detail table, all derived
/// live from the real salesmen roster (never typed by hand).
class ManagerSalesmanPerformanceScreen extends StatefulWidget {
  final String initialBranch;
  final String initialSalesman;
  const ManagerSalesmanPerformanceScreen({super.key, this.initialBranch = 'All Branches', this.initialSalesman = 'All Salesmen'});

  @override
  State<ManagerSalesmanPerformanceScreen> createState() => _ManagerSalesmanPerformanceScreenState();
}

enum _SortBy { achievementDesc, achievementAsc, nameAsc, targetDesc }

class _ManagerSalesmanPerformanceScreenState extends State<ManagerSalesmanPerformanceScreen> {
  late String _branch;
  late String _salesman;

  @override
  void initState() {
    super.initState();
    _branch = widget.initialBranch;
    _salesman = widget.initialSalesman;
  }
  String _query = '';
  _SortBy _sort = _SortBy.achievementDesc;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = ['All Branches', ...{for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}];
    final allSalesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];

    var salesmen = store.salesmen.where((s) => (_branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == _branch) && (_salesman == 'All Salesmen' || s['name'] == _salesman)).toList();

    final totalTarget = salesmen.fold(0.0, (s, m) => s + (m['collectionTarget'] as num).toDouble());
    final totalReceived = salesmen.fold(0.0, (s, m) => s + (m['collectionAchieved'] as num).toDouble());
    final variance = totalTarget - totalReceived;
    final achievementPercent = totalTarget <= 0 ? 0.0 : (totalReceived / totalTarget * 100).clamp(0, 999).toDouble();
    // "Active Salesmen" (calls made today) had no real data source — no
    // call-log table exists anywhere in the server — so it was removed
    // rather than faked. This card now shows a real, equally meaningful
    // figure: salesmen genuinely below their real collection target.
    final belowTargetSalesmen = salesmen.where((s) => (s['collectionAchievedPercent'] as int) < 60).length;

    // Achievement distribution buckets.
    final bucket100 = salesmen.where((s) => (s['collectionAchievedPercent'] as int) >= 100).length;
    final bucket75 = salesmen.where((s) => (s['collectionAchievedPercent'] as int) >= 75 && (s['collectionAchievedPercent'] as int) < 100).length;
    final bucket50 = salesmen.where((s) => (s['collectionAchievedPercent'] as int) >= 50 && (s['collectionAchievedPercent'] as int) < 75).length;
    final bucketLow = salesmen.where((s) => (s['collectionAchievedPercent'] as int) < 50).length;

    final ranked = List<Map<String, dynamic>>.from(salesmen)..sort((a, b) => (b['collectionAchievedPercent'] as int).compareTo(a['collectionAchievedPercent'] as int));
    final topPerformers = ranked.take(3).toList();
    final bottomPerformers = ranked.reversed.take(3).toList();

    final trend = store.collectionsTrendLast7Days;
    final maxTrend = trend.fold<double>(0, (m, t) => [m, (t['expected'] as num).toDouble(), (t['actual'] as num).toDouble()].reduce((a, b) => a > b ? a : b));
    final chartMax = maxTrend <= 0 ? 100000.0 : maxTrend * 1.15;

    var tableRows = salesmen.where((s) {
      if (_query.trim().isEmpty) return true;
      return (s['name'] as String).toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();
    switch (_sort) {
      case _SortBy.achievementDesc:
        tableRows.sort((a, b) => (b['collectionAchievedPercent'] as int).compareTo(a['collectionAchievedPercent'] as int));
        break;
      case _SortBy.achievementAsc:
        tableRows.sort((a, b) => (a['collectionAchievedPercent'] as int).compareTo(b['collectionAchievedPercent'] as int));
        break;
      case _SortBy.nameAsc:
        tableRows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        break;
      case _SortBy.targetDesc:
        tableRows.sort((a, b) => (b['collectionTarget'] as num).toDouble().compareTo((a['collectionTarget'] as num).toDouble()));
        break;
    }

    final highestRow = ranked.isEmpty ? null : ranked.first;
    final lowestRow = ranked.isEmpty ? null : ranked.last;
    final avgAchievement = salesmen.isEmpty ? 0.0 : salesmen.fold(0.0, (s, m) => s + (m['collectionAchievedPercent'] as int)) / salesmen.length;

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
                      _filterRow(branches, allSalesmenNames),
                      const SizedBox(height: 14),
                      _statCards(totalTarget, totalReceived, achievementPercent, variance, belowTargetSalesmen, salesmen.length),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _achievementDistribution(salesmen.length, bucket100, bucket75, bucket50, bucketLow)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              children: [
                                _performersCard(context, 'Top Performers', topPerformers, kGreen),
                                const SizedBox(height: 12),
                                _performersCard(context, 'Bottom Performers', bottomPerformers, kRed),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _achievementTrend(trend, chartMax),
                      const SizedBox(height: 20),
                      _processVsDifficultyCard(context, salesmen),
                      const SizedBox(height: 20),
                      _detailsTable(tableRows),
                      const SizedBox(height: 20),
                      _summaryRow(salesmen.length, avgAchievement, highestRow, lowestRow),
                      const SizedBox(height: 16),
                      _footer(store),
                    ],
                  ),
                ),
              ],
            );
            if (constraints.maxWidth <= 900) return content;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: content,
              ),
            );
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
                Text('Salesmen Performance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Individual performance and achievement report', style: TextStyle(fontSize: 10.5, color: kMuted)),
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
  // Filter row
  // -------------------------------------------------------------------
  Widget _filterRow(List<String> branches, List<String> salesmenNames) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
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
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dropdownPill(Icons.apartment_outlined, kBlue, _branch, branches, (v) => setState(() => _branch = v))),
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
  Widget _statCards(double target, double received, double achievement, double variance, int active, int total) {
    final cards = [
      (Icons.gps_fixed, kPurple, _rupee.format(target), 'Total Target (₹)', '100%'),
      (Icons.swap_vert, kGreen, _rupee.format(received), 'Total Received (₹)', '${achievement.toStringAsFixed(2)}%'),
      (Icons.show_chart, kOrange, '${achievement.toStringAsFixed(2)}%', 'Achievement', 'vs Target'),
      (Icons.trending_down, kRed, _rupee.format(variance), 'Variance (₹)', total <= 0 ? '0%' : '${(variance / (target <= 0 ? 1 : target) * 100).clamp(0, 999).toStringAsFixed(2)}%'),
      (Icons.groups_outlined, kBlue, '$active', 'Below Target', 'of $total'),
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
          decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.15))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 18),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(fontSize: 9, color: kMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // -------------------------------------------------------------------
  // Achievement Distribution
  // -------------------------------------------------------------------
  Widget _achievementDistribution(int total, int b100, int b75, int b50, int bLow) {
    final buckets = [
      ('>= 100%', b100, kGreen),
      ('75% - 99%', b75, kBlue),
      ('50% - 74%', b50, kOrange),
      ('< 50%', bLow, kRed),
    ];
    return InfoCard(
      children: [
        const Text('Achievement Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 34,
                  sectionsSpace: 2,
                  sections: buckets.where((b) => b.$2 > 0).map((b) => PieChartSectionData(value: b.$2.toDouble(), color: b.$3, radius: 24, showTitle: false)).toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kNavy)),
                  const Text('Salesmen', style: TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...buckets.map((b) {
          final pct = total <= 0 ? 0.0 : (b.$2 / total * 100);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: b.$3, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(b.$1, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                Text('${b.$2} (${pct.toStringAsFixed(2)}%)', style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Top / Bottom performers
  // -------------------------------------------------------------------
  Widget _performersCard(BuildContext context, String title, List<Map<String, dynamic>> rows, Color valueColor) {
    return InfoCard(
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavy))),
            if (rows.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _sort = title == 'Top Performers' ? _SortBy.achievementDesc : _SortBy.achievementAsc),
                child: const Text('View All', style: TextStyle(color: kBlue, fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('No salesmen in this view.', style: TextStyle(fontSize: 11, color: kMuted)))
        else
          ...rows.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final s = entry.value;
            final name = (s['fullName'] as String?) ?? s['name'] as String;
            final branch = ((s['branch'] as String?) ?? 'Turning Point');
            final received = (s['collectionAchieved'] as num).toDouble();
            final percent = s['collectionAchievedPercent'] as int;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(radius: 11, backgroundColor: valueColor.withOpacity(0.15), child: Text('$rank', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: valueColor))),
                  const SizedBox(width: 8),
                  CircleAvatar(radius: 14, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 9.5, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark)),
                        Text(branch, style: const TextStyle(fontSize: 9.5, color: kMuted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(received), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark))),
                      Text('$percent%', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: valueColor)),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Achievement Trend
  // -------------------------------------------------------------------
  Widget _achievementTrend(List<Map<String, dynamic>> trend, double chartMax) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('Achievement Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy))),
            _legendDash(kPurple, 'Target'),
            const SizedBox(width: 12),
            _legendDot(kGreen, 'Received'),
          ],
        ),
        const SizedBox(height: 14),
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
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(_crore(v), style: const TextStyle(fontSize: 8, color: kMuted)))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= trend.length) return const SizedBox();
                      return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'] as String, style: const TextStyle(fontSize: 8.5, color: kMuted)));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['expected'] as num).toDouble())], isCurved: true, color: kPurple, barWidth: 2, dashArray: [6, 4], dotData: const FlDotData(show: true)),
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['actual'] as num).toDouble())], isCurved: true, color: kGreen, barWidth: 2.5, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: kGreen.withOpacity(0.08))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDash(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 14, height: 2, child: CustomPaint(painter: _DashPainter(color))),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
    ]);
  }

  // -------------------------------------------------------------------
  // Process Discipline vs Customer Difficulty
  // -------------------------------------------------------------------
  Widget _processVsDifficultyCard(BuildContext context, List<Map<String, dynamic>> salesmen) {
    return InfoCard(
      children: [
        const Text('Process Discipline vs Customer Difficulty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
        const SizedBox(height: 2),
        const Text('Two independent readings — a hard portfolio is never read as a process failure, and vice versa.', style: TextStyle(fontSize: 10, color: kMuted)),
        const SizedBox(height: 12),
        if (salesmen.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No salesmen in this view.', style: TextStyle(fontSize: 11, color: kMuted)))
        else
          ...salesmen.map((s) {
            final name = (s['fullName'] as String?) ?? s['name'] as String;
            final compliance = _processCompliance(s);
            final difficulty = _customerDifficulty(s);
            return InkWell(
              onTap: () => _showProcessDifficultyDetail(context, s, compliance, difficulty),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    CircleAvatar(radius: 13, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 9.5, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark))),
                    _badge('Process: $compliance', _processComplianceColor(compliance)),
                    const SizedBox(width: 6),
                    _badge('Customer: $difficulty', _customerDifficultyColor(difficulty)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 15, color: kMuted),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  void _showProcessDifficultyDetail(BuildContext context, Map<String, dynamic> s, String compliance, String difficulty) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 18, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 12, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _processComplianceColor(compliance).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _processComplianceColor(compliance).withOpacity(0.2))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Process Compliance', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                          Text(compliance, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _processComplianceColor(compliance))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _customerDifficultyColor(difficulty).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _customerDifficultyColor(difficulty).withOpacity(0.2))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Customer Difficulty', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                          Text(difficulty, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _customerDifficultyColor(difficulty))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Process Discipline', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 6),
              _kv('Task Completion Rate', '${s['taskCompletionRate']}%'),
              _kv('Valid Next Action Rate', '${s['validNextActionRate']}%'),
              const SizedBox(height: 10),
              const Text('Customer Difficulty', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 6),
              _kv('Broken PTPs', '${s['brokenPtps']}'),
              _kv('Escalated Accounts (L1-L4)', '${s['escalatedCustomers']} of ${s['customers']}'),
              _kv('High Risk Accounts', '${s['highRiskCustomers']} of ${s['customers']}'),
              const SizedBox(height: 12),
              Text(
                compliance == 'Good' && difficulty == 'High'
                    ? 'Good process on a hard portfolio — do not read low collection numbers as a process failure here.'
                    : (compliance == 'Poor' && difficulty == 'Low'
                        ? 'Easy portfolio with weak process discipline — this is a coaching/accountability case, not a customer-risk case.'
                        : 'Process compliance and customer difficulty are independent readings — review both before drawing a conclusion.'),
                style: const TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600))),
          Text(value, style: const TextStyle(fontSize: 12.5, color: kDark, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Details table
  // -------------------------------------------------------------------
  Widget _detailsTable(List<Map<String, dynamic>> rows) {
    return InfoCard(
      children: [
        const Text('Salesmen Performance Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 14, color: kMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(fontSize: 11.5, color: kDark),
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Search by name', hintStyle: TextStyle(fontSize: 11, color: kMuted)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _sort = _sort == _SortBy.achievementDesc ? _SortBy.achievementAsc : _SortBy.achievementDesc;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sort == _SortBy.achievementAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: kNavy),
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No salesmen match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.map((s) => _detailRow(context, s)),
      ],
    );
  }

  Widget _detailRow(BuildContext context, Map<String, dynamic> s) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    final branch = ((s['branch'] as String?) ?? 'Turning Point');
    final target = (s['collectionTarget'] as num).toDouble();
    final received = (s['collectionAchieved'] as num).toDouble();
    final percent = s['collectionAchievedPercent'] as int;
    final variance = received - target;
    final dueTodayPtps = (s['dueTodayPtps'] as num).toDouble();
    final barColor = percent >= 100 ? kGreen : (percent >= 75 ? kBlue : (percent >= 50 ? kOrange : kRed));

    return InkWell(
      onTap: () => _showProcessDifficultyDetail(context, s, _processCompliance(s), _customerDifficulty(s)),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(radius: 15, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 10.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                Text(branch, style: const TextStyle(fontSize: 9.5, color: kMuted)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(received), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen))),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(width: 70, child: LinearProgressIndicator(value: (percent / 100).clamp(0, 1).toDouble(), minHeight: 4, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(barColor))),
                ),
                Text('$percent%', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: barColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(variance >= 0 ? '+${_rupee.format(variance)}' : '-${_rupee.format(variance.abs())}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: variance >= 0 ? kGreen : kRed)),
                Text('PTP: ${_rupee.format(dueTodayPtps)}', style: const TextStyle(fontSize: 8.5, color: kMuted)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: kMuted),
        ],
      ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Summary + footer
  // -------------------------------------------------------------------
  Widget _summaryRow(int total, double avgAchievement, Map<String, dynamic>? highest, Map<String, dynamic>? lowest) {
    return InfoCard(
      children: [
        Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kPurple.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.calendar_month_outlined, size: 15, color: kPurple)),
            const SizedBox(width: 8),
            const Text('Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavy)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _summaryItem('Total Salesmen', '$total')),
            Expanded(child: _summaryItem('Avg Achievement', '${avgAchievement.toStringAsFixed(2)}%')),
            Expanded(child: _summaryItem('Highest Achievement', highest == null ? '-' : '${highest['collectionAchievedPercent']}% (${highest['fullName'] ?? highest['name']})', color: kGreen)),
            Expanded(child: _summaryItem('Lowest Achievement', lowest == null ? '-' : '${lowest['collectionAchievedPercent']}% (${lowest['fullName'] ?? lowest['name']})', color: kRed)),
          ],
        ),
      ],
    );
  }

  Widget _summaryItem(String label, String value, {Color color = kDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _footer(AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(child: Text('All amounts are in INR. Data is as per payments received on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.', style: const TextStyle(fontSize: 10, color: kDark))),
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
