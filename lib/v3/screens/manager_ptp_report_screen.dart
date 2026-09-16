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
String _lakh(double v) => '${(v / 100000).toStringAsFixed(0)}L';
bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Manager's PTP Report — Kept/Pending/Broken breakdown, trend, due-today
/// and broken summaries, and a searchable/sortable detail table, all
/// derived live from the real `ptps` list (never typed by hand).
/// 'all' shows everything (the plain report); 'dueToday'/'overdue' pre-filter
/// the details table to exactly what the dashboard's "Expected Collection
/// Today" / "Today's Overdue" stat cards claim, instead of landing on the
/// same unfiltered report as every other PTP card.
enum PtpReportQuickFilter { all, dueToday, overdue }

class ManagerPtpReportScreen extends StatefulWidget {
  final String initialBranch;
  final PtpReportQuickFilter initialQuickFilter;
  const ManagerPtpReportScreen({super.key, this.initialBranch = 'All Branches', this.initialQuickFilter = PtpReportQuickFilter.all});

  @override
  State<ManagerPtpReportScreen> createState() => _ManagerPtpReportScreenState();
}

enum _SortBy { dateDesc, dateAsc, amountDesc }

class _ManagerPtpReportScreenState extends State<ManagerPtpReportScreen> {
  String get _branch => context.read<AppStore>().branchFilter;
  late PtpReportQuickFilter _quickFilter;

  @override
  void initState() {
    super.initState();
    _quickFilter = widget.initialQuickFilter;
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _SortBy _sort = _SortBy.dateDesc;

  Customer _customerFor(AppStore store, String customerId) => store.customers.firstWhere((c) => c.id == customerId, orElse: () => store.customers.first);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];
    final now = DateTime.now();

    bool inScope(PromiseToPay p) {
      final c = _customerFor(store, p.customerId);
      return (_branch == 'All Branches' || c.branch == _branch) && (_salesman == 'All Salesmen' || c.assignedSalesmanId == _salesman);
    }

    final ptps = store.ptps.where(inScope).toList();

    double amountFor(bool Function(PromiseToPay) test) => ptps.where(test).fold(0.0, (s, p) => s + p.amountPromised);
    int countFor(bool Function(PromiseToPay) test) => ptps.where(test).length;

    bool isKept(PromiseToPay p) => p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept;
    bool isPending(PromiseToPay p) =>
        p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification || p.status == PtpStatus.financialSyncPending;
    bool isBroken(PromiseToPay p) => p.status == PtpStatus.broken;

    final totalAmount = ptps.fold(0.0, (s, p) => s + p.amountPromised);
    final keptAmount = amountFor(isKept);
    final pendingAmount = amountFor(isPending);
    final brokenAmount = amountFor(isBroken);
    final keptCount = countFor(isKept);
    final pendingCount = countFor(isPending);
    final brokenCount = countFor(isBroken);
    final avgPromise = ptps.isEmpty ? 0.0 : totalAmount / ptps.length;

    final dueToday = ptps
        .where((p) => (p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification) && _isSameDay(p.promiseDate, now))
        .toList()
      ..sort((a, b) => a.promiseDate.compareTo(b.promiseDate));
    final dueTodayTotal = dueToday.fold(0.0, (s, p) => s + p.amountPromised);

    // Same "still scheduled, promise date already passed" population the
    // dashboard's "Today's Overdue" card counts — kept in sync with
    // control_dashboard_screen.dart's own overduePtps computation.
    final startOfToday = DateTime(now.year, now.month, now.day);
    final overdueUnresolved = ptps.where((p) => p.status == PtpStatus.scheduled && p.promiseDate.isBefore(startOfToday)).toList()
      ..sort((a, b) => a.promiseDate.compareTo(b.promiseDate));

    final broken = ptps.where(isBroken).toList()..sort((a, b) => b.promiseDate.compareTo(a.promiseDate));
    final avgBroken = broken.isEmpty ? 0.0 : brokenAmount / broken.length;
    final brokenReasonCounts = <String, int>{};
    for (final p in broken) {
      final r = p.brokenReason ?? 'Others';
      brokenReasonCounts[r] = (brokenReasonCounts[r] ?? 0) + 1;
    }
    final reasonOrder = ['Payment not arranged', 'Cash flow issue', 'Client not reachable', 'Others'];

    // 7-day trend, split by current status of each PTP grouped by promise date.
    final trend = <Map<String, dynamic>>[];
    for (var i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayPtps = ptps.where((p) => _isSameDay(p.promiseDate, day));
      trend.add({
        'label': DateFormat('dd MMM').format(day),
        'kept': dayPtps.where(isKept).fold(0.0, (s, p) => s + p.amountPromised),
        'pending': dayPtps.where(isPending).fold(0.0, (s, p) => s + p.amountPromised),
        'broken': dayPtps.where(isBroken).fold(0.0, (s, p) => s + p.amountPromised),
      });
    }
    final maxTrend = trend.fold<double>(0, (m, t) => [m, (t['kept'] as num).toDouble(), (t['pending'] as num).toDouble(), (t['broken'] as num).toDouble()].reduce((a, b) => a > b ? a : b));
    final chartMax = maxTrend <= 0 ? 100000.0 : maxTrend * 1.2;

    var tableRows = ptps.where((p) {
      switch (_quickFilter) {
        case PtpReportQuickFilter.dueToday:
          if (!dueToday.contains(p)) return false;
          break;
        case PtpReportQuickFilter.overdue:
          if (!overdueUnresolved.contains(p)) return false;
          break;
        case PtpReportQuickFilter.all:
          break;
      }
      if (_query.trim().isEmpty) return true;
      final c = _customerFor(store, p.customerId);
      final q = _query.trim().toLowerCase();
      return c.name.toLowerCase().contains(q) || c.assignedSalesmanId.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _SortBy.dateDesc:
        tableRows.sort((a, b) => b.promiseDate.compareTo(a.promiseDate));
        break;
      case _SortBy.dateAsc:
        tableRows.sort((a, b) => a.promiseDate.compareTo(b.promiseDate));
        break;
      case _SortBy.amountDesc:
        tableRows.sort((a, b) => b.amountPromised.compareTo(a.amountPromised));
        break;
    }

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, store),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (_quickFilter != PtpReportQuickFilter.all) ...[
                        _quickFilterBanner(_quickFilter == PtpReportQuickFilter.dueToday
                            ? 'Showing ${dueToday.length} PTP(s) due today only.'
                            : 'Showing ${overdueUnresolved.length} overdue, unresolved PTP(s) only.'),
                        const SizedBox(height: 14),
                      ],
                      _filterRow(branches, salesmenNames),
                      const SizedBox(height: 20),
                      _statCards(totalAmount, avgPromise, keptAmount, keptCount, pendingAmount, pendingCount, brokenAmount, brokenCount),
                      const SizedBox(height: 20),
                      _statusDistribution(totalAmount, keptAmount, pendingAmount, brokenAmount),
                      const SizedBox(height: 20),
                      _ptpTrend(trend, chartMax),
                      const SizedBox(height: 20),
                      _dueTodayCard(context, store, dueToday, dueTodayTotal),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _brokenSummaryCard(context, brokenAmount, brokenCount, avgBroken, totalAmount, brokenReasonCounts, reasonOrder)),
                          const SizedBox(width: 12),
                          Expanded(child: _recentBrokenCard(context, store, broken)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _detailsTable(store, tableRows),
                      const SizedBox(height: 20),
                      _footer(store),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
                Text('PTP Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Promise to Pay analysis and summary', style: TextStyle(fontSize: 10.5, color: kMuted)),
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
  /// Shown only when this screen was opened from a dashboard card that
  /// pre-filters the table (see PtpReportQuickFilter) — makes the filter
  /// visible and gives the RE a way back to the full report.
  Widget _quickFilterBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.25))),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kBlue))),
          InkWell(
            onTap: () => setState(() => _quickFilter = PtpReportQuickFilter.all),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('CLEAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kBlue)),
            ),
          ),
        ],
      ),
    );
  }

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
  Widget _statCards(double total, double avg, double kept, int keptCount, double pending, int pendingCount, double broken, int brokenCount) {
    final cards = [
      (Icons.calendar_month_outlined, kPurple, _rupee.format(total), 'Total PTP Amount', 'Avg. Promise: ${_rupee.format(avg)}'),
      (Icons.check_circle, kGreen, _rupee.format(kept), 'PTP Kept', '${total <= 0 ? 0 : (kept / total * 100).toStringAsFixed(2)}%  ·  Count: $keptCount'),
      (Icons.access_time_filled, kOrange, _rupee.format(pending), 'PTP Pending (Due)', '${total <= 0 ? 0 : (pending / total * 100).toStringAsFixed(2)}%  ·  Count: $pendingCount'),
      (Icons.link_off, kRed, _rupee.format(broken), 'PTP Broken', '${total <= 0 ? 0 : (broken / total * 100).toStringAsFixed(2)}%  ·  Count: $brokenCount'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.65,
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
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(sub, style: const TextStyle(fontSize: 9, color: kMuted))),
            ],
          ),
        );
      }).toList(),
    );
  }

  // -------------------------------------------------------------------
  // Status distribution
  // -------------------------------------------------------------------
  Widget _statusDistribution(double total, double kept, double pending, double broken) {
    final buckets = [('Kept', kept, kGreen), ('Pending (Due)', pending, kOrange), ('Broken', broken, kRed)];
    return InfoCard(
      children: [
        const Text('PTP Status Distribution (Amount)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(PieChartData(centerSpaceRadius: 32, sectionsSpace: 2, sections: buckets.where((b) => b.$2 > 0).map((b) => PieChartSectionData(value: b.$2, color: b.$3, radius: 22, showTitle: false)).toList())),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kNavy))),
                      const Text('Total', style: TextStyle(fontSize: 8.5, color: kMuted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buckets.map((b) {
                  final pct = total <= 0 ? 0.0 : (b.$2 / total * 100);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: b.$3, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.$1, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600)),
                              Text('${_rupee.format(b.$2)} (${pct.toStringAsFixed(2)}%)', style: const TextStyle(fontSize: 9, color: kMuted)),
                            ],
                          ),
                        ),
                      ],
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

  // -------------------------------------------------------------------
  // PTP trend
  // -------------------------------------------------------------------
  Widget _ptpTrend(List<Map<String, dynamic>> trend, double chartMax) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('PTP Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy))),
            _legendDot(kGreen, 'Kept'),
            const SizedBox(width: 8),
            _legendDot(kOrange, 'Pending'),
            const SizedBox(width: 8),
            _legendDot(kRed, 'Broken'),
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
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, m) => Text(_lakh(v), style: const TextStyle(fontSize: 8, color: kMuted)))),
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
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['kept'] as num).toDouble())], isCurved: true, color: kGreen, barWidth: 2.5, dotData: const FlDotData(show: true)),
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['pending'] as num).toDouble())], isCurved: true, color: kOrange, barWidth: 2.5, dotData: const FlDotData(show: true)),
                LineChartBarData(spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['broken'] as num).toDouble())], isCurved: true, color: kRed, barWidth: 2.5, dotData: const FlDotData(show: true)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
    ]);
  }

  // -------------------------------------------------------------------
  // PTP Due Today
  // -------------------------------------------------------------------
  Widget _dueTodayCard(BuildContext context, AppStore store, List<PromiseToPay> dueToday, double dueTodayTotal) {
    final shown = dueToday.take(5).toList();
    return InfoCard(
      children: [
        Row(
          children: [
            Expanded(child: Text('PTP Due Today (${DateFormat('dd MMM yyyy').format(DateTime.now())})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen())),
              child: const Text('View All', style: TextStyle(color: kBlue, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No PTPs due today in this view.', style: TextStyle(fontSize: 12, color: kMuted)))
        else ...[
          ...shown.map((p) {
            final c = _customerFor(store, p.customerId);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
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
                        FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(p.amountPromised), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark))),
                        Text(DateFormat('hh:mm a').format(p.promiseDate), style: const TextStyle(fontSize: 9.5, color: kMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _showPtpDetail(context, c, p),
                    child: const Icon(Icons.access_time_filled, size: 18, color: kGreen),
                  ),
                ],
              ),
            );
          }),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          Row(
            children: [
              Expanded(child: Text('Total (${dueToday.length} Accounts)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavy))),
              Text(_rupee.format(dueTodayTotal), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kGreen)),
            ],
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------
  // Broken summary + recent broken
  // -------------------------------------------------------------------
  Widget _brokenSummaryCard(BuildContext context, double brokenAmount, int brokenCount, double avgBroken, double total, Map<String, int> reasonCounts, List<String> reasonOrder) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('PTP Broken Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavy))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen())),
              child: const Text('View All', style: TextStyle(color: kBlue, fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _kv('Total Broken Amount', _rupee.format(brokenAmount), kRed),
        _kv('Broken PTP Count', '$brokenCount', kDark),
        _kv('Avg. Broken Amount', _rupee.format(avgBroken), kDark),
        _kv('% of Total PTP', '${total <= 0 ? 0 : (brokenAmount / total * 100).toStringAsFixed(2)}%', kOrange),
        const SizedBox(height: 10),
        const Text('Top Reasons for Broken PTP', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kNavy)),
        const SizedBox(height: 8),
        if (brokenCount == 0)
          const Text('No broken PTPs in this view.', style: TextStyle(fontSize: 11, color: kMuted))
        else
          ...reasonOrder.where((r) => (reasonCounts[r] ?? 0) > 0).map((r) {
            final count = reasonCounts[r] ?? 0;
            final pct = brokenCount <= 0 ? 0.0 : count / brokenCount;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 92, child: Text(r, style: const TextStyle(fontSize: 9.5, color: kDark))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: kBorder, valueColor: const AlwaysStoppedAnimation<Color>(kRed)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('$count (${(pct * 100).toStringAsFixed(2)}%)', style: const TextStyle(fontSize: 9, color: kMuted)),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _kv(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 10, color: kMuted))),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _recentBrokenCard(BuildContext context, AppStore store, List<PromiseToPay> broken) {
    final shown = broken.take(5).toList();
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('Recent Broken PTPs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavy))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyRecoveryQueueScreen())),
              child: const Text('View All', style: TextStyle(color: kBlue, fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const Text('No broken PTPs in this view.', style: TextStyle(fontSize: 11, color: kMuted))
        else
          ...shown.map((p) {
            final c = _customerFor(store, p.customerId);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark)),
                        Text(store.salesmanDisplayName(c.assignedSalesmanId), style: const TextStyle(fontSize: 9.5, color: kMuted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_rupee.format(p.amountPromised), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kRed)),
                      Text(DateFormat('dd MMM yyyy').format(p.promiseDate), style: const TextStyle(fontSize: 9, color: kMuted)),
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
  // PTP details table
  // -------------------------------------------------------------------
  Widget _detailsTable(AppStore store, List<PromiseToPay> rows) {
    return InfoCard(
      children: [
        const Text('PTP Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
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
              onTap: () => setState(() => _sort = _sort == _SortBy.dateDesc ? _SortBy.dateAsc : (_sort == _SortBy.dateAsc ? _SortBy.amountDesc : _SortBy.dateDesc)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sort == _SortBy.amountDesc ? Icons.currency_rupee : (_sort == _SortBy.dateAsc ? Icons.arrow_upward : Icons.arrow_downward), size: 13, color: kNavy),
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No PTPs match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.take(30).map((p) => _detailRow(store, p)),
      ],
    );
  }

  Widget _detailRow(AppStore store, PromiseToPay p) {
    final c = _customerFor(store, p.customerId);
    String statusLabel;
    Color statusColor;
    switch (p.status) {
      case PtpStatus.kept:
        statusLabel = 'Kept';
        statusColor = kGreen;
        break;
      case PtpStatus.partiallyKept:
        statusLabel = 'Partial';
        statusColor = kBlue;
        break;
      case PtpStatus.broken:
        statusLabel = 'Broken';
        statusColor = kRed;
        break;
      case PtpStatus.financialSyncPending:
        statusLabel = 'Sync Pending';
        statusColor = kMuted;
        break;
      case PtpStatus.scheduled:
        statusLabel = 'Pending';
        statusColor = kOrange;
        break;
      case PtpStatus.pendingVerification:
        statusLabel = 'Verifying';
        statusColor = kOrange;
        break;
    }

    return InkWell(
      onTap: () => _showPtpDetail(context, c, p),
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
                  Text('${c.branch}  ·  ${store.salesmanDisplayName(c.assignedSalesmanId)}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(p.amountPromised), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
                  Text(DateFormat('dd MMM, hh:mm a').format(p.promiseDate), style: const TextStyle(fontSize: 8.5, color: kMuted)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(statusLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor)),
            ),
            const SizedBox(width: 6),
            Icon(_modeIcon(p.paymentMode), size: 15, color: _modeColor(p.paymentMode)),
          ],
        ),
      ),
    );
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'UPI':
        return Icons.qr_code;
      case 'Cheque':
        return Icons.receipt_long_outlined;
      default:
        return Icons.account_balance_outlined;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'UPI':
        return kPurple;
      case 'Cheque':
        return kOrange;
      default:
        return kBlue;
    }
  }

  // -------------------------------------------------------------------
  // Read-only PTP detail sheet (Manager: view only)
  // -------------------------------------------------------------------
  void _showPtpDetail(BuildContext context, Customer c, PromiseToPay p) {
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
              _kv('Promise Amount', _rupee.format(p.amountPromised), kDark),
              _kv('Promise Date & Time', DateFormat('dd MMM yyyy, hh:mm a').format(p.promiseDate), kDark),
              _kv('Payment Mode', p.paymentMode, kDark),
              _kv('Status', p.status.name, kDark),
              if (p.amountReceived != null) _kv('Amount Received', _rupee.format(p.amountReceived!), kGreen),
              if (p.brokenReason != null) _kv('Broken Reason', p.brokenReason!, kRed),
              const SizedBox(height: 8),
              const Text('Manager view is read-only — actions on this PTP are taken by the Recovery Executive or the assigned salesperson.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Footer
  // -------------------------------------------------------------------
  Widget _footer(AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(child: Text('All amounts are in INR. Data is as per promises recorded up to ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}.', style: const TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(onTap: () => setState(() => store.refreshBusySync()), child: const Icon(Icons.refresh, size: 15, color: kBlue)),
        ],
      ),
    );
  }
}
