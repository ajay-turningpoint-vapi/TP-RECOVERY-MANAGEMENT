import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _brokenBucket(Customer c) {
  if (c.escalationLevel == 'L4') return 'Management Attention';
  if (c.currentRecoveryState == 'RE Control') return 'Under RE Control';
  if (c.escalationLevel == 'L3') return 'Third+ Broken';
  if (c.escalationLevel == 'L2') return 'Second Broken';
  return 'First Broken';
}

const _bucketColors = {'First Broken': kBlue, 'Second Broken': kOrange, 'Third+ Broken': kGreen, 'Under RE Control': kPurple, 'Management Attention': kRed};

/// Manager's Broken PTP Report — same real analysis as the RE's Broken PTP
/// Report (escalation-bucketed broken promises), restyled to the Manager
/// report visual language, view-only (no resolution actions).
class ManagerBrokenPtpReportScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerBrokenPtpReportScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerBrokenPtpReportScreen> createState() => _ManagerBrokenPtpReportScreenState();
}

enum _SortBy { dateDesc, amountDesc }

class _ManagerBrokenPtpReportScreenState extends State<ManagerBrokenPtpReportScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _SortBy _sort = _SortBy.dateDesc;

  Customer _customerFor(AppStore store, String customerId) => store.customers.firstWhere((c) => c.id == customerId, orElse: () => store.customers.first);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    // Exclude salesmen with zero total overdue — nothing to chase, so they
    // just clutter this filter (same convention as control_dashboard_screen
    // / report_detail_screens' salesman leaderboard).
    final salesmenNames = [
      'All Salesmen',
      ...store.salesmen
          .where((s) => ((s['totalOverdue'] as num?) ?? 0) > 0)
          .map((s) => s['name'] as String),
    ];
    final now = DateTime.now();

    bool inScope(PromiseToPay p) {
      final c = _customerFor(store, p.customerId);
      return (_branch == 'All Branches' || c.branch == _branch) && (_salesman == 'All Salesmen' || c.assignedSalesmanId == _salesman);
    }

    final items = store.brokenPtps.where(inScope).toList()..sort((a, b) => b.promiseDate.compareTo(a.promiseDate));
    final totalAmount = items.fold(0.0, (s, p) => s + p.amountPromised);
    final brokenToday = items.where((p) => _isSameDay(p.promiseDate, now)).fold(0.0, (s, p) => s + p.amountPromised);

    final byCustomer = <String, List<PromiseToPay>>{};
    for (final p in items) {
      byCustomer.putIfAbsent(p.customerId, () => []).add(p);
    }
    final repeatBrokenAccounts = byCustomer.values.where((l) => l.length >= 2).length;
    final brokenCustomers = byCustomer.keys.map((id) => _customerFor(store, id)).toList();
    final reControlCount = brokenCustomers.where((c) => c.currentRecoveryState == 'RE Control' && c.escalationLevel != 'L4').length;
    final managementAttentionCount = brokenCustomers.where((c) => c.escalationLevel == 'L4').length;

    final buckets = <String, List<Customer>>{'First Broken': [], 'Second Broken': [], 'Third+ Broken': [], 'Under RE Control': [], 'Management Attention': []};
    for (final c in brokenCustomers) {
      buckets[_brokenBucket(c)]!.add(c);
    }

    final trend = store.brokenPtpCountTrend;
    final maxTrend = trend.fold<int>(0, (m, t) => (t['count'] as int) > m ? (t['count'] as int) : m);
    final chartMax = maxTrend <= 0 ? 5.0 : maxTrend * 1.3;

    var rows = items.where((p) {
      if (_query.trim().isEmpty) return true;
      final c = _customerFor(store, p.customerId);
      final q = _query.trim().toLowerCase();
      return c.name.toLowerCase().contains(q) || c.assignedSalesmanId.toLowerCase().contains(q);
    }).toList();
    if (_sort == _SortBy.amountDesc) rows.sort((a, b) => b.amountPromised.compareTo(a.amountPromised));

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, store),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _filterRow(branches, salesmenNames),
                  const SizedBox(height: 14),
                  _statCards(items.length, totalAmount, brokenToday, repeatBrokenAccounts, reControlCount, managementAttentionCount),
                  const SizedBox(height: 20),
                  _trendCard(trend, chartMax),
                  const SizedBox(height: 20),
                  _distributionCard(context, buckets, brokenCustomers.length),
                  const SizedBox(height: 20),
                  _detailsTable(store, rows),
                  const SizedBox(height: 16),
                  _footer(store),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                Text('Broken PTP Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Analysis of broken promises and follow-up status', style: TextStyle(fontSize: 10, color: kMuted)),
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
      child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)), child: Icon(icon, size: 17, color: kNavy)),
    );
  }

  void _snack(BuildContext context, String message) => showAppMessage(context, message: message);

  Widget _filterRow(List<String> branches, List<String> salesmenNames) {
    return Row(
      children: [
        Expanded(child: _dropdownPill(Icons.apartment_outlined, kBlue, _branch, branches, (v) { context.read<AppStore>().setBranchFilter(v); setState(() {}); })),
        const SizedBox(width: 10),
        Expanded(child: _dropdownPill(Icons.person_outline, kGreen, _salesman, salesmenNames, (v) => setState(() => _salesman = v))),
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

  Widget _statCards(int count, double amount, double brokenToday, int repeat, int reControl, int mgmt) {
    final cards = [
      (Icons.link_off, kRed, '$count', 'Total Broken PTPs', _rupee.format(amount)),
      (Icons.event_outlined, kOrange, _rupee.format(brokenToday), 'Broken Today', ''),
      (Icons.replay, kRed, '$repeat', 'Repeat Broken Accounts', '2+ broken'),
      (Icons.shield_outlined, kPurple, '$reControl', 'RE Control', ''),
      (Icons.warning_amber_rounded, kRed, '$mgmt', 'Management Attention', 'L4 escalation'),
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
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 9, color: kMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _trendCard(List<Map<String, dynamic>> trend, double chartMax) {
    return InfoCard(
      children: [
        const Text('Broken PTP Trend (Last 6 Months)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: chartMax,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, getTitlesWidget: (v, m) => Text('${v.toInt()}', style: const TextStyle(fontSize: 8, color: kMuted)))),
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
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['count'] as num).toDouble())], isCurved: true, color: kRed, barWidth: 2.5, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: kRed.withValues(alpha: 0.08))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _distributionCard(BuildContext context, Map<String, List<Customer>> buckets, int total) {
    return InfoCard(
      children: [
        const Text('Broken PTP Status Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: PieChart(PieChartData(centerSpaceRadius: 28, sectionsSpace: 2, sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.length.toDouble(), color: _bucketColors[e.key], radius: 22, showTitle: false)).toList())),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buckets.entries.map((e) {
                  final pct = total <= 0 ? 0.0 : e.value.length / total * 100;
                  return InkWell(
                    onTap: e.value.isEmpty ? null : () => _showBucketSheet(context, e.key, e.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: _bucketColors[e.key], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                          Text('${e.value.length} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showBucketSheet(BuildContext context, String title, List<Customer> customers) {
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
              Text('$title (${customers.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: customers.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(c.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark))),
                            Text(_rupee.format(c.totalDue), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kRed)),
                          ],
                        ),
                      )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsTable(AppStore store, List<PromiseToPay> rows) {
    return InfoCard(
      children: [
        const Text('Broken PTP Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
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
                    hintText: 'Search customer or salesman',
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
              onTap: () => setState(() => _sort = _sort == _SortBy.dateDesc ? _SortBy.amountDesc : _SortBy.dateDesc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sort == _SortBy.amountDesc ? Icons.currency_rupee : Icons.arrow_downward, size: 13, color: kNavy),
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No broken PTPs match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.take(30).map((p) {
            final c = _customerFor(store, p.customerId);
            final bucket = _brokenBucket(c);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                        Text('${c.branch}  ·  ${store.salesmanDisplayName(c.assignedSalesmanId)}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(p.amountPromised), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kRed))),
                        Text(DateFormat('dd MMM yyyy').format(p.promiseDate), style: const TextStyle(fontSize: 8.5, color: kMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: _bucketColors[bucket]!.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(bucket.split(' ').first, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: _bucketColors[bucket])),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _footer(AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withValues(alpha: 0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          const Expanded(child: Text('Broken PTP figures are based on the latest reconciled commitments and outcome history.', style: TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(onTap: () => setState(() => store.refreshBusySync()), child: const Icon(Icons.refresh, size: 15, color: kBlue)),
        ],
      ),
    );
  }
}
