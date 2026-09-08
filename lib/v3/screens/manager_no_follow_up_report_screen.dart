import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const double _kHighValueThreshold = 200000;

String _priority(int days) {
  if (days >= 15) return 'Critical';
  if (days >= 11) return 'High';
  if (days >= 7) return 'Medium';
  return 'Low';
}

Color _priorityColor(String p) {
  switch (p) {
    case 'Critical':
      return kRed;
    case 'High':
      return kOrange;
    case 'Medium':
      return const Color(0xFFCA8A04);
    default:
      return kGreen;
  }
}

/// Manager's No Follow-Up Report — same real "no recent activity" analysis
/// as the RE's report (customers with due exposure and no logged follow-up
/// within the control window), restyled to the Manager visual language.
class ManagerNoFollowUpReportScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerNoFollowUpReportScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerNoFollowUpReportScreen> createState() => _ManagerNoFollowUpReportScreenState();
}

enum _SortBy { daysDesc, amountDesc }

class _ManagerNoFollowUpReportScreenState extends State<ManagerNoFollowUpReportScreen> {
  late String _branch;

  @override
  void initState() {
    super.initState();
    _branch = widget.initialBranch;
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _SortBy _sort = _SortBy.daysDesc;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = ['All Branches', ...{for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}];
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];

    final items = store.noFollowUpAccounts.where((c) => (_branch == 'All Branches' || c.branch == _branch) && (_salesman == 'All Salesmen' || c.assignedSalesmanId == _salesman)).toList()
      ..sort((a, b) => store.daysSinceLastFollowUp(b).compareTo(store.daysSinceLastFollowUp(a)));

    final outstandingAtRisk = items.fold(0.0, (s, c) => s + c.totalDue);
    final highValueCount = items.where((c) => c.totalDue >= _kHighValueThreshold).length;
    final salesmenInvolved = items.map((c) => c.assignedSalesmanId).where((s) => s.isNotEmpty).toSet().length;
    final avgDays = items.isEmpty ? 0.0 : items.fold(0, (s, c) => s + store.daysSinceLastFollowUp(c)) / items.length;
    final criticalCount = items.where((c) => store.daysSinceLastFollowUp(c) >= 15).length;

    final priorityCounts = <String, int>{'Critical': 0, 'High': 0, 'Medium': 0, 'Low': 0};
    for (final c in items) {
      final p = _priority(store.daysSinceLastFollowUp(c));
      priorityCounts[p] = (priorityCounts[p] ?? 0) + 1;
    }

    final trend = store.noFollowUpTrend;
    final maxTrend = trend.fold<int>(0, (m, t) => (t['count'] as int) > m ? (t['count'] as int) : m);
    final chartMax = maxTrend <= 0 ? 5.0 : maxTrend * 1.3;

    var rows = items.where((c) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return c.name.toLowerCase().contains(q) || c.assignedSalesmanId.toLowerCase().contains(q);
    }).toList();
    if (_sort == _SortBy.amountDesc) rows.sort((a, b) => b.totalDue.compareTo(a.totalDue));

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
                      _statCards(items.length, outstandingAtRisk, highValueCount, salesmenInvolved, avgDays, criticalCount),
                      const SizedBox(height: 20),
                      _trendCard(trend, chartMax),
                      const SizedBox(height: 20),
                      _priorityRow(priorityCounts),
                      const SizedBox(height: 20),
                      _detailsTable(store, rows),
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
                Text('No Follow-up Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Accounts with no follow-up in the selected period', style: TextStyle(fontSize: 10, color: kMuted)),
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
        Expanded(child: _dropdownPill(Icons.apartment_outlined, kBlue, _branch, branches, (v) => setState(() => _branch = v))),
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

  Widget _statCards(int count, double outstanding, int highValue, int salesmenInvolved, double avgDays, int critical) {
    final cards = [
      (Icons.person_off_outlined, kPurple, '$count', 'No Follow-Up Accounts', ''),
      (Icons.warning_amber_rounded, kRed, _rupee.format(outstanding), 'Outstanding at Risk', ''),
      (Icons.diamond_outlined, const Color(0xFFCA8A04), '$highValue', 'High Value Accounts', ''),
      (Icons.groups_outlined, kBlue, '$salesmenInvolved', 'Salesmen Involved', ''),
      (Icons.schedule, kGreen, (avgDays.toStringAsFixed(1)), 'Avg Days Since Follow-Up', ''),
      (Icons.error_outline, kRed, '$critical', 'Critical (15+ Days)', ''),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
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
        const Text('No Follow-Up Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
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
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['count'] as num).toDouble())], isCurved: true, color: kBlue, barWidth: 2.5, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: kBlue.withOpacity(0.08))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _priorityRow(Map<String, int> priorityCounts) {
    return InfoCard(
      children: [
        const Text('Priority Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        Row(
          children: ['Critical', 'High', 'Medium', 'Low'].map((p) {
            final color = _priorityColor(p);
            final icon = p == 'Critical' ? Icons.error_outline : (p == 'High' ? Icons.arrow_upward : (p == 'Medium' ? Icons.remove : Icons.arrow_downward));
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.15))),
                child: Column(
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(height: 6),
                    Text('${priorityCounts[p]}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
                    Text(p, style: const TextStyle(fontSize: 9, color: kDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _detailsTable(AppStore store, List<Customer> rows) {
    return InfoCard(
      children: [
        const Text('No Follow-Up Account List', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
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
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Search customer or salesman', hintStyle: TextStyle(fontSize: 11, color: kMuted)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _sort = _sort == _SortBy.daysDesc ? _SortBy.amountDesc : _SortBy.daysDesc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sort == _SortBy.amountDesc ? Icons.currency_rupee : Icons.schedule, size: 13, color: kNavy),
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No accounts match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.take(30).map((c) {
            final days = store.daysSinceLastFollowUp(c);
            final priority = _priority(days);
            final color = _priorityColor(priority);
            return InkWell(
              onTap: () => _showDetail(context, c, days, priority),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                          Text('${store.salesmanDisplayName(c.assignedSalesmanId)}  ·  $days days', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(c.totalDue), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(priority, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color)),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _showDetail(BuildContext context, Customer c, int days, String priority) {
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
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
              Text('${c.branch}  ·  ${context.read<AppStore>().salesmanDisplayName(c.assignedSalesmanId)}', style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 14),
              _kv('Outstanding Due', _rupee.format(c.totalDue)),
              _kv('Days Since Last Follow-Up', '$days days'),
              _kv('Priority', priority),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c, readOnly: true)));
                  },
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('View Full Customer 360', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Manager view is read-only — follow-up actions are taken by the assigned salesperson.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.w600)),
        ],
      ),
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
          const Expanded(child: Text('No Follow-Up Accounts are customers with due exposure and no logged activity within the control window (${AppStore.noFollowUpThresholdDays}+ days).', style: TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(onTap: () => setState(() => store.refreshBusySync()), child: const Icon(Icons.refresh, size: 15, color: kBlue)),
        ],
      ),
    );
  }
}
