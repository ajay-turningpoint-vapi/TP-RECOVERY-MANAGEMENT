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
const _kAmber = Color(0xFFCA8A04);

/// A dispute's overall management status, grouped from its real, granular
/// status field into the 4 stages this summary tracks.
String _summaryBucket(String status) {
  switch (status) {
    case 'Approved':
    case 'Resolved':
      return 'Approved';
    case 'Rejected':
      return 'Rejected';
    case 'Pending Approval':
      return 'Pending Approval';
    default: // In Resolution, Awaiting Verification, Need More Information
      return 'Pending Review';
  }
}

const _summaryColors = {'Pending Review': kBlue, 'Pending Approval': kOrange, 'Approved': kGreen, 'Rejected': kRed};

/// Real classification of a dispute's own reason text into the 5 buckets
/// this summary tracks — not an invented label.
String _summaryReasonCategory(String reason) {
  final r = reason.toLowerCase();
  if (r.contains('damage')) return 'Damaged Material';
  if (r.contains('short delivery') || r.contains('shortage')) return 'Short Delivery';
  if (r.contains('rate') || r.contains('pricing') || r.contains('discrepancy')) return 'Rate Difference';
  if (r.contains('return') || r.contains('credit') || r.contains('reflected')) return 'Quality Issue';
  return 'Other Reasons';
}

const _reasonColors = {'Quality Issue': kPurple, 'Short Delivery': kOrange, 'Rate Difference': kBlue, 'Damaged Material': kRed, 'Other Reasons': kGreen};

IconData _summaryReasonIcon(String category) {
  switch (category) {
    case 'Quality Issue':
      return Icons.assignment_outlined;
    case 'Short Delivery':
      return Icons.local_shipping_outlined;
    case 'Rate Difference':
      return Icons.swap_horiz;
    case 'Damaged Material':
      return Icons.warning_amber_rounded;
    default:
      return Icons.more_horiz;
  }
}

enum _SummaryTab { recent, pendingReview, pendingApproval, approved, rejected }

enum _SortBy { dateDesc, amountDesc }

/// Manager's Dispute Management — Summary: a company-wide overview of every
/// dispute's status, ageing and reason, with a tabbed/searchable detail
/// table. View-only — dispute actions live in the RE's Disputes tab.
class ManagerDisputeManagementSummaryScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerDisputeManagementSummaryScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerDisputeManagementSummaryScreen> createState() => _ManagerDisputeManagementSummaryScreenState();
}

class _ManagerDisputeManagementSummaryScreenState extends State<ManagerDisputeManagementSummaryScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }
  String _query = '';
  _SortBy _sort = _SortBy.dateDesc;
  _SummaryTab _tab = _SummaryTab.recent;

  Customer _customerFor(AppStore store, String name) => store.customers.firstWhere((c) => c.name == name, orElse: () => store.customers.first);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    final now = DateTime.now();

    final disputes = store.disputes.where((d) {
      final c = _customerFor(store, d['customer'] as String);
      return _branch == 'All Branches' || c.branch == _branch;
    }).toList()
      ..sort((a, b) => (b['raisedDate'] as DateTime).compareTo(a['raisedDate'] as DateTime));

    final totalAmount = disputes.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));

    final buckets = <String, List<Map<String, dynamic>>>{
      'Pending Review': disputes.where((d) => _summaryBucket(d['status'] as String) == 'Pending Review').toList(),
      'Pending Approval': disputes.where((d) => _summaryBucket(d['status'] as String) == 'Pending Approval').toList(),
      'Approved': disputes.where((d) => _summaryBucket(d['status'] as String) == 'Approved').toList(),
      'Rejected': disputes.where((d) => _summaryBucket(d['status'] as String) == 'Rejected').toList(),
    };

    final ageingBuckets = <String, List<Map<String, dynamic>>>{'0 - 15 days': [], '16 - 30 days': [], '31 - 60 days': [], '60+ days': []};
    for (final d in disputes) {
      final days = now.difference(d['raisedDate'] as DateTime).inDays;
      if (days <= 15) {
        ageingBuckets['0 - 15 days']!.add(d);
      } else if (days <= 30) {
        ageingBuckets['16 - 30 days']!.add(d);
      } else if (days <= 60) {
        ageingBuckets['31 - 60 days']!.add(d);
      } else {
        ageingBuckets['60+ days']!.add(d);
      }
    }
    const ageingColors = {'0 - 15 days': kGreen, '16 - 30 days': kOrange, '31 - 60 days': kBlue, '60+ days': kRed};

    final byReason = <String, List<Map<String, dynamic>>>{};
    for (final d in disputes) {
      byReason.putIfAbsent(_summaryReasonCategory(d['reason'] as String), () => []).add(d);
    }
    final reasonOrder = ['Quality Issue', 'Short Delivery', 'Rate Difference', 'Damaged Material', 'Other Reasons'];
    final reasonEntries = reasonOrder.where((k) => byReason.containsKey(k)).map((k) => MapEntry(k, byReason[k]!)).toList()
      ..sort((a, b) => b.value.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble())).compareTo(a.value.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble()))));

    var rows = _tab == _SummaryTab.recent ? disputes : buckets[_tabLabel(_tab)]!;
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      rows = rows.where((d) => (d['customer'] as String).toLowerCase().contains(q) || (d['id'] as String).toLowerCase().contains(q) || ((d['invoice'] as String?) ?? '').toLowerCase().contains(q)).toList();
    }
    rows = List.of(rows);
    if (_sort == _SortBy.amountDesc) {
      rows.sort((a, b) => ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()));
    } else {
      rows.sort((a, b) => (b['raisedDate'] as DateTime).compareTo(a['raisedDate'] as DateTime));
    }

    final rowsTotalAmount = rows.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
    final avgAgeing = rows.isEmpty ? 0 : (rows.fold<int>(0, (s, d) => s + now.difference(d['raisedDate'] as DateTime).inDays) / rows.length).round();

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _filterRow(branches),
                  const SizedBox(height: 14),
                  _statCards(disputes.length, totalAmount, buckets),
                  const SizedBox(height: 16),
                  _statusAndAgeingRow(context, buckets, disputes.length, ageingBuckets, ageingColors, totalAmount),
                  const SizedBox(height: 16),
                  _reasonsCard(context, reasonEntries),
                  const SizedBox(height: 16),
                  _tabRow(buckets),
                  const SizedBox(height: 10),
                  _searchSortRow(),
                  const SizedBox(height: 10),
                  _table(context, store, rows, disputes.length, rowsTotalAmount, avgAgeing),
                  const SizedBox(height: 16),
                  _footer(context, store),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(_SummaryTab t) {
    switch (t) {
      case _SummaryTab.pendingReview:
        return 'Pending Review';
      case _SummaryTab.pendingApproval:
        return 'Pending Approval';
      case _SummaryTab.approved:
        return 'Approved';
      case _SummaryTab.rejected:
        return 'Rejected';
      case _SummaryTab.recent:
        return 'Recent Disputes';
    }
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: kNavy), tooltip: 'Back', onPressed: () => Navigator.pop(context)),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dispute Management – Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
                Text('Overview of all disputes and their status', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _snack(context, 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.')),
          const SizedBox(width: 8),
          _headerIcon(Icons.filter_alt_outlined, () => _snack(context, 'Use the Branch filter and tabs below to scope this summary.')),
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

  Widget _filterRow(List<String> branches) {
    return Row(
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
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: Row(
              children: [
                const Icon(Icons.apartment_outlined, size: 14, color: kBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _branch,
                      isDense: true,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 15, color: kMuted),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark),
                      items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) { if (v != null) { context.read<AppStore>().setBranchFilter(v); setState(() {}); } },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCards(int total, double totalAmount, Map<String, List<Map<String, dynamic>>> buckets) {
    final cards = [
      (kPurple, '$total', 'Total Disputes', '100%'),
      (_kAmber, _rupee.format(totalAmount), 'Amount In Dispute (₹)', '100%'),
      ...buckets.entries.map((e) {
        final pct = total <= 0 ? 0.0 : e.value.length / total * 100;
        return (_summaryColors[e.key]!, '${e.value.length}', e.key, '${pct.toStringAsFixed(2)}%');
      }),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (color, value, label, sub) = cards[i];
          return Container(
            width: 122,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.15))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kDark, fontWeight: FontWeight.w600)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusAndAgeingRow(BuildContext context, Map<String, List<Map<String, dynamic>>> buckets, int total, Map<String, List<Map<String, dynamic>>> ageingBuckets, Map<String, Color> ageingColors, double totalAmount) {
    return Column(
      children: [
        InfoCard(
          children: [
            const Text('Disputes by Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(PieChartData(centerSpaceRadius: 30, sectionsSpace: 2, sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.length.toDouble(), color: _summaryColors[e.key], radius: 20, showTitle: false)).toList())),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kNavy)),
                          const Text('Total', style: TextStyle(fontSize: 9, color: kMuted)),
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
                      final pct = total <= 0 ? 0.0 : e.value.length / total * 100;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: _summaryColors[e.key], shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                            Text('${e.value.length} (${pct.toStringAsFixed(2)}%)', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        InfoCard(
          children: [
            const Text('Disputes by Ageing (Amount in ₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
            const SizedBox(height: 14),
            ...ageingBuckets.entries.map((e) {
              final amt = e.value.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
              final pct = totalAmount <= 0 ? 0.0 : amt / totalAmount * 100;
              final color = ageingColors[e.key]!;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 70, child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1).toDouble(), minHeight: 8, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(color)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 82, child: Text('${_rupee.format(amt)} (${pct.toStringAsFixed(1)}%)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color))),
                  ],
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _reasonsCard(BuildContext context, List<MapEntry<String, List<Map<String, dynamic>>>> reasonEntries) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('Top Dispute Reasons (Amount in ₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy))),
            if (reasonEntries.isNotEmpty)
              GestureDetector(
                onTap: () => _showAllReasons(context, reasonEntries),
                child: const Text('View All Reasons', style: TextStyle(color: kBlue, fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (reasonEntries.isEmpty)
          const Text('No disputes in this view.', style: TextStyle(fontSize: 11, color: kMuted))
        else
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reasonEntries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final e = reasonEntries[i];
                final amt = e.value.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
                final totalAmt = reasonEntries.fold<double>(0.0, (s, r) => s + r.value.fold<double>(0.0, (s2, d) => s2 + ((d['amount'] as num).toDouble())));
                final pct = totalAmt <= 0 ? 0.0 : amt / totalAmt * 100;
                final color = _reasonColors[e.key]!;
                return Container(
                  width: 112,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.15))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(_summaryReasonIcon(e.key), size: 14, color: color)),
                      const SizedBox(height: 6),
                      Text(e.key, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: kDark, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(_rupee.format(amt), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color))),
                      Text('${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 8.5, color: color)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showAllReasons(BuildContext context, List<MapEntry<String, List<Map<String, dynamic>>>> reasonEntries) {
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
              const Text('Dispute Reasons', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
              const SizedBox(height: 12),
              ...reasonEntries.map((e) {
                final amt = e.value.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12.5, color: kDark, fontWeight: FontWeight.w600))),
                      Text('${e.value.length} · ${_rupee.format(amt)}', style: const TextStyle(fontSize: 12, color: kMuted)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabRow(Map<String, List<Map<String, dynamic>>> buckets) {
    final tabs = [
      (_SummaryTab.recent, 'Recent Disputes'),
      (_SummaryTab.pendingReview, 'Pending Review (${buckets['Pending Review']!.length})'),
      (_SummaryTab.pendingApproval, 'Pending Approval (${buckets['Pending Approval']!.length})'),
      (_SummaryTab.approved, 'Approved (${buckets['Approved']!.length})'),
      (_SummaryTab.rejected, 'Rejected (${buckets['Rejected']!.length})'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (value, label) = tabs[i];
          final selected = _tab == value;
          return InkWell(
            onTap: () => setState(() => _tab = value),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? kPurple : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? kPurple : kBorder),
              ),
              child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : kDark)),
            ),
          );
        },
      ),
    );
  }

  Widget _searchSortRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 12.5, color: kDark),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12), border: InputBorder.none, hintText: 'Search by customer name, ID or invoice no.', hintStyle: TextStyle(fontSize: 11.5, color: kMuted)),
                  ),
                ),
                const Icon(Icons.search, size: 18, color: kMuted),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kNavy, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () => setState(() => _sort = _sort == _SortBy.dateDesc ? _SortBy.amountDesc : _SortBy.dateDesc),
          icon: const Icon(Icons.swap_vert, size: 15),
          label: const Text('Sort', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, AppStore store, List<Map<String, dynamic>> rows, int totalDisputes, double totalAmount, int avgAgeing) {
    return InfoCard(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(width: 90, child: Text('Dispute ID', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 140, child: Text('Customer Name / Invoice No.', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 130, child: Text('Reason / Dispute Date', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 100, child: Text('Amount (₹) / Ageing', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 120, child: Text('Status / Raised By', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 30, child: Text('', style: TextStyle(fontSize: 9.5)))
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                if (rows.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('No disputes match this search.', style: TextStyle(fontSize: 12, color: kMuted))))
                else
                  ...rows.take(30).map((d) => _disputeRow(context, store, d)),
                if (rows.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                  Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Disputes', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                            Text('$totalDisputes', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kNavy)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Amount in Dispute', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(_rupee.format(totalAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kBlue))),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Average Ageing', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                            Text('$avgAgeing Days', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kOrange)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _disputeRow(BuildContext context, AppStore store, Map<String, dynamic> d) {
    final c = _customerFor(store, d['customer'] as String);
    final bucket = _summaryBucket(d['status'] as String);
    final color = _summaryColors[bucket]!;
    final reason = _summaryReasonCategory(d['reason'] as String);
    final days = DateTime.now().difference(d['raisedDate'] as DateTime).inDays;
    return InkWell(
      onTap: () => _showDisputeDetail(context, d, c, bucket, reason, days),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(d['id'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['customer'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                  Text((d['invoice'] as String?) ?? 'No invoice', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reason, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kDark, fontWeight: FontWeight.w600)),
                  Text(DateFormat('dd MMM yyyy').format(d['raisedDate'] as DateTime), style: const TextStyle(fontSize: 9, color: kMuted)),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(d['amount']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
                  Text('$days days', style: const TextStyle(fontSize: 9, color: kMuted)),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(bucket, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color)),
                  ),
                  const SizedBox(height: 2),
                  Text(store.salesmanDisplayName(c.assignedSalesmanId), style: const TextStyle(fontSize: 8.5, color: kMuted)),
                ],
              ),
            ),
            const SizedBox(width: 30, child: Icon(Icons.chevron_right, size: 16, color: kMuted)),
          ],
        ),
      ),
    );
  }

  void _showDisputeDetail(BuildContext context, Map<String, dynamic> d, Customer c, String bucket, String reason, int days) {
    final color = _summaryColors[bucket]!;
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['customer'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                        Text('${d['id']}  ·  ${c.branch}', style: const TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(bucket, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _kv('Invoice No.', (d['invoice'] as String?) ?? 'No invoice'),
              _kv('Amount', _rupee.format(d['amount'])),
              _kv('Reason', reason),
              _kv('Dispute Date', DateFormat('dd MMM yyyy').format(d['raisedDate'] as DateTime)),
              _kv('Ageing', '$days days'),
              _kv('Raised By', context.read<AppStore>().salesmanDisplayName(c.assignedSalesmanId)),
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
              const Text('Manager view is read-only — dispute actions are taken by the Recovery Executive.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600))),
          Text(value, style: const TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Disputes are grouped by their current management status and raised reason.', style: TextStyle(fontSize: 10.5, color: kDark)),
                const SizedBox(height: 2),
                Text('Last synced ${DateFormat('hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => store.refreshBusySync()),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.refresh, size: 16, color: kBlue)),
          ),
        ],
      ),
    );
  }
}
