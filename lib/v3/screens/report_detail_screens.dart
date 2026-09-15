import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class ReportFilters {
  final String dateRange; // Today | This Week | This Month | This Quarter | All Time
  final String branch; // All Branches or specific
  final String salesman; // All Salesmen or specific
  const ReportFilters({this.dateRange = 'This Month', this.branch = 'All Branches', this.salesman = 'All Salesmen'});

  bool matchesDate(DateTime d) {
    final now = DateTime.now();
    switch (dateRange) {
      case 'Today':
        return d.year == now.year && d.month == now.month && d.day == now.day;
      case 'This Week':
        return d.difference(now).inDays.abs() <= 7;
      case 'This Month':
        return d.year == now.year && d.month == now.month;
      case 'This Quarter':
        return d.difference(now).inDays.abs() <= 90;
      default:
        return true;
    }
  }

  bool matchesCustomer(Customer c) => (branch == 'All Branches' || c.branch == branch) && (salesman == 'All Salesmen' || c.assignedSalesmanId == salesman);
}

class _ReportScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _ReportScaffold({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kNavy,
        centerTitle: true,
        title: Column(children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
          Text(subtitle, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: children),
    );
  }
}

/// Bounds a long salesman-data list to a fixed viewport with its own
/// internal scroll, so a report page with many salesmen doesn't force one
/// giant outer scroll — the operator scrolls this block, then moves on to
/// the rest of the report below it.
Widget _scrollableBlock(List<Widget> children, {double maxHeight = 420}) {
  final controller = ScrollController();
  return Container(
    constraints: BoxConstraints(maxHeight: maxHeight),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
    child: Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ListView(
        controller: controller,
        shrinkWrap: true,
        padding: const EdgeInsets.only(right: 10),
        children: children,
      ),
    ),
  );
}

/// Inline "no data" message for use inside an [InfoCard] whose list content
/// can be empty.
Widget _emptyText(String message) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Text(message, style: const TextStyle(fontSize: 12, color: kMuted))),
    );

/// Standalone bordered "no data" card for sections that build a list of
/// cards directly (not wrapped in an [InfoCard]) and can be empty.
Widget _emptyCard(String message) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Center(child: Text(message, style: const TextStyle(fontSize: 12, color: kMuted))),
    );

/// Reusable inline filter bar for one report page — Branch/Salesperson are
/// shown on every report (every report scopes its data by `matchesCustomer`),
/// Date Range only on the reports that actually apply `matchesDate`
/// (PTP Report, Broken PTP Report, Dispute Status Report, Expected vs Actual
/// Collection). Previously one shared Date Range/Branch/Salesperson panel
/// lived on the Reports list screen and applied identically to every
/// report — including ones like Ageing Receivables or Recovery Target that
/// never used the date range at all, which was misleading. Each report page
/// now owns exactly the filters it uses.
class _ReportFilterBar extends StatelessWidget {
  final bool showDateRange;
  final String dateRange;
  final ValueChanged<String>? onDateRangeChanged;
  final String branch;
  final ValueChanged<String> onBranchChanged;
  final String salesman;
  final ValueChanged<String> onSalesmanChanged;
  const _ReportFilterBar({
    this.showDateRange = false,
    this.dateRange = 'This Month',
    this.onDateRangeChanged,
    required this.branch,
    required this.onBranchChanged,
    required this.salesman,
    required this.onSalesmanChanged,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];
    String salesmanLabel(String v) => v == 'All Salesmen' ? v : store.salesmanDisplayName(v);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InfoCard(children: [
        if (showDateRange) ...[
          _filterDropdown(Icons.calendar_today_outlined, kPurple, 'Date Range', dateRange, const ['Today', 'This Week', 'This Month', 'This Quarter', 'All Time'], onDateRangeChanged!),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
        ],
        _filterDropdown(Icons.apartment_outlined, kBlue, 'Branch', branch, branches, onBranchChanged),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
        _filterDropdown(Icons.person_outline, kBlue, 'Salesperson', salesman, salesmenNames, onSalesmanChanged, labelFor: salesmanLabel),
      ]),
    );
  }

  Widget _filterDropdown(IconData icon, Color color, String label, String value, List<String> options, ValueChanged<String> onChanged, {String Function(String)? labelFor}) {
    String text(String o) => labelFor != null ? labelFor(o) : o;
    // Guards against a value (e.g. a salesman removed from the roster since
    // this filter was set) that no longer appears in `options` — Dropdown
    // asserts if `value` isn't one of its `items`.
    final safeValue = options.contains(value) ? value : options.first;
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: safeValue,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kDark),
                  items: options.map((o) => DropdownMenuItem(value: o, child: Text(text(o), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) { if (v != null) onChanged(v); },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reusable inline search box for a report's salesman/customer list section.
/// Purely a text field — the caller owns the query state and does the
/// actual filtering, so this stays a stateless building block usable from
/// any report regardless of whether that report is itself stateful.
class _ReportSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _ReportSearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12.5, color: kMuted),
          prefixIcon: const Icon(Icons.search, size: 18, color: kMuted),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBlue)),
        ),
      ),
    );
  }
}

Widget _drillRow(BuildContext context, String label, String sub, String value, Color valueColor, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 10.5, color: kMuted)),
              ],
            ),
          ),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 16, color: kMuted),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------
// 1) Daily Recovery Summary
// ---------------------------------------------------------------------
class DailyRecoverySummaryReport extends StatefulWidget {
  final ReportFilters filters;
  const DailyRecoverySummaryReport({super.key, required this.filters});

  @override
  State<DailyRecoverySummaryReport> createState() => _DailyRecoverySummaryReportState();
}

class _DailyRecoverySummaryReportState extends State<DailyRecoverySummaryReport> {
  bool _showPercentage = false;
  String _salesmanQuery = '';
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final filters = ReportFilters(branch: _branch, salesman: _salesman);
    final now = DateTime.now();

    final salesmenAll = store.salesmen
        .where((s) => (filters.branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == filters.branch) && (filters.salesman == 'All Salesmen' || s['name'] == filters.salesman))
        .toList()
      ..sort((a, b) => ((b['collectionAchieved'] as num).toDouble()).compareTo((a['collectionAchieved'] as num).toDouble()));

    // Top Salesmen Performance only lists salesmen who currently carry
    // overdue exposure — a salesman with zero total overdue has nothing to
    // recover and clutters the leaderboard.
    final salesmenWithOverdue = salesmenAll.where((s) => ((s['totalOverdue'] as num?) ?? 0) > 0).toList();
    final salesmenSearched = salesmenWithOverdue
        .where((s) => ((s['fullName'] as String?) ?? s['name'] as String).toLowerCase().contains(_salesmanQuery.toLowerCase()))
        .toList();

    final totalTarget = salesmenAll.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));

    final salesmenNames = salesmenAll.map((s) => s['name'] as String).toSet();
    final todaysVisits = store.tasks.where((t) => t.type == TaskType.physicalVisit && salesmenNames.contains(t.ownerId) && _isSameDay(t.deadline, now)).length;

    // "Collected" for a report titled Daily Recovery Summary must mean
    // TODAY's collection, not each salesman's all-time kept-PTP total (that
    // lifetime figure is `collectionAchieved`, used elsewhere for the
    // ongoing recovery score). A PTP matures on its promise date, so a PTP
    // kept/partiallyKept whose promiseDate is today is what actually closed
    // today.
    final ownedCustomerIds = store.customers.where((c) => salesmenNames.contains(c.assignedSalesmanId)).map((c) => c.id).toSet();
    final totalCollected = store.ptps
        .where((p) =>
            ownedCustomerIds.contains(p.customerId) &&
            (p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept) &&
            _isSameDay(p.promiseDate, now))
        .fold(0.0, (s, p) => s + (p.amountReceived ?? 0));
    final pendingAmount = (totalTarget - totalCollected) < 0 ? 0.0 : (totalTarget - totalCollected);
    final collectionPercent = totalTarget <= 0 ? 0.0 : (totalCollected / totalTarget * 100).clamp(0, 999);

    final trend = store.dailyCollectionTrend;
    final maxTrendAmount = trend.fold<double>(0, (m, e) => ((e['amount'] as num).toDouble()) > m ? ((e['amount'] as num).toDouble()) : m);

    return _ReportScaffold(
      title: 'Daily Recovery Summary',
      subtitle: 'Collections, targets and daily closure',
      children: [
        _ReportFilterBar(
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.flag_outlined, kPurple, _rupee.format(totalTarget), 'Total Target'),
            _statTile(Icons.account_balance_wallet_outlined, kGreen, _rupee.format(totalCollected), 'Total Collected'),
            _statTile(Icons.hourglass_empty, kOrange, _rupee.format(pendingAmount), 'Pending Amount'),
            _statTile(Icons.directions_walk, kBlue, '$todaysVisits', "Today's Visits"),
            _statTile(Icons.percent, kTeal, '${collectionPercent.toStringAsFixed(1)}%', 'Collection %'),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: Text('Collection Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy))),
            _toggleChip('Amount', !_showPercentage, () => setState(() => _showPercentage = false)),
            const SizedBox(width: 6),
            _toggleChip('Percentage', _showPercentage, () => setState(() => _showPercentage = true)),
          ],
        ),
        const SizedBox(height: 10),
        InfoCard(children: [
          _summaryRow('Collected Amount', totalCollected, totalTarget, kGreen),
          const SizedBox(height: 14),
          _summaryRow('Pending Amount', pendingAmount, totalTarget, kOrange),
        ]),
        const SizedBox(height: 20),
        const Text('Collection Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: trend.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = trend[i];
                final amount = (e['amount'] as num).toDouble();
                final isLast = i == trend.length - 1;
                final barHeight = maxTrendAmount <= 0 ? 4.0 : 8 + (amount / maxTrendAmount) * 44;
                return SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(_shortRupee(amount), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isLast ? kBlue : kMuted)),
                      const SizedBox(height: 4),
                      Container(height: barHeight, decoration: BoxDecoration(color: isLast ? kBlue : kBlue.withOpacity(0.35), borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 6),
                      Text(e['label'] as String, style: const TextStyle(fontSize: 9, color: kMuted)),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Text('Top Salesmen Performance · ${salesmenWithOverdue.length} Salesmen', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search salesman by name...', onChanged: (v) => setState(() => _salesmanQuery = v)),
        _scrollableBlock([
          InfoCard(
            children: salesmenSearched.isEmpty
                ? [_emptyText('No salesmen match this filter.')]
                : salesmenSearched.map((s) {
              final name = (s['fullName'] as String?) ?? s['name'] as String;
              final target = (s['collectionTarget'] as num).toDouble();
              final achieved = (s['collectionAchieved'] as num).toDouble();
              final percent = s['collectionAchievedPercent'] as int;
              final color = percent >= 100 ? kGreen : (percent >= 60 ? kBlue : (percent >= 30 ? kOrange : kRed));
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(radius: 15, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 10.5, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
                          Text('Target ${_rupee.format(target)} · Collected ${_rupee.format(achieved)}', style: const TextStyle(fontSize: 10, color: kMuted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text('$percent%', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: selected ? kBlue : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: selected ? kBlue : kBorder)),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : kMuted)),
      ),
    );
  }

  Widget _summaryRow(String label, double amount, double total, Color color) {
    final percent = total <= 0 ? 0.0 : (amount / total * 100).clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kDark))),
            Text(_showPercentage ? '${percent.toStringAsFixed(1)}%' : _rupee.format(amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: percent / 100, minHeight: 8, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(color)),
        ),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 2) Salesman Performance Report
// ---------------------------------------------------------------------
String _performanceBand(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 60) return 'Good';
  if (score >= 40) return 'Average';
  if (score >= 20) return 'Below Average';
  return 'Poor';
}

Color _performanceBandColor(String band) {
  switch (band) {
    case 'Excellent':
      return kGreen;
    case 'Good':
      return kBlue;
    case 'Average':
      return kOrange;
    case 'Below Average':
      return const Color(0xFFEA580C);
    default:
      return kRed;
  }
}

double _collectedFor(AppStore store, String name) {
  final ids = store.customers.where((c) => c.assignedSalesmanId == name).map((c) => c.id).toSet();
  return store.ptps.where((p) => ids.contains(p.customerId) && (p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept)).fold(0.0, (s, p) => s + (p.amountReceived ?? 0));
}

double _brokenRateFor(AppStore store, String name) {
  final ids = store.customers.where((c) => c.assignedSalesmanId == name).map((c) => c.id).toSet();
  final matured = store.ptps.where((p) => ids.contains(p.customerId) && p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification && p.status != PtpStatus.financialSyncPending).toList();
  if (matured.isEmpty) return 0;
  return matured.where((p) => p.status == PtpStatus.broken).length / matured.length * 100;
}

int _noFollowUpCountFor(AppStore store, String name) => store.noValidNextActionCustomers.where((c) => c.assignedSalesmanId == name).length;

double _aging60For(AppStore store, String name) => store.customers.where((c) => c.assignedSalesmanId == name).fold(0.0, (s, c) => s + (c.agingBuckets['>60'] ?? 0));

double _followUpDisciplineFor(Map<String, dynamic> s) {
  final components = (s['recoveryScoreComponents'] as Map?)?.cast<String, num>();
  return (components?['followUpDiscipline'] ?? 0).toDouble();
}

class SalesmanPerformanceReport extends StatefulWidget {
  final ReportFilters filters;
  const SalesmanPerformanceReport({super.key, required this.filters});

  @override
  State<SalesmanPerformanceReport> createState() => _SalesmanPerformanceReportState();
}

class _SalesmanPerformanceReportState extends State<SalesmanPerformanceReport> {
  String _query = '';
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final salesmen = store.salesmen.where((s) =>
        (filters.branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == filters.branch) &&
        (filters.salesman == 'All Salesmen' || s['name'] == filters.salesman)).toList();
    final branchCount = {for (final s in salesmen) ((s['branch'] as String?) ?? 'Turning Point')}.length;

    final avgScore = salesmen.isEmpty ? 0.0 : salesmen.fold(0.0, (a, s) => a + (s['recoveryScore'] as int)) / salesmen.length;
    final sortedByScore = [...salesmen]..sort((a, b) => (b['recoveryScore'] as int).compareTo(a['recoveryScore'] as int));
    final sortedByScoreSearched = sortedByScore
        .where((s) => ((s['fullName'] as String?) ?? s['name'] as String).toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final topPerformer = sortedByScore.isEmpty ? null : sortedByScore.first;
    final totalCollected = salesmen.fold(0.0, (s, sm) => s + _collectedFor(store, sm['name']));

    final ids = salesmen.map((s) => s['name']).toSet();
    final customerById = {for (final c in store.customers) c.id: c};
    final companyMatured = store.ptps.where((p) {
      final c = customerById[p.customerId];
      return c != null && ids.contains(c.assignedSalesmanId) && p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification && p.status != PtpStatus.financialSyncPending;
    }).toList();
    final companyBroken = companyMatured.where((p) => p.status == PtpStatus.broken).length;
    final brokenRate = companyMatured.isEmpty ? 0.0 : companyBroken / companyMatured.length * 100;

    final noFollowUpCustomers = store.noValidNextActionCustomers.where((c) => ids.contains(c.assignedSalesmanId)).toList();
    final noFollowUpAmount = noFollowUpCustomers.fold(0.0, (s, c) => s + c.totalDue);

    // Performance distribution bands (real, from live recoveryScore)
    final bands = ['Excellent', 'Good', 'Average', 'Below Average', 'Poor'];
    final bandCounts = {for (final b in bands) b: salesmen.where((s) => _performanceBand(s['recoveryScore'] as int) == b).length};

    final trend = store.recoveryScoreTrend;

    return _ReportScaffold(
      title: 'Salesman Performance Report',
      subtitle: 'Track recovery discipline, collection performance and follow-up quality',
      children: [
        _ReportFilterBar(
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        _statGrid([
          (Icons.groups_outlined, kPurple, '${salesmen.length}', 'Total Salesmen Evaluated', 'Across $branchCount Branches'),
          (Icons.star_outline, kGreen, '${avgScore.toStringAsFixed(2)}%', 'Average Recovery Score', 'Weighted Performance Index'),
          (Icons.emoji_events_outlined, const Color(0xFFCA8A04), topPerformer != null ? '${(topPerformer['recoveryScore'] as int).toStringAsFixed(0)}%' : '-', 'Top Performer Score', topPerformer != null ? '${topPerformer['name']} · ${(topPerformer['branch'] as String?) ?? 'Turning Point'}' : '-'),
          (Icons.currency_rupee, kBlue, _rupee.format(totalCollected), 'Total Collection Achieved', '${companyMatured.length} matured PTPs'),
          (Icons.shield_outlined, kRed, '${brokenRate.toStringAsFixed(2)}%', 'Broken PTP Rate', '$companyBroken of ${companyMatured.length} matured'),
          (Icons.notifications_active_outlined, kOrange, _rupee.format(noFollowUpAmount), 'No Follow-Up Accounts', '${noFollowUpCustomers.length} customers'),
        ]),
        const SizedBox(height: 20),
        const Text('Recovery Score Trend (Last 6 Months)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: 25, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9, color: kMuted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= trend.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'], style: const TextStyle(fontSize: 9, color: kMuted)));
                  })),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['score'] as num).toDouble())],
                    isCurved: true,
                    color: kBlue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: kBlue.withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Performance Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    sections: bands.map((b) {
                      final count = bandCounts[b]!;
                      return PieChartSectionData(value: count.toDouble(), color: _performanceBandColor(b), radius: 26, showTitle: false);
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bands.map((b) {
                    final count = bandCounts[b]!;
                    final pct = salesmen.isEmpty ? 0.0 : count / salesmen.length * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: _performanceBandColor(b), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(b, style: const TextStyle(fontSize: 11, color: kDark, fontWeight: FontWeight.w600))),
                          Text('$count (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(child: Text('${salesmen.length} Salesmen', style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 20),
        const Text('Salesman Performance Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search salesman by name...', onChanged: (v) => setState(() => _query = v)),
        _scrollableBlock(sortedByScoreSearched.isEmpty ? [_emptyText('No salesmen match this search.')] : sortedByScoreSearched.map((s) {
          final name = s['name'] as String;
          final displayName = (s['fullName'] as String?) ?? name;
          final score = s['recoveryScore'] as int;
          final band = _performanceBand(score);
          final bandColor = _performanceBandColor(band);
          final collected = _collectedFor(store, name);
          final brokenPct = _brokenRateFor(store, name);
          final followUp = _followUpDisciplineFor(s);
          final noFollowUp = _noFollowUpCountFor(store, name);
          final aging60 = _aging60For(store, name);
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesmanScoreDetailScreen(salesman: s, store: store))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: InfoCard(children: [
                Row(children: [
                  CircleAvatar(radius: 16, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(displayName), style: TextStyle(color: avatarColorFor(name), fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kDark)),
                        Text((s['branch'] as String?) ?? 'Turning Point', style: const TextStyle(fontSize: 10, color: kMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bandColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(band, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: bandColor)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: kMuted),
                ]),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                KeyValueRow('Recovery Score', '$score%', valueColor: bandColor),
                KeyValueRow('Collection Achieved', _rupee.format(collected)),
                KeyValueRow('Follow-Up Discipline', '${followUp.toStringAsFixed(1)}%'),
                KeyValueRow('Broken PTP Rate', '${brokenPct.toStringAsFixed(1)}%', valueColor: kRed),
                KeyValueRow('No Follow-Up Accounts', '$noFollowUp'),
                KeyValueRow('Aging > 60 Days', _rupee.format(aging60), valueColor: kOrange),
              ]),
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Score Components & Weightage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          _weightRow(Icons.currency_rupee, kBlue, 'Collection Performance', 40),
          _weightRow(Icons.call_outlined, kGreen, 'Follow-Up Discipline', 20),
          _weightRow(Icons.event_available_outlined, kPurple, 'PTP Discipline & Quality', 15),
          _weightRow(Icons.trending_down, kOrange, 'Old Outstanding Reduction', 10),
          _weightRow(Icons.notifications_active_outlined, kRed, 'No Follow-Up Control', 10),
          _weightRow(Icons.fact_check_outlined, kTeal, 'Process / Evidence Discipline', 5),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
            Text('100% · Weighted Performance Index', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: kBlue)),
          ]),
        ]),
        const SizedBox(height: 20),
        const Text('Top 5 Performers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: sortedByScore.isEmpty ? [_emptyText('No salesmen match this filter.')] : sortedByScore.take(5).toList().asMap().entries.map((e) {
          final medal = ['🥇', '🥈', '🥉', '4', '5'][e.key];
          final s = e.value;
          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesmanScoreDetailScreen(salesman: s, store: store))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 24, child: Text(medal, style: const TextStyle(fontSize: 14))),
                  const SizedBox(width: 8),
                  Expanded(child: Text((s['fullName'] as String?) ?? s['name'] as String, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark))),
                  Text('${s['recoveryScore']}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _performanceBandColor(_performanceBand(s['recoveryScore'] as int)))),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 15, color: kMuted),
                ],
              ),
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Score Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          _legendRow('Excellent', '80% and above'),
          _legendRow('Good', '60% – 79%'),
          _legendRow('Average', '40% – 59%'),
          _legendRow('Below Average', '20% – 39%'),
          _legendRow('Poor', 'Below 20%'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDBA74))),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 15, color: Color(0xFFC2410C)),
            SizedBox(width: 8),
            Expanded(child: Text('Scores and achievements are calculated live from current recovery data for the selected date range.', style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statGrid(List<(IconData, Color, String, String, String)> cards) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cards.map((c) {
        final (icon, color, value, label, sub) = c;
        return SizedBox(
          width: 160,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 9.5, color: kMuted)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _weightRow(IconData icon, Color color, String label, int pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark))),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct / 40, minHeight: 6, backgroundColor: kBg, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text('$pct%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _legendRow(String label, String range) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: _performanceBandColor(label), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark, fontWeight: FontWeight.w600))),
          Text(range, style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
      ),
    );
  }
}

class SalesmanScoreDetailScreen extends StatefulWidget {
  final Map<String, dynamic> salesman;
  final AppStore store;
  const SalesmanScoreDetailScreen({super.key, required this.salesman, required this.store});

  @override
  State<SalesmanScoreDetailScreen> createState() => _SalesmanScoreDetailScreenState();
}

class _SalesmanScoreDetailScreenState extends State<SalesmanScoreDetailScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final salesman = widget.salesman;
    final store = widget.store;
    final id = salesman['name'] as String;
    final displayName = (salesman['fullName'] as String?) ?? id;
    final owned = store.customers.where((c) => c.assignedSalesmanId == id).toList()..sort((a, b) => b.totalDue.compareTo(a.totalDue));
    final ids = owned.map((c) => c.id).toSet();
    final ownedPtps = store.ptps.where((p) => ids.contains(p.customerId)).toList();
    final breakdown = (salesman['recoveryScoreComponents'] as Map?)?.cast<String, num>() ?? const <String, num>{};

    // --- Portfolio money ---
    final totalOutstanding = owned.fold<double>(0, (s, c) => s + c.totalOutstanding);
    final totalOverdue = owned.fold<double>(0, (s, c) => s + c.totalDue);
    final overdueCustomers = owned.where((c) => c.totalDue > 0).length;
    final aging60 = owned.where((c) => c.oldestOverdueDays >= 60).fold<double>(0, (s, c) => s + c.totalDue);
    final noNextAction = owned.where((c) => !c.hasValidNextAction && c.totalDue > 0).length;

    // --- PTPs ---
    final scheduled = ownedPtps.where((p) => p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification).toList();
    final kept = ownedPtps.where((p) => p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept).toList();
    final broken = ownedPtps.where((p) => p.status == PtpStatus.broken).toList();
    final matured = ownedPtps.where((p) => p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification && p.status != PtpStatus.financialSyncPending).toList();
    final totalReceived = kept.fold<double>(0, (s, p) => s + (p.amountReceived ?? 0));
    final scheduledAmt = scheduled.fold<double>(0, (s, p) => s + p.amountPromised);
    final brokenAmt = broken.fold<double>(0, (s, p) => s + p.amountPromised);
    final brokenRate = matured.isEmpty ? 0.0 : broken.length / matured.length * 100;
    final keptRate = matured.isEmpty ? 0.0 : kept.length / matured.length * 100;

    // --- Score / discipline ---
    final score = salesman['recoveryScore'] as int;
    final band = _performanceBand(score);
    final bandColor = _performanceBandColor(band);
    final target = (salesman['collectionTarget'] as num?)?.toDouble() ?? 0;
    final achieved = (salesman['collectionAchieved'] as num?)?.toDouble() ?? 0;
    final achievedPct = salesman['collectionAchievedPercent'] as int? ?? 0;
    final followUp = _followUpDisciplineFor(salesman);
    final taskDone = salesman['taskCompletionRate'] as int? ?? 0;
    final overdueTasks = salesman['overdueTasks'] as int? ?? 0;
    final validNextRate = salesman['validNextActionRate'] as int? ?? 0;
    final escalatedC = salesman['escalatedCustomers'] as int? ?? 0;
    final highRiskC = salesman['highRiskCustomers'] as int? ?? 0;
    final dueTodayAmt = (salesman['dueTodayPtps'] as num?)?.toDouble() ?? 0;

    final dueTodayCount = scheduled.where((p) => _isSameDay(p.promiseDate, DateTime.now())).length;

    return _ReportScaffold(
      title: displayName,
      subtitle: '${(salesman['branch'] as String?) ?? 'Turning Point'} · Recovery Score $score%',
      children: [
        _hero(displayName, (salesman['branch'] as String?) ?? 'Turning Point', salesman['phone'] as String?, score, band, bandColor),
        const SizedBox(height: 18),

        _sectionTitle('Money at a glance'),
        const SizedBox(height: 10),
        _statGrid([
          (Icons.account_balance_wallet_outlined, kBlue, _rupee.format(totalOutstanding), 'Total Outstanding', '${owned.length} customers'),
          (Icons.currency_rupee, kRed, _rupee.format(totalOverdue), 'Total Overdue', '$overdueCustomers overdue'),
          (Icons.savings_outlined, kGreen, _rupee.format(totalReceived), 'Total Received', '${kept.length} kept'),
          (Icons.handshake_outlined, kPurple, '${ownedPtps.length}', 'Total PTPs', '${_rupee.format(scheduledAmt)} active'),
          (Icons.link_off, kRed, '${broken.length}', 'Broken PTPs', '${brokenRate.toStringAsFixed(0)}% of matured'),
          (Icons.event_available_outlined, kOrange, _rupee.format(dueTodayAmt), 'PTP Due Today', '$dueTodayCount PTPs'),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('How they are performing'),
        const SizedBox(height: 10),
        InfoCard(children: [
          _bar('Collection Achieved', achievedPct.toDouble(), sub: '${_rupee.format(achieved)} of ${_rupee.format(target)}'),
          _bar('PTP Kept Rate', keptRate),
          _bar('Follow-Up Discipline', followUp),
          _bar('Task Completion', taskDone.toDouble()),
          _bar('Valid Next Action', validNextRate.toDouble()),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _flagChip('Overdue Tasks', '$overdueTasks', overdueTasks > 0 ? kRed : kGreen),
            _flagChip('No Next Action', '$noNextAction', noNextAction > 0 ? kOrange : kGreen),
            _flagChip('Escalated', '$escalatedC', escalatedC > 0 ? kOrange : kGreen),
            _flagChip('High Risk', '$highRiskC', highRiskC > 0 ? kRed : kGreen),
            _flagChip('Ageing > 60d', _rupee.format(aging60), aging60 > 0 ? kOrange : kGreen),
            _flagChip('Broken PTP Rate', '${brokenRate.toStringAsFixed(0)}%', brokenRate > 20 ? kRed : (brokenRate > 0 ? kOrange : kGreen)),
          ]),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('PTP outcomes'),
        const SizedBox(height: 10),
        InfoCard(children: [
          _ptpBar(scheduled.length, kept.length, broken.length),
          const SizedBox(height: 14),
          _ptpLegendRow(kBlue, 'Scheduled (Active)', scheduled.length, scheduledAmt),
          _ptpLegendRow(kGreen, 'Kept / Partially Kept', kept.length, totalReceived, suffix: ' received'),
          _ptpLegendRow(kRed, 'Broken', broken.length, brokenAmt),
          _ptpLegendRow(kMuted, 'Matured (has an outcome)', matured.length, null),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('Why this score'),
        const SizedBox(height: 10),
        InfoCard(children: [
          _weightBar('Collection Performance', 40, breakdown['collectionPerformance'] ?? 0, kBlue),
          _weightBar('Follow-Up Discipline', 20, breakdown['followUpDiscipline'] ?? 0, kGreen),
          _weightBar('PTP Discipline & Quality', 15, breakdown['ptpDiscipline'] ?? 0, kPurple),
          _weightBar('Old Outstanding Reduction', 10, breakdown['oldOutstandingReduction'] ?? 0, kOrange),
          _weightBar('No-Follow-Up Control', 10, breakdown['noFollowUpControl'] ?? 0, kRed),
          _weightBar('Process / Evidence Discipline', 5, breakdown['processDiscipline'] ?? 0, kTeal),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          Row(children: [
            const Expanded(child: Text('Weighted Recovery Score', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kNavy))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: bandColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('${breakdown['total'] ?? score}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: bandColor)),
            ),
          ]),
        ]),
        const SizedBox(height: 20),

        Row(children: [
          Expanded(child: _sectionTitle('Portfolio')),
          Text('${owned.length} customers', style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        if (owned.isEmpty)
          const InfoCard(children: [Text('No customers currently mapped to this salesman.', style: TextStyle(fontSize: 11.5, color: kMuted))])
        else ...[
          _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
          Builder(builder: (context) {
            final searched = owned.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();
            if (searched.isEmpty) return _emptyCard('No customers match this search.');
            return Column(children: searched.map((c) => _drillRow(context, c.name, '${c.oldestOverdueDays} days overdue · ${c.primaryNextAction}', _rupee.format(c.totalDue), kRed,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))))).toList());
          }),
        ],
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy));

  Widget _hero(String name, String branch, String? phone, int score, String band, Color bandColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bandColor.withOpacity(0.25)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [bandColor.withOpacity(0.10), bandColor.withOpacity(0.02)]),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 24, backgroundColor: bandColor.withOpacity(0.18), child: Text(initialsFor(name), style: TextStyle(color: bandColor, fontSize: 15, fontWeight: FontWeight.w900))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavy)),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 12, color: kMuted),
                  const SizedBox(width: 3),
                  Flexible(child: Text('$branch Branch', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted))),
                ]),
                if (phone != null && phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: CallablePhoneNumber(phoneNumber: phone, style: const TextStyle(fontSize: 11), iconSize: 12),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bandColor.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
                  child: Text(band.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: bandColor, letterSpacing: 0.4)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            height: 62,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 62,
                height: 62,
                child: CircularProgressIndicator(value: (score / 100).clamp(0.0, 1.0), strokeWidth: 6, backgroundColor: bandColor.withOpacity(0.15), valueColor: AlwaysStoppedAnimation(bandColor)),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$score', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: bandColor, height: 1)),
                const Text('SCORE', style: TextStyle(fontSize: 6.5, fontWeight: FontWeight.bold, color: kMuted, letterSpacing: 0.5)),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _statGrid(List<(IconData, Color, String, String, String)> cards) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards.map((c) {
        final (icon, color, value, label, sub) = c;
        return SizedBox(
          width: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: kBorder)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 4, color: color),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 10, 10, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 13, color: color)),
                        const SizedBox(height: 8),
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color))),
                        const SizedBox(height: 2),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  static Color _rateColor(double pct) => pct >= 75 ? kGreen : (pct >= 45 ? kOrange : kRed);

  Widget _bar(String label, double pct, {String? sub}) {
    final v = pct.clamp(0, 100).toDouble();
    final c = _rateColor(v);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark, fontWeight: FontWeight.w600))),
            Text('${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: v / 100, minHeight: 7, backgroundColor: kBg, valueColor: AlwaysStoppedAnimation(c))),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub, style: const TextStyle(fontSize: 9.5, color: kMuted))),
        ],
      ),
    );
  }

  Widget _flagChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color)),
      ]),
    );
  }

  Widget _ptpBar(int sched, int kept, int broken) {
    final total = sched + kept + broken;
    if (total == 0) {
      return Container(
        height: 14,
        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        child: const Text('No PTPs yet', style: TextStyle(fontSize: 9, color: kMuted)),
      );
    }
    Widget seg(int n, Color c) => n == 0 ? const SizedBox.shrink() : Expanded(flex: n, child: Container(color: c));
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(height: 14, child: Row(children: [seg(sched, kBlue), seg(kept, kGreen), seg(broken, kRed)])),
    );
  }

  Widget _ptpLegendRow(Color color, String label, int count, double? amount, {String suffix = ''}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark))),
        Text(amount == null ? '$count' : '$count  ·  ${_rupee.format(amount)}$suffix', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark)),
      ]),
    );
  }

  Widget _weightBar(String label, int weight, num pct, Color color) {
    final v = pct.toDouble().clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: RichText(
            text: TextSpan(style: const TextStyle(fontSize: 11.5, color: kDark), children: [
              TextSpan(text: label),
              TextSpan(text: '  $weight%', style: const TextStyle(fontSize: 9.5, color: kMuted)),
            ]),
          ),
        ),
        Expanded(
          flex: 4,
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: v / 100, minHeight: 6, backgroundColor: kBg, valueColor: AlwaysStoppedAnimation(color))),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 34, child: Text('${v.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// 3) PTP Report
// ---------------------------------------------------------------------
bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _ptpBand(double keptPct) {
  if (keptPct >= 80) return 'Excellent';
  if (keptPct >= 65) return 'Good';
  if (keptPct >= 50) return 'Average';
  if (keptPct >= 30) return 'At Risk';
  return 'Critical';
}

Color _ptpBandColor(String band) {
  switch (band) {
    case 'Excellent':
      return kGreen;
    case 'Good':
      return kBlue;
    case 'Average':
      return kOrange;
    case 'At Risk':
      return const Color(0xFFEA580C);
    default:
      return kRed;
  }
}

class PtpReport extends StatefulWidget {
  final ReportFilters filters;
  const PtpReport({super.key, required this.filters});

  @override
  State<PtpReport> createState() => _PtpReportState();
}

class _PtpReportState extends State<PtpReport> {
  String _query = '';
  late String _dateRange = widget.filters.dateRange;
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(dateRange: _dateRange, branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final customerById = {for (final c in store.customers) c.id: c};
    final ptps = store.ptps.where((p) {
      final c = customerById[p.customerId];
      return c != null && filters.matchesCustomer(c) && filters.matchesDate(p.promiseDate);
    }).toList();

    final buckets = <String, List<PromiseToPay>>{
      'Kept': ptps.where((p) => p.status == PtpStatus.kept).toList(),
      'Partially Kept': ptps.where((p) => p.status == PtpStatus.partiallyKept).toList(),
      // A PTP due today flips scheduled -> pendingVerification at the very
      // midnight sync that starts that day, so both count as "Due Today".
      // pendingVerification normally clears within its 1-day grace window,
      // but if the verification job stalls (e.g. BUSY source unreachable)
      // it can sit past its promise date — still shown here rather than
      // vanishing from every bucket while it waits.
      'Due Today': ptps.where((p) => p.status == PtpStatus.pendingVerification || (p.status == PtpStatus.scheduled && _isSameDay(p.promiseDate, now))).toList(),
      'Upcoming': ptps.where((p) => p.status == PtpStatus.scheduled && p.promiseDate.isAfter(now) && !_isSameDay(p.promiseDate, now)).toList(),
      'Broken': ptps.where((p) => p.status == PtpStatus.broken).toList(),
      'Financial Sync Pending': ptps.where((p) => p.status == PtpStatus.financialSyncPending).toList(),
    };
    final bucketColors = {'Kept': kGreen, 'Partially Kept': const Color(0xFF0891B2), 'Due Today': kOrange, 'Upcoming': kBlue, 'Broken': kRed, 'Financial Sync Pending': kPurple};

    final totalAmount = ptps.fold(0.0, (s, p) => s + p.amountPromised);
    final dueTodayItems = buckets['Due Today']!;
    final dueTodayAmount = dueTodayItems.fold(0.0, (s, p) => s + p.amountPromised);
    final dueTodayAccounts = dueTodayItems.map((p) => p.customerId).toSet().length;
    final matured = ptps.where((p) => p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification && p.status != PtpStatus.financialSyncPending).toList();
    final keptCount = buckets['Kept']!.length;
    final brokenCount = buckets['Broken']!.length;
    final keptRate = matured.isEmpty ? 0.0 : keptCount / matured.length * 100;
    final brokenRate = matured.isEmpty ? 0.0 : brokenCount / matured.length * 100;

    final trend = store.ptpAmountTrend;

    // Per-salesman summary
    final salesmen = store.salesmen.where((s) =>
        (filters.branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == filters.branch) &&
        (filters.salesman == 'All Salesmen' || s['name'] == filters.salesman)).toList();
    final rows = salesmen.map((s) {
      final name = s['name'] as String;
      final displayName = (s['fullName'] as String?) ?? name;
      final ids = store.customers.where((c) => c.assignedSalesmanId == name).map((c) => c.id).toSet();
      final mine = ptps.where((p) => ids.contains(p.customerId)).toList();
      final active = mine.where((p) => p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification).fold(0.0, (a, p) => a + p.amountPromised);
      final dueToday = mine.where((p) => p.status == PtpStatus.pendingVerification || (p.status == PtpStatus.scheduled && _isSameDay(p.promiseDate, now))).fold(0.0, (a, p) => a + p.amountPromised);
      final mineMatured = mine.where((p) => p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification && p.status != PtpStatus.financialSyncPending).toList();
      final mineKept = mineMatured.where((p) => p.status == PtpStatus.kept).length;
      final mineBroken = mineMatured.where((p) => p.status == PtpStatus.broken).length;
      final keptPct = mineMatured.isEmpty ? 0.0 : mineKept / mineMatured.length * 100;
      final brokenPct = mineMatured.isEmpty ? 0.0 : mineBroken / mineMatured.length * 100;
      return {'name': displayName, 'branch': s['branch'], 'active': active, 'dueToday': dueToday, 'keptPct': keptPct, 'brokenPct': brokenPct};
    }).toList()
      ..sort((a, b) => ((b['keptPct'] as num).toDouble()).compareTo((a['keptPct'] as num).toDouble()));
    final rowsSearched = rows.where((r) => (r['name'] as String).toLowerCase().contains(_query.toLowerCase())).toList();

    return _ReportScaffold(
      title: 'PTP Report',
      subtitle: 'Track promise-to-pay commitments, due follow-ups and reliability',
      children: [
        _ReportFilterBar(
          showDateRange: true,
          dateRange: _dateRange,
          onDateRangeChanged: (v) => setState(() => _dateRange = v),
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.groups_outlined, kPurple, '${ptps.length}', 'Total PTPs'),
            _statTile(Icons.currency_rupee, kBlue, _rupee.format(totalAmount), 'PTP Amount'),
            _statTile(Icons.event_outlined, kOrange, _rupee.format(dueTodayAmount), 'PTP Due Today'),
            _statTile(Icons.shield_outlined, kGreen, '${keptRate.toStringAsFixed(1)}%', 'Kept PTP Rate'),
            _statTile(Icons.shield_outlined, kRed, '${brokenRate.toStringAsFixed(1)}%', 'Broken PTP Rate'),
            _statTile(Icons.notifications_active_outlined, kOrange, '$dueTodayAccounts', 'Due Today Accounts'),
          ],
        ),
        const SizedBox(height: 20),
        const Text('PTP Trend (Last 6 Months)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, m) => Text(_shortRupee(v), style: const TextStyle(fontSize: 9, color: kMuted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= trend.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'], style: const TextStyle(fontSize: 9, color: kMuted)));
                  })),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['amount'] as num).toDouble())],
                    isCurved: true,
                    color: kBlue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: kBlue.withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('PTP Status Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.length.toDouble(), color: bucketColors[e.key], radius: 26, showTitle: false)).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: buckets.entries.map((e) {
                    final pct = ptps.isEmpty ? 0.0 : e.value.length / ptps.length * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: bucketColors[e.key], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                          Text('${e.value.length} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 10, color: kMuted)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(child: Text('${ptps.length} Total PTPs', style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 20),
        Row(
          children: buckets.entries.map((e) {
            final total = e.value.fold(0.0, (s, p) => s + p.amountPromised);
            return Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PtpBucketListScreen(title: e.key, ptps: e.value, store: store))),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${e.key.split(' ').first}\n${_rupee.format(total)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: bucketColors[e.key])),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Salesman PTP Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search salesman by name...', onChanged: (v) => setState(() => _query = v)),
        _scrollableBlock(rowsSearched.isEmpty ? [_emptyText('No salesmen match this search.')] : rowsSearched.map((r) {
          final name = r['name'] as String;
          final keptPct = (r['keptPct'] as num).toDouble();
          final band = _ptpBand(keptPct);
          final bandColor = _ptpBandColor(band);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: InfoCard(children: [
              Row(children: [
                CircleAvatar(radius: 16, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kDark)),
                      Text(((r['branch'] as String?) ?? 'Turning Point'), style: const TextStyle(fontSize: 10, color: kMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: bandColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(band, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: bandColor)),
                ),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
              KeyValueRow('Active PTP', _rupee.format(r['active'])),
              KeyValueRow('Due Today', _rupee.format(r['dueToday'])),
              KeyValueRow('Kept %', '${keptPct.toStringAsFixed(1)}%', valueColor: kGreen),
              KeyValueRow('Broken %', '${((r['brokenPct'] as num).toDouble()).toStringAsFixed(1)}%', valueColor: kRed),
            ]),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Top 5 PTP Performers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: rows.isEmpty ? [_emptyText('No PTP data matches this filter.')] : rows.take(5).toList().asMap().entries.map((e) {
          final medal = ['🥇', '🥈', '🥉', '4', '5'][e.key];
          final r = e.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text(medal, style: const TextStyle(fontSize: 14))),
                const SizedBox(width: 8),
                Expanded(child: Text(r['name'] as String, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark))),
                Text('${((r['keptPct'] as num).toDouble()).toStringAsFixed(1)}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _ptpBandColor(_ptpBand((r['keptPct'] as num).toDouble())))),
              ],
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('PTP Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          _ptpLegendRow('Excellent', '80% and above'),
          _ptpLegendRow('Good', '65% – 79%'),
          _ptpLegendRow('Average', '50% – 64%'),
          _ptpLegendRow('At Risk', '30% – 49%'),
          _ptpLegendRow('Critical', 'Below 30%'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDBA74))),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 15, color: Color(0xFFC2410C)),
            SizedBox(width: 8),
            Expanded(child: Text('PTP figures are based on the latest reconciled commitments and outcomes.', style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 160,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
          ],
        ),
      ),
    );
  }

  Widget _ptpLegendRow(String label, String range) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: _ptpBandColor(label), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark, fontWeight: FontWeight.w600))),
          Text(range, style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
      ),
    );
  }
}

String _shortRupee(double v) {
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(0)}L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}K';
  return '₹${v.toStringAsFixed(0)}';
}

class _PtpBucketListScreen extends StatefulWidget {
  final String title;
  final List<PromiseToPay> ptps;
  final AppStore store;
  const _PtpBucketListScreen({required this.title, required this.ptps, required this.store});

  @override
  State<_PtpBucketListScreen> createState() => _PtpBucketListScreenState();
}

class _PtpBucketListScreenState extends State<_PtpBucketListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customerById = {for (final c in widget.store.customers) c.id: c};
    final rows = widget.ptps.where((p) => customerById.containsKey(p.customerId)).toList();
    final searched = rows.where((p) => customerById[p.customerId]!.name.toLowerCase().contains(_query.toLowerCase())).toList();
    return _ReportScaffold(
      title: widget.title,
      subtitle: '${widget.ptps.length} PTPs',
      children: [
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
        if (searched.isEmpty) _emptyCard('No PTPs match this search.'),
        ...searched.map((p) {
          final c = customerById[p.customerId]!;
          return _drillRow(context, c.name, DateFormat('dd MMM yyyy').format(p.promiseDate), _rupee.format(p.amountPromised), kDark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))));
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 4) Broken PTP Report
// ---------------------------------------------------------------------
String _brokenBand(double pct) {
  if (pct < 10) return 'Good';
  if (pct < 18) return 'Average';
  if (pct < 24) return 'At Risk';
  return 'Critical';
}

Color _brokenBandColor(String band) {
  switch (band) {
    case 'Good':
      return kGreen;
    case 'Average':
      return kOrange;
    case 'At Risk':
      return const Color(0xFFEA580C);
    default:
      return kRed;
  }
}

/// Which bucket a customer with at least one broken PTP falls into —
/// mutually exclusive, driven entirely by real customer state.
String _brokenCustomerBucket(Customer c) {
  if (c.escalationLevel == 'L4') return 'Management Attention';
  if (c.currentRecoveryState == 'RE Control') return 'Under RE Control';
  if (c.escalationLevel == 'L3') return 'Third+ Broken';
  if (c.escalationLevel == 'L2') return 'Second Broken';
  return 'First Broken';
}

class BrokenPtpReport extends StatefulWidget {
  final ReportFilters filters;
  const BrokenPtpReport({super.key, required this.filters});

  @override
  State<BrokenPtpReport> createState() => _BrokenPtpReportState();
}

class _BrokenPtpReportState extends State<BrokenPtpReport> {
  String _query = '';
  late String _dateRange = widget.filters.dateRange;
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(dateRange: _dateRange, branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final customerById = {for (final c in store.customers) c.id: c};
    final items = store.brokenPtps.where((p) {
      final c = customerById[p.customerId];
      return c != null && filters.matchesCustomer(c) && filters.matchesDate(p.promiseDate);
    }).toList();

    final totalAmount = items.fold(0.0, (s, p) => s + p.amountPromised);
    final brokenToday = items.where((p) => _isSameDay(p.promiseDate, now)).fold(0.0, (s, p) => s + p.amountPromised);

    // Repeat offenders: customers with 2+ broken PTPs in this filtered set.
    final byCustomer = <String, List<PromiseToPay>>{};
    for (final p in items) {
      byCustomer.putIfAbsent(p.customerId, () => []).add(p);
    }
    final repeatBrokenAccounts = byCustomer.values.where((l) => l.length >= 2).length;

    final brokenCustomers = byCustomer.keys.map((id) => customerById[id]).whereType<Customer>().toList();
    final reControlCount = brokenCustomers.where((c) => c.currentRecoveryState == 'RE Control' && c.escalationLevel != 'L4').length;
    final managementAttentionCount = brokenCustomers.where((c) => c.escalationLevel == 'L4').length;

    final buckets = <String, List<Customer>>{
      'First Broken': [],
      'Second Broken': [],
      'Third+ Broken': [],
      'Under RE Control': [],
      'Management Attention': [],
    };
    for (final c in brokenCustomers) {
      buckets[_brokenCustomerBucket(c)]!.add(c);
    }
    final bucketColors = {'First Broken': kBlue, 'Second Broken': kOrange, 'Third+ Broken': kGreen, 'Under RE Control': kPurple, 'Management Attention': kRed};

    final trend = store.brokenPtpCountTrend;

    // Per-salesman summary
    final salesmen = store.salesmen.where((s) =>
        (filters.branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == filters.branch) &&
        (filters.salesman == 'All Salesmen' || s['name'] == filters.salesman)).toList();
    final rows = salesmen.map((s) {
      final name = s['name'] as String;
      final displayName = (s['fullName'] as String?) ?? name;
      final ids = store.customers.where((c) => c.assignedSalesmanId == name).map((c) => c.id).toSet();
      final mineBroken = items.where((p) => ids.contains(p.customerId)).toList();
      // Matured denominator scoped to the same date filter as `items`
      // (mineBroken) — otherwise a date-filtered numerator over a lifetime
      // denominator produces a percentage that doesn't match the selected range.
      final mineMatured = store.ptps
          .where((p) =>
              ids.contains(p.customerId) &&
              p.status != PtpStatus.scheduled &&
              p.status != PtpStatus.pendingVerification &&
              p.status != PtpStatus.financialSyncPending &&
              filters.matchesDate(p.promiseDate))
          .toList();
      final brokenAmount = mineBroken.fold(0.0, (a, p) => a + p.amountPromised);
      final brokenPct = mineMatured.isEmpty ? 0.0 : mineBroken.length / mineMatured.length * 100;
      return {'name': displayName, 'branch': s['branch'], 'brokenAmount': brokenAmount, 'brokenPct': brokenPct};
    }).toList()
      ..sort((a, b) => ((b['brokenAmount'] as num).toDouble()).compareTo((a['brokenAmount'] as num).toDouble()));
    final rowsSearched = rows.where((r) => (r['name'] as String).toLowerCase().contains(_query.toLowerCase())).toList();

    return _ReportScaffold(
      title: 'Broken PTP Report',
      subtitle: 'Track broken commitments, high-risk follow-ups and escalation exposure',
      children: [
        _ReportFilterBar(
          showDateRange: true,
          dateRange: _dateRange,
          onDateRangeChanged: (v) => setState(() => _dateRange = v),
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.link_off, kRed, '${items.length}', 'Total Broken PTPs'),
            _statTile(Icons.currency_rupee, kBlue, _rupee.format(totalAmount), 'Broken PTP Amount'),
            _statTile(Icons.event_outlined, kOrange, _rupee.format(brokenToday), 'Broken Today'),
            _statTile(Icons.replay, kRed, '$repeatBrokenAccounts', 'Repeat Broken Accounts'),
            _statTile(Icons.person_outline, kBlue, '$reControlCount', 'Recovery Executive Control'),
            _statTile(Icons.warning_amber_rounded, kRed, '$managementAttentionCount', 'Management Attention'),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Broken PTP Trend (Last 6 Months)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text('${v.toInt()}', style: const TextStyle(fontSize: 9, color: kMuted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= trend.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'], style: const TextStyle(fontSize: 9, color: kMuted)));
                  })),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['count'] as num).toDouble())],
                    isCurved: true,
                    color: kRed,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: kRed.withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Broken PTP Status Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.length.toDouble(), color: bucketColors[e.key], radius: 26, showTitle: false)).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: buckets.entries.map((e) {
                    final pct = brokenCustomers.isEmpty ? 0.0 : e.value.length / brokenCustomers.length * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: bucketColors[e.key], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                          Text('${e.value.length} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 10, color: kMuted)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(child: Text('${brokenCustomers.length} Broken PTP Customers', style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 20),
        Row(
          children: buckets.entries.map((e) {
            return Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _BrokenCustomerBucketScreen(title: e.key, customers: e.value))),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${e.key.split(' ').first}\n${e.value.length}', textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: bucketColors[e.key])),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Salesman Broken PTP Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search salesman by name...', onChanged: (v) => setState(() => _query = v)),
        _scrollableBlock(rowsSearched.isEmpty ? [_emptyText('No salesmen match this search.')] : rowsSearched.map((r) {
          final name = r['name'] as String;
          final brokenPct = (r['brokenPct'] as num).toDouble();
          final band = _brokenBand(brokenPct);
          final bandColor = _brokenBandColor(band);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: InfoCard(children: [
              Row(children: [
                CircleAvatar(radius: 16, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kDark)),
                      Text(((r['branch'] as String?) ?? 'Turning Point'), style: const TextStyle(fontSize: 10, color: kMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: bandColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(band, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: bandColor)),
                ),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
              KeyValueRow('Broken Amount', _rupee.format(r['brokenAmount']), valueColor: kRed),
              KeyValueRow('Broken %', '${brokenPct.toStringAsFixed(1)}%', valueColor: bandColor),
            ]),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Top 5 Broken Exposure', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: rows.isEmpty ? [_emptyText('No broken PTP data matches this filter.')] : rows.take(5).toList().asMap().entries.map((e) {
          final medal = ['🥇', '🥈', '🥉', '4', '5'][e.key];
          final r = e.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text(medal, style: const TextStyle(fontSize: 14))),
                const SizedBox(width: 8),
                Expanded(child: Text(r['name'] as String, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark))),
                Text(_rupee.format(r['brokenAmount']), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kRed)),
              ],
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Broken PTP Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          _brokenLegendRow('Good', 'below 10%'),
          _brokenLegendRow('Average', '10% – 17%'),
          _brokenLegendRow('At Risk', '18% – 24%'),
          _brokenLegendRow('Critical', 'above 24%'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDBA74))),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 15, color: Color(0xFFC2410C)),
            SizedBox(width: 8),
            Expanded(child: Text('Broken PTP figures are based on the latest reconciled commitments and outcome history.', style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 160,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
          ],
        ),
      ),
    );
  }

  Widget _brokenLegendRow(String label, String range) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: _brokenBandColor(label), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark, fontWeight: FontWeight.w600))),
          Text(range, style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
      ),
    );
  }
}

class _BrokenCustomerBucketScreen extends StatefulWidget {
  final String title;
  final List<Customer> customers;
  const _BrokenCustomerBucketScreen({required this.title, required this.customers});

  @override
  State<_BrokenCustomerBucketScreen> createState() => _BrokenCustomerBucketScreenState();
}

class _BrokenCustomerBucketScreenState extends State<_BrokenCustomerBucketScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final searched = widget.customers.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();
    return _ReportScaffold(
      title: widget.title,
      subtitle: '${widget.customers.length} customers',
      children: [
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
        if (searched.isEmpty) _emptyCard('No customers match this search.'),
        ...searched.map((c) => _drillRow(context, c.name, '${context.read<AppStore>().salesmanDisplayName(c.assignedSalesmanId)} · ${c.branch}', _rupee.format(c.totalDue), kRed, () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))))),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 5) Dispute Status Report
// ---------------------------------------------------------------------
String _disputeBucket(String status) {
  switch (status) {
    case 'Pending Approval':
      return 'Awaiting Review';
    case 'Approved':
    case 'In Resolution':
    case 'Awaiting Verification':
    case 'Need More Information':
      return 'In Progress';
    case 'Resolved':
      return 'Resolved';
    case 'Rejected':
    case 'Returned to Recovery':
      return 'Rejected';
    default:
      return 'Awaiting Review';
  }
}

Color _disputeBucketColor(String bucket) {
  switch (bucket) {
    case 'Awaiting Review':
      return kOrange;
    case 'In Progress':
      return kPurple;
    case 'Resolved':
      return kGreen;
    default:
      return kRed;
  }
}

IconData _disputeReasonIcon(String category) {
  switch (category) {
    case 'Goods Issue':
      return Icons.warning_amber_rounded;
    case 'Short Delivery':
      return Icons.inventory_2_outlined;
    case 'Rate Discrepancy':
      return Icons.currency_rupee;
    case 'Freight Charge':
      return Icons.local_shipping_outlined;
    case 'Invoice Issue':
      return Icons.receipt_long_outlined;
    default:
      return Icons.more_horiz;
  }
}

/// Classifies a dispute's free-text reason into a display category — a real
/// derivation from the actual reason string, not an invented label.
String _disputeReasonCategory(String reason) {
  final r = reason.toLowerCase();
  if (r.contains('wrong') || r.contains('damage')) return 'Goods Issue';
  if (r.contains('quantity') || r.contains('shortage') || r.contains('short delivery')) return 'Short Delivery';
  if (r.contains('rate') || r.contains('discrepancy')) return 'Rate Discrepancy';
  if (r.contains('freight')) return 'Freight Charge';
  if (r.contains('invoice') || r.contains('credit') || r.contains('reflected')) return 'Invoice Issue';
  return 'Others';
}

class DisputeStatusReport extends StatefulWidget {
  final ReportFilters filters;
  const DisputeStatusReport({super.key, required this.filters});

  @override
  State<DisputeStatusReport> createState() => _DisputeStatusReportState();
}

class _DisputeStatusReportState extends State<DisputeStatusReport> {
  String _query = '';
  late String _dateRange = widget.filters.dateRange;
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(dateRange: _dateRange, branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    // Match by customerCode (the real customerId — see
    // AppStore._refreshDisputesFromApi) rather than display name: names
    // aren't guaranteed unique, and a dispute whose customer lookup failed
    // during loading has `customer` set to the raw id, which would never
    // match any customer's name anyway.
    final customerById = {for (final c in store.customers) c.id: c};
    final disputes = store.disputes.where((d) {
      final c = customerById[d['customerCode']];
      return c != null && filters.matchesCustomer(c) && filters.matchesDate(d['raisedDate']);
    }).toList()
      ..sort((a, b) => (b['raisedDate'] as DateTime).compareTo(a['raisedDate'] as DateTime));

    final buckets = <String, List<Map<String, dynamic>>>{
      'Awaiting Review': disputes.where((d) => _disputeBucket(d['status']) == 'Awaiting Review').toList(),
      'In Progress': disputes.where((d) => _disputeBucket(d['status']) == 'In Progress').toList(),
      'Resolved': disputes.where((d) => _disputeBucket(d['status']) == 'Resolved').toList(),
      'Rejected': disputes.where((d) => _disputeBucket(d['status']) == 'Rejected').toList(),
    };
    final totalAmount = disputes.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));

    // Reasons — grouped by a real classification of each dispute's own text.
    final byReason = <String, List<Map<String, dynamic>>>{};
    for (final d in disputes) {
      byReason.putIfAbsent(_disputeReasonCategory(d['reason']), () => []).add(d);
    }
    final reasonEntries = byReason.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));

    // Aging buckets — real, from each dispute's actual raisedDate.
    final agingBuckets = <String, List<Map<String, dynamic>>>{'0-7 Days': [], '8-15 Days': [], '16-30 Days': [], '31-60 Days': [], '60+ Days': []};
    for (final d in disputes) {
      final days = now.difference(d['raisedDate'] as DateTime).inDays;
      if (days <= 7) {
        agingBuckets['0-7 Days']!.add(d);
      } else if (days <= 15) {
        agingBuckets['8-15 Days']!.add(d);
      } else if (days <= 30) {
        agingBuckets['16-30 Days']!.add(d);
      } else if (days <= 60) {
        agingBuckets['31-60 Days']!.add(d);
      } else {
        agingBuckets['60+ Days']!.add(d);
      }
    }
    final agingColors = {'0-7 Days': kGreen, '8-15 Days': kBlue, '16-30 Days': kOrange, '31-60 Days': kPurple, '60+ Days': kRed};

    return _ReportScaffold(
      title: 'Dispute Status Report',
      subtitle: 'Overview of dispute status and resolution',
      children: [
        _ReportFilterBar(
          showDateRange: true,
          dateRange: _dateRange,
          onDateRangeChanged: (v) => setState(() => _dateRange = v),
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.description_outlined, kBlue, '${disputes.length}', 'Total Disputes', _rupee.format(totalAmount)),
            ...buckets.entries.map((e) {
              final total = e.value.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
              return _statTile(
                e.key == 'Awaiting Review' ? Icons.hourglass_empty : (e.key == 'In Progress' ? Icons.sync : (e.key == 'Resolved' ? Icons.check_circle_outline : Icons.cancel_outlined)),
                _disputeBucketColor(e.key),
                '${e.value.length}',
                e.key,
                _rupee.format(total),
              );
            }),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Disputes by Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.length.toDouble(), color: _disputeBucketColor(e.key), radius: 26, showTitle: false)).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: buckets.entries.map((e) {
                    final pct = disputes.isEmpty ? 0.0 : e.value.length / disputes.length * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: _disputeBucketColor(e.key), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                          Text('${e.value.length} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 10, color: kMuted)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(child: Text('${disputes.length} Total', style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 10),
        Row(
          children: buckets.entries.map((e) {
            return Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _DisputeBucketListScreen(title: e.key, disputes: e.value, store: store))),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${e.key}\n(${e.value.length})', textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: _disputeBucketColor(e.key))),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Disputes by Reason', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: reasonEntries.map((e) {
          final total = e.value.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kIndigo.withOpacity(0.1), shape: BoxShape.circle), child: Icon(_disputeReasonIcon(e.key), size: 15, color: kIndigo)),
                const SizedBox(width: 10),
                Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kDark))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${e.value.length}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
                    Text(_rupee.format(total), style: const TextStyle(fontSize: 10, color: kMuted)),
                  ],
                ),
              ],
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Disputes Aging', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: agingBuckets.entries.map((e) {
            final total = e.value.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
            final color = agingColors[e.key]!;
            return SizedBox(
              width: 100,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                child: Column(
                  children: [
                    Text(e.key, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('${e.value.length}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
                    const SizedBox(height: 2),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(total), style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Dispute Status Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
        Builder(builder: (context) {
          final searched = disputes.where((d) => (d['customer'] as String).toLowerCase().contains(_query.toLowerCase())).toList();
          if (searched.isEmpty) return _emptyCard('No disputes match this filter.');
          return Column(children: searched.map((d) {
          final bucket = _disputeBucket(d['status']);
          final color = _disputeBucketColor(bucket);
          final c = customerById[d['customerCode']]!;
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 16, backgroundColor: avatarColorFor(d['customer']).withOpacity(0.15), child: Text(initialsFor(d['customer']), style: TextStyle(color: avatarColorFor(d['customer']), fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['customer'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                        Text('${d['invoice']} · ${c.branch} Branch', style: const TextStyle(fontSize: 10, color: kMuted)),
                        const SizedBox(height: 4),
                        Text(d['reason'], style: const TextStyle(fontSize: 10.5, color: kMuted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_rupee.format(d['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                        child: Text(bucket.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                      ),
                      const SizedBox(height: 4),
                      Text(DateFormat('dd MMM yyyy, hh:mm a').format(d['raisedDate']), style: const TextStyle(fontSize: 9, color: kMuted)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList());
        }),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label, String sub) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(sub, style: const TextStyle(fontSize: 9.5, color: kMuted))),
          ],
        ),
      ),
    );
  }
}

class _DisputeBucketListScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> disputes;
  final AppStore store;
  const _DisputeBucketListScreen({required this.title, required this.disputes, required this.store});

  @override
  State<_DisputeBucketListScreen> createState() => _DisputeBucketListScreenState();
}

class _DisputeBucketListScreenState extends State<_DisputeBucketListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customerById = {for (final c in widget.store.customers) c.id: c};
    final rows = widget.disputes.where((d) => customerById.containsKey(d['customerCode'])).toList();
    final searched = rows.where((d) => (d['customer'] as String).toLowerCase().contains(_query.toLowerCase())).toList();
    return _ReportScaffold(
      title: '${widget.title} Disputes',
      subtitle: '${widget.disputes.length} disputes',
      children: [
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
        if (searched.isEmpty) _emptyCard('No disputes match this search.'),
        ...searched.map((d) {
          final c = customerById[d['customerCode']]!;
          return _drillRow(context, d['customer'], d['reason'], _rupee.format(d['amount']), kIndigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))));
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 6) Ageing Receivables Report
// ---------------------------------------------------------------------
/// One customer's real BUSY-sourced ageing exposure in a single bucket
/// (futureDue / age0_30 / age31_60 / age61_90 / age90Plus — the same figures
/// the daily sync writes onto the customer row). NOT reconstructed from
/// `c.invoices`: the bulk customer list (`GET /api/customers`, what every
/// report reads via `store.customers`) never populates `invoices` — that
/// field is only ever filled in by the single-customer detail fetch — so
/// building rows from it here always fell through to one synthetic
/// aggregate row per customer dated by `oldestOverdueDays`, which dumped a
/// customer's entire balance into a single bucket and left every other
/// bucket blind to money they actually owe there.
class _AgeingRow {
  final Customer customer;
  final String bucket;
  final double amount;
  _AgeingRow({required this.customer, required this.bucket, required this.amount});
}

class AgeingReceivablesReport extends StatefulWidget {
  final ReportFilters filters;
  const AgeingReceivablesReport({super.key, required this.filters});

  @override
  State<AgeingReceivablesReport> createState() => _AgeingReceivablesReportState();
}

class _AgeingReceivablesReportState extends State<AgeingReceivablesReport> {
  String _query = '';
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  List<_AgeingRow> _rowsFor(Customer c) {
    final rows = <_AgeingRow>[];
    void add(String bucket, double amount) {
      if (amount > 0) rows.add(_AgeingRow(customer: c, bucket: bucket, amount: amount));
    }

    add('Not Due', c.futureDue);
    add('0 - 30 Days', c.age0_30);
    add('31 - 60 Days', c.age31_60);
    add('61 - 90 Days', c.age61_90);
    add('90+ Days', c.age90Plus);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final customers = store.customers.where(filters.matchesCustomer).toList();

    final allRows = <_AgeingRow>[];
    for (final c in customers) {
      allRows.addAll(_rowsFor(c));
    }
    allRows.sort((a, b) => b.amount.compareTo(a.amount));

    final buckets = <String, List<_AgeingRow>>{'Not Due': [], '0 - 30 Days': [], '31 - 60 Days': [], '61 - 90 Days': [], '90+ Days': []};
    for (final r in allRows) {
      buckets[r.bucket]!.add(r);
    }
    final bucketColors = {'Not Due': kGreen, '0 - 30 Days': kOrange, '31 - 60 Days': kRed, '61 - 90 Days': kPurple, '90+ Days': const Color(0xFF991B1B)};
    final totalOutstanding = allRows.fold(0.0, (s, r) => s + r.amount);
    final customersWithDue = customers.where((c) => c.totalDue > 0).length;

    return _ReportScaffold(
      title: 'Ageing Receivables Report',
      subtitle: 'Outstanding analysis by real BUSY ageing bucket',
      children: [
        _ReportFilterBar(
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.currency_rupee, kBlue, _rupee.format(totalOutstanding), 'Total Outstanding', 'From $customersWithDue Customers'),
            ...buckets.entries.map((e) {
              final total = e.value.fold(0.0, (s, r) => s + r.amount);
              final pct = totalOutstanding == 0 ? 0.0 : total / totalOutstanding * 100;
              return _statTile(
                e.key == 'Not Due' ? Icons.check_circle_outline : Icons.hourglass_bottom,
                bucketColors[e.key]!,
                _rupee.format(total),
                e.key,
                '${pct.toStringAsFixed(2)}% of Total',
              );
            }),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Ageing Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.fold<double>(0.0, (s, r) => s + r.amount), color: bucketColors[e.key]!, radius: 26, showTitle: false)).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: buckets.entries.map((e) {
                    final total = e.value.fold(0.0, (s, r) => s + r.amount);
                    final pct = totalOutstanding == 0 ? 0.0 : total / totalOutstanding * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: bucketColors[e.key], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                          Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10, color: kMuted)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: kBorder)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
            Text(_rupee.format(totalOutstanding), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
          ]),
        ]),
        const SizedBox(height: 20),
        Text('Ageing Receivables Details · ${allRows.length} Records', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
        Builder(builder: (context) {
          final searched = allRows.where((r) => r.customer.name.toLowerCase().contains(_query.toLowerCase())).toList();
          if (searched.isEmpty) return _emptyCard('No ageing receivables match this filter.');
          return Column(children: searched.map((r) {
          final bucket = r.bucket;
          final color = bucketColors[bucket]!;
          final isNotDue = bucket == 'Not Due';
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: r.customer))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 16, backgroundColor: avatarColorFor(r.customer.name).withOpacity(0.15), child: Text(initialsFor(r.customer.name), style: TextStyle(color: avatarColorFor(r.customer.name), fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                        Text('${r.customer.branch} Branch', style: const TextStyle(fontSize: 10, color: kMuted)),
                        Text(
                          isNotDue ? 'Not yet due' : 'Oldest overdue ${r.customer.oldestOverdueDays} days',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: isNotDue ? kGreen : kRed),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_rupee.format(r.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                        child: Text(bucket, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList());
        }),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('As on ${DateFormat('dd MMM yyyy').format(now)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label, String sub) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
            Text(sub, style: const TextStyle(fontSize: 9, color: kMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 7) Expected vs Actual Collection
// ---------------------------------------------------------------------
String _efficiencyBand(double pct) {
  if (pct >= 85) return 'Excellent';
  if (pct >= 70) return 'Good';
  if (pct >= 50) return 'Average';
  if (pct >= 30) return 'Below Average';
  return 'Poor';
}

Color _efficiencyBandColor(String band) {
  switch (band) {
    case 'Excellent':
      return kGreen;
    case 'Good':
      return kBlue;
    case 'Average':
      return kOrange;
    case 'Below Average':
      return const Color(0xFFEA580C);
    default:
      return kRed;
  }
}

class ExpectedVsActualCollectionReport extends StatefulWidget {
  final ReportFilters filters;
  const ExpectedVsActualCollectionReport({super.key, required this.filters});

  @override
  State<ExpectedVsActualCollectionReport> createState() => _ExpectedVsActualCollectionReportState();
}

class _ExpectedVsActualCollectionReportState extends State<ExpectedVsActualCollectionReport> {
  String _salesmanQuery = '';
  String _customerQuery = '';
  late String _dateRange = widget.filters.dateRange;
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(dateRange: _dateRange, branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final customerById = {for (final c in store.customers) c.id: c};
    final matured = store.ptps.where((p) {
      final c = customerById[p.customerId];
      return c != null && filters.matchesCustomer(c) && filters.matchesDate(p.promiseDate) && p.status != PtpStatus.scheduled && p.status != PtpStatus.pendingVerification && p.status != PtpStatus.financialSyncPending;
    }).toList()
      ..sort((a, b) => b.promiseDate.compareTo(a.promiseDate));
    final expected = matured.fold(0.0, (s, p) => s + p.amountPromised);
    final actual = matured.fold(0.0, (s, p) => s + (p.amountReceived ?? 0));
    final gap = (expected - actual).clamp(0, double.infinity);
    final pct = expected == 0 ? 0.0 : (actual / expected * 100);

    final outcomeBuckets = <String, List<PromiseToPay>>{
      'Fully Kept': matured.where((p) => p.status == PtpStatus.kept).toList(),
      'Partially Kept': matured.where((p) => p.status == PtpStatus.partiallyKept).toList(),
      'Broken': matured.where((p) => p.status == PtpStatus.broken).toList(),
    };
    final outcomeColors = {'Fully Kept': kGreen, 'Partially Kept': kOrange, 'Broken': kRed};

    final trend = store.collectionTrend;

    final salesmen = store.salesmen.where((s) =>
        (filters.branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == filters.branch) &&
        (filters.salesman == 'All Salesmen' || s['name'] == filters.salesman)).toList();
    final rows = salesmen.map((s) {
      final name = s['name'] as String;
      final displayName = (s['fullName'] as String?) ?? name;
      final ids = store.customers.where((c) => c.assignedSalesmanId == name).map((c) => c.id).toSet();
      final mine = matured.where((p) => ids.contains(p.customerId)).toList();
      final mineExpected = mine.fold(0.0, (a, p) => a + p.amountPromised);
      final mineActual = mine.fold(0.0, (a, p) => a + (p.amountReceived ?? 0));
      final eff = mineExpected == 0 ? 0.0 : mineActual / mineExpected * 100;
      return {'name': displayName, 'branch': s['branch'], 'expected': mineExpected, 'actual': mineActual, 'efficiency': eff};
    }).toList()
      ..sort((a, b) => ((b['efficiency'] as num).toDouble()).compareTo((a['efficiency'] as num).toDouble()));
    final rowsSearched = rows.where((r) => (r['name'] as String).toLowerCase().contains(_salesmanQuery.toLowerCase())).toList();

    return _ReportScaffold(
      title: 'Expected vs Actual Collection',
      subtitle: 'Compare committed promises against real receipts',
      children: [
        _ReportFilterBar(
          showDateRange: true,
          dateRange: _dateRange,
          onDateRangeChanged: (v) => setState(() => _dateRange = v),
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.event_available_outlined, kPurple, '${matured.length}', 'Matured PTPs'),
            _statTile(Icons.trending_up, kBlue, _rupee.format(expected), 'Expected (Committed)'),
            _statTile(Icons.currency_rupee, kGreen, _rupee.format(actual), 'Actual (Received)'),
            _statTile(Icons.trending_down, kRed, _rupee.format(gap), 'Shortfall'),
            _statTile(Icons.speed, pct >= 75 ? kGreen : (pct >= 50 ? kOrange : kRed), '${pct.toStringAsFixed(1)}%', 'Collection Efficiency'),
            _statTile(Icons.link_off, kRed, '${outcomeBuckets['Broken']!.length}', 'Fully Uncollected'),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Collection Trend (Last 6 Months)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, m) => Text(_shortRupee(v), style: const TextStyle(fontSize: 9, color: kMuted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= trend.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'], style: const TextStyle(fontSize: 9, color: kMuted)));
                  })),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['expected'] as num).toDouble())],
                    isCurved: true,
                    color: kBlue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['actual'] as num).toDouble())],
                    isCurved: true,
                    color: kGreen,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: kGreen.withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 9, height: 9, decoration: const BoxDecoration(color: kBlue, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('Expected', style: TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 16),
            Container(width: 9, height: 9, decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('Actual', style: TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
          ]),
        ]),
        const SizedBox(height: 20),
        const Text('Outcome Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                    sections: outcomeBuckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.length.toDouble(), color: outcomeColors[e.key], radius: 26, showTitle: false)).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: outcomeBuckets.entries.map((e) {
                    final amt = e.value.fold(0.0, (s, p) => s + p.amountPromised);
                    final pct2 = matured.isEmpty ? 0.0 : e.value.length / matured.length * 100;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: outcomeColors[e.key], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('${e.value.length} (${pct2.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 10, color: kMuted)),
                            Text(_rupee.format(amt), style: const TextStyle(fontSize: 9, color: kMuted)),
                          ]),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Salesman Collection Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search salesman by name...', onChanged: (v) => setState(() => _salesmanQuery = v)),
        _scrollableBlock(rowsSearched.isEmpty ? [_emptyText('No salesmen match this search.')] : rowsSearched.map((r) {
          final name = r['name'] as String;
          final eff = (r['efficiency'] as num).toDouble();
          final band = _efficiencyBand(eff);
          final bandColor = _efficiencyBandColor(band);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: InfoCard(children: [
              Row(children: [
                CircleAvatar(radius: 16, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kDark)),
                      Text(((r['branch'] as String?) ?? 'Turning Point'), style: const TextStyle(fontSize: 10, color: kMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: bandColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(band, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: bandColor)),
                ),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
              KeyValueRow('Expected', _rupee.format(r['expected'])),
              KeyValueRow('Actual', _rupee.format(r['actual']), valueColor: kGreen),
              KeyValueRow('Efficiency', '${eff.toStringAsFixed(1)}%', valueColor: bandColor),
            ]),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Top 5 by Collection Efficiency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: rows.isEmpty ? [_emptyText('No collection data matches this filter.')] : rows.take(5).toList().asMap().entries.map((e) {
          final medal = ['🥇', '🥈', '🥉', '4', '5'][e.key];
          final r = e.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text(medal, style: const TextStyle(fontSize: 14))),
                const SizedBox(width: 8),
                Expanded(child: Text(r['name'] as String, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark))),
                Text('${((r['efficiency'] as num).toDouble()).toStringAsFixed(1)}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _efficiencyBandColor(_efficiencyBand((r['efficiency'] as num).toDouble())))),
              ],
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        const Text('Efficiency Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          _effLegendRow('Excellent', '85% and above'),
          _effLegendRow('Good', '70% – 84%'),
          _effLegendRow('Average', '50% – 69%'),
          _effLegendRow('Below Average', '30% – 49%'),
          _effLegendRow('Poor', 'Below 30%'),
        ]),
        const SizedBox(height: 20),
        Text('Collection Details · ${matured.length} PTPs', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _customerQuery = v)),
        Builder(builder: (context) {
          final searched = matured.where((p) => (customerById[p.customerId]?.name ?? '').toLowerCase().contains(_customerQuery.toLowerCase())).toList();
          if (searched.isEmpty) return _emptyCard('No matured PTPs match this filter.');
          return Column(children: searched.map((p) {
          final c = customerById[p.customerId]!;
          final received = p.amountReceived ?? 0;
          final variance = received - p.amountPromised;
          final color = p.status == PtpStatus.kept ? kGreen : (p.status == PtpStatus.partiallyKept ? kOrange : kRed);
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 16, backgroundColor: avatarColorFor(c.name).withOpacity(0.15), child: Text(initialsFor(c.name), style: TextStyle(color: avatarColorFor(c.name), fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                        Text('${store.salesmanDisplayName(c.assignedSalesmanId)} · Promised ${DateFormat('dd MMM yyyy').format(p.promiseDate)}', style: const TextStyle(fontSize: 10, color: kMuted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${_rupee.format(received)} / ${_rupee.format(p.amountPromised)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: kDark)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                        child: Text(variance >= 0 ? 'Full' : _rupee.format(variance), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList());
        }),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
          ],
        ),
      ),
    );
  }

  Widget _effLegendRow(String label, String range) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: _efficiencyBandColor(label), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: kDark, fontWeight: FontWeight.w600))),
          Text(range, style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 8) No Follow-Up Accounts
// ---------------------------------------------------------------------
/// Configured high-value threshold (spec §71 lists "High-value thresholds"
/// as explicitly configurable/TBD — this is the chosen default).
const double kHighValueThreshold = 200000;

String _followUpPriority(int days) {
  if (days >= 15) return 'Critical';
  if (days >= 11) return 'High';
  if (days >= 7) return 'Medium';
  return 'Low';
}

Color _followUpPriorityColor(String p) {
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

class NoFollowUpAccountsReport extends StatefulWidget {
  final ReportFilters filters;
  const NoFollowUpAccountsReport({super.key, required this.filters});

  @override
  State<NoFollowUpAccountsReport> createState() => _NoFollowUpAccountsReportState();
}

class _NoFollowUpAccountsReportState extends State<NoFollowUpAccountsReport> {
  String _customerQuery = '';
  String _salesmanQuery = '';
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();
    final items = store.noFollowUpAccounts.where(filters.matchesCustomer).toList()
      ..sort((a, b) => store.daysSinceLastFollowUp(b).compareTo(store.daysSinceLastFollowUp(a)));

    final outstandingAtRisk = items.fold(0.0, (s, c) => s + c.totalDue);
    final highValueCount = items.where((c) => c.totalDue >= kHighValueThreshold).length;
    final salesmenInvolved = items.map((c) => c.assignedSalesmanId).where((s) => s.isNotEmpty).toSet().length;
    final avgDays = items.isEmpty ? 0.0 : items.fold(0, (s, c) => s + store.daysSinceLastFollowUp(c)) / items.length;
    final criticalCount = items.where((c) => store.daysSinceLastFollowUp(c) >= 15).length;

    final priorityCounts = <String, int>{'Critical': 0, 'High': 0, 'Medium': 0, 'Low': 0};
    for (final c in items) {
      priorityCounts[_followUpPriority(store.daysSinceLastFollowUp(c))] = (priorityCounts[_followUpPriority(store.daysSinceLastFollowUp(c))] ?? 0) + 1;
    }

    final trend = store.noFollowUpTrend;

    final salesmen = store.salesmen.where((s) =>
        (filters.branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == filters.branch) &&
        (filters.salesman == 'All Salesmen' || s['name'] == filters.salesman)).toList();
    final salesmanRows = salesmen.map((s) {
      final name = s['name'] as String;
      final displayName = (s['fullName'] as String?) ?? name;
      final accounts = items.where((c) => c.assignedSalesmanId == name).toList();
      return {'name': displayName, 'accounts': accounts};
    }).where((r) => (r['accounts'] as List).isNotEmpty).toList()
      ..sort((a, b) => (b['accounts'] as List).length.compareTo((a['accounts'] as List).length));
    final salesmanRowsSearched = salesmanRows.where((r) => (r['name'] as String).toLowerCase().contains(_salesmanQuery.toLowerCase())).toList();

    return _ReportScaffold(
      title: 'No Follow-Up Accounts',
      subtitle: 'Track customers where recovery follow-up is missing or overdue',
      children: [
        _ReportFilterBar(
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.person_off_outlined, kPurple, '${items.length}', 'Total No Follow-Up Accounts'),
            _statTile(Icons.warning_amber_rounded, kRed, _rupee.format(outstandingAtRisk), 'Outstanding at Risk'),
            _statTile(Icons.diamond_outlined, const Color(0xFFCA8A04), '$highValueCount', 'High Value Accounts'),
            _statTile(Icons.groups_outlined, kBlue, '$salesmenInvolved', 'Salesmen Involved'),
            _statTile(Icons.schedule, kGreen, '${avgDays.toStringAsFixed(1)} Days', 'Avg Days Since Last Follow-Up'),
            _statTile(Icons.error_outline, kRed, '$criticalCount', 'Critical Accounts (15+ Days)'),
          ],
        ),
        const SizedBox(height: 20),
        const Text('No Follow-Up Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text('${v.toInt()}', style: const TextStyle(fontSize: 9, color: kMuted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 || i >= trend.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'], style: const TextStyle(fontSize: 8.5, color: kMuted)));
                  })),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['count'] as num).toDouble())],
                    isCurved: true,
                    color: kBlue,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: kBlue.withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Priority Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Critical', 'High', 'Medium', 'Low'].map((p) {
            final color = _followUpPriorityColor(p);
            final icon = p == 'Critical' ? Icons.error_outline : (p == 'High' ? Icons.arrow_upward : (p == 'Medium' ? Icons.remove : Icons.arrow_downward));
            return SizedBox(
              width: 100,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                child: Column(
                  children: [
                    Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 14, color: color)),
                    const SizedBox(height: 6),
                    Text(p, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
                    Text('${priorityCounts[p]}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Text('No Follow-Up Account List · ${items.length} Accounts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _customerQuery = v)),
        Builder(builder: (context) {
          final searched = items.where((c) => c.name.toLowerCase().contains(_customerQuery.toLowerCase())).toList();
          if (searched.isEmpty) return _emptyCard('No accounts match this filter.');
          return Column(children: searched.map((c) {
          final days = store.daysSinceLastFollowUp(c);
          final priority = _followUpPriority(days);
          final color = _followUpPriorityColor(priority);
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
              child: Row(
                children: [
                  CircleAvatar(radius: 16, backgroundColor: avatarColorFor(c.name).withOpacity(0.15), child: Text(initialsFor(c.name), style: TextStyle(color: avatarColorFor(c.name), fontSize: 11, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                        Text('${store.salesmanDisplayName(c.assignedSalesmanId)} · $days Days Since Last Follow-Up', style: const TextStyle(fontSize: 10, color: kMuted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_rupee.format(c.totalDue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                        child: Text(priority, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: kMuted),
                ],
              ),
            ),
          );
        }).toList());
        }),
        const SizedBox(height: 20),
        const Text('Salesman No Follow-Up Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        _ReportSearchField(hint: 'Search salesman by name...', onChanged: (v) => setState(() => _salesmanQuery = v)),
        _scrollableBlock([
          InfoCard(children: salesmanRowsSearched.isEmpty ? [_emptyText('No salesmen match this filter.')] : salesmanRowsSearched.map((r) {
            final name = r['name'] as String;
            final accounts = r['accounts'] as List<Customer>;
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _NoFollowUpSalesmanScreen(name: name, accounts: accounts))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(radius: 14, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 10, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark))),
                    Text('${accounts.length} accounts', style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: kMuted),
                  ],
                ),
              ),
            );
          }).toList()),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFDBA74))),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 15, color: Color(0xFFC2410C)),
            SizedBox(width: 8),
            Expanded(child: Text('No Follow-Up Accounts are customers with due exposure where no valid recovery activity has been logged within the required control window (${AppStore.noFollowUpThresholdDays}+ days, configurable).', style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, size: 14, color: kMuted),
          const SizedBox(width: 6),
          Text('Last Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
        ]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color))),
          ],
        ),
      ),
    );
  }
}

class _NoFollowUpSalesmanScreen extends StatefulWidget {
  final String name;
  final List<Customer> accounts;
  const _NoFollowUpSalesmanScreen({required this.name, required this.accounts});

  @override
  State<_NoFollowUpSalesmanScreen> createState() => _NoFollowUpSalesmanScreenState();
}

class _NoFollowUpSalesmanScreenState extends State<_NoFollowUpSalesmanScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final sorted = [...widget.accounts]..sort((a, b) => store.daysSinceLastFollowUp(b).compareTo(store.daysSinceLastFollowUp(a)));
    final searched = sorted.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();
    return _ReportScaffold(
      title: widget.name,
      subtitle: '${widget.accounts.length} no follow-up accounts',
      children: [
        _ReportSearchField(hint: 'Search customer name...', onChanged: (v) => setState(() => _query = v)),
        if (searched.isEmpty) _emptyCard('No accounts match this search.'),
        ...searched.map((c) {
          final days = store.daysSinceLastFollowUp(c);
          return _drillRow(context, c.name, '$days Days Since Last Follow-Up', _rupee.format(c.totalDue), _followUpPriorityColor(_followUpPriority(days)), () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))));
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// 9) Recovery Target — Target vs Actual Recovery  (RE-only)
// ---------------------------------------------------------------------
/// Fixed business tiers of the total-overdue amount. NOT rolling by month —
/// these percentages never shift based on the calendar.
const _kRecoveryTargetTiers = <({String label, double pct})>[
  (label: 'Tier 1', pct: 0.25),
  (label: 'Tier 2', pct: 0.35),
  (label: 'Tier 3', pct: 0.50),
  (label: 'Tier 4', pct: 0.70),
];

class RecoveryTargetVsActualReport extends StatefulWidget {
  final ReportFilters filters;
  const RecoveryTargetVsActualReport({super.key, required this.filters});

  @override
  State<RecoveryTargetVsActualReport> createState() => _RecoveryTargetVsActualReportState();
}

class _RecoveryTargetVsActualReportState extends State<RecoveryTargetVsActualReport> {
  late String _branch = widget.filters.branch;
  late String _salesman = widget.filters.salesman;

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color))),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, {double width = 96, Color? color, FontWeight weight = FontWeight.w600, TextAlign align = TextAlign.right}) {
    return SizedBox(
      width: width,
      child: Text(text, textAlign: align, style: TextStyle(fontSize: 11.5, fontWeight: weight, color: color ?? kNavy)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = ReportFilters(branch: _branch, salesman: _salesman);
    final store = context.watch<AppStore>();

    // Overdue = totalDue (never total outstanding). Respect the Reports
    // branch / salesman filter, like every other report.
    final scoped = store.customers.where(filters.matchesCustomer).toList();
    final totalOverdue = scoped.fold<double>(0.0, (s, c) => s + c.totalDue);

    // Actual recovery = the existing primitive: amountReceived on PTPs that
    // were kept / partially kept, for the filtered customers.
    final scopedIds = scoped.map((c) => c.id).toSet();
    final actualRecovery = store.ptps
        .where((p) =>
            (p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept) &&
            scopedIds.contains(p.customerId))
        .fold<double>(0.0, (s, p) => s + (p.amountReceived ?? 0));

    final tier1Target = totalOverdue * _kRecoveryTargetTiers.first.pct;
    final tier1Achievement = tier1Target <= 0 ? null : actualRecovery / tier1Target * 100;
    final onTrack = tier1Achievement != null && tier1Achievement >= 100;

    return _ReportScaffold(
      title: 'Recovery Target',
      subtitle: 'Target vs Actual Recovery',
      children: [
        _ReportFilterBar(
          branch: _branch,
          onBranchChanged: (v) => setState(() => _branch = v),
          salesman: _salesman,
          onSalesmanChanged: (v) => setState(() => _salesman = v),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statTile(Icons.account_balance_wallet_outlined, kBlue, _rupee.format(totalOverdue), 'Total Overdue'),
            _statTile(Icons.currency_rupee, kGreen, _rupee.format(actualRecovery), 'Actual Recovery'),
            _statTile(Icons.track_changes, kOrange, _rupee.format(tier1Target), 'Target (Tier 1 · 25%)'),
            _statTile(Icons.speed, onTrack ? kGreen : kRed, tier1Achievement == null ? '—' : '${tier1Achievement.toStringAsFixed(2)}%', 'Achievement'),
            _statTile(onTrack ? Icons.check_circle_outline : Icons.trending_down, onTrack ? kGreen : kRed, onTrack ? 'On Track' : 'Behind', 'Status'),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Tier Comparison', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
        const SizedBox(height: 10),
        InfoCard(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    _cell('Tier', width: 60, align: TextAlign.left, color: kMuted, weight: FontWeight.w700),
                    _cell('Target %', width: 72, color: kMuted, weight: FontWeight.w700),
                    _cell('Target Amount', width: 120, color: kMuted, weight: FontWeight.w700),
                    _cell('Actual Recovery', width: 120, color: kMuted, weight: FontWeight.w700),
                    _cell('Achievement', width: 96, color: kMuted, weight: FontWeight.w700),
                    _cell('Shortfall / Excess', width: 130, color: kMuted, weight: FontWeight.w700),
                  ]),
                ),
                const Divider(height: 1, color: kBorder),
                ..._kRecoveryTargetTiers.map((t) {
                  final target = totalOverdue * t.pct;
                  final achievement = target <= 0 ? null : actualRecovery / target * 100;
                  final delta = actualRecovery - target;
                  final String deltaText;
                  final Color deltaColor;
                  if (target <= 0) {
                    deltaText = '—';
                    deltaColor = kMuted;
                  } else if (delta < 0) {
                    deltaText = 'Short ${_rupee.format(delta.abs())}';
                    deltaColor = kRed;
                  } else if (delta > 0) {
                    deltaText = 'Excess ${_rupee.format(delta)}';
                    deltaColor = kGreen;
                  } else {
                    deltaText = 'Achieved';
                    deltaColor = kGreen;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      _cell(t.label, width: 60, align: TextAlign.left, weight: FontWeight.w800),
                      _cell('${(t.pct * 100).toStringAsFixed(0)}%', width: 72),
                      _cell(_rupee.format(target), width: 120, weight: FontWeight.w700),
                      _cell(_rupee.format(actualRecovery), width: 120),
                      _cell(achievement == null ? '—' : '${achievement.toStringAsFixed(2)}%', width: 96, color: achievement != null && achievement >= 100 ? kGreen : kRed, weight: FontWeight.w700),
                      _cell(deltaText, width: 130, color: deltaColor, weight: FontWeight.w700),
                    ]),
                  );
                }),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        const Text(
          'Actual recovery = amount received on kept / partially-kept PTPs. Target % is a fixed tier of the total overdue amount.',
          style: TextStyle(fontSize: 10.5, color: kMuted),
        ),
      ],
    );
  }
}
