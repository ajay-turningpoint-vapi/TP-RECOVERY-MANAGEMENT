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

const _bucketColors = {'Awaiting Review': kOrange, 'In Progress': kPurple, 'Resolved': kGreen, 'Rejected': kRed};

/// Real classification of a dispute's own reason text — not an invented label.
String _reasonCategory(String reason) {
  final r = reason.toLowerCase();
  if (r.contains('wrong') || r.contains('damage')) return 'Goods Issue';
  if (r.contains('quantity') || r.contains('shortage') || r.contains('short delivery')) return 'Short Delivery';
  if (r.contains('rate') || r.contains('discrepancy')) return 'Rate Discrepancy';
  if (r.contains('freight')) return 'Freight Charge';
  if (r.contains('invoice') || r.contains('credit') || r.contains('reflected')) return 'Invoice Issue';
  return 'Others';
}

IconData _reasonIcon(String category) {
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

/// Manager's Dispute Status Report — same real bucketing/reason analysis as
/// the RE's Dispute Status Report, restyled to the Manager visual language,
/// view-only (dispute actions live in the RE's Disputes tab).
class ManagerDisputeStatusReportScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerDisputeStatusReportScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerDisputeStatusReportScreen> createState() => _ManagerDisputeStatusReportScreenState();
}

enum _SortBy { dateDesc, amountDesc }

class _ManagerDisputeStatusReportScreenState extends State<ManagerDisputeStatusReportScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _SortBy _sort = _SortBy.dateDesc;

  Customer _customerFor(AppStore store, String name) => store.customers.firstWhere((c) => c.name == name, orElse: () => store.customers.first);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];
    final now = DateTime.now();

    bool inScope(Map<String, dynamic> d) {
      final c = _customerFor(store, d['customer'] as String);
      return (_branch == 'All Branches' || c.branch == _branch) && (_salesman == 'All Salesmen' || c.assignedSalesmanId == _salesman);
    }

    final disputes = store.disputes.where(inScope).toList()..sort((a, b) => (b['raisedDate'] as DateTime).compareTo(a['raisedDate'] as DateTime));
    final totalAmount = disputes.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));

    final buckets = <String, List<Map<String, dynamic>>>{
      'Awaiting Review': disputes.where((d) => _disputeBucket(d['status'] as String) == 'Awaiting Review').toList(),
      'In Progress': disputes.where((d) => _disputeBucket(d['status'] as String) == 'In Progress').toList(),
      'Resolved': disputes.where((d) => _disputeBucket(d['status'] as String) == 'Resolved').toList(),
      'Rejected': disputes.where((d) => _disputeBucket(d['status'] as String) == 'Rejected').toList(),
    };

    final byReason = <String, List<Map<String, dynamic>>>{};
    for (final d in disputes) {
      byReason.putIfAbsent(_reasonCategory(d['reason'] as String), () => []).add(d);
    }
    final reasonEntries = byReason.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));

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
    const agingColors = {'0-7 Days': kGreen, '8-15 Days': kBlue, '16-30 Days': kOrange, '31-60 Days': kPurple, '60+ Days': kRed};

    var rows = disputes.where((d) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return (d['customer'] as String).toLowerCase().contains(q);
    }).toList();
    if (_sort == _SortBy.amountDesc) rows.sort((a, b) => ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()));

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
                  _statCards(disputes.length, totalAmount, buckets),
                  const SizedBox(height: 20),
                  _distributionCard(context, buckets, disputes.length),
                  const SizedBox(height: 20),
                  _reasonsCard(reasonEntries),
                  const SizedBox(height: 20),
                  _agingRow(agingBuckets, agingColors),
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
                Text('Dispute Status Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Summary of all disputes by status and reason', style: TextStyle(fontSize: 10, color: kMuted)),
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

  Widget _statCards(int total, double totalAmount, Map<String, List<Map<String, dynamic>>> buckets) {
    final cards = [
      (Icons.description_outlined, kBlue, '$total', 'Total Disputes', _rupee.format(totalAmount)),
      ...buckets.entries.map((e) {
        final amt = e.value.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
        final icon = e.key == 'Awaiting Review' ? Icons.hourglass_empty : (e.key == 'In Progress' ? Icons.sync : (e.key == 'Resolved' ? Icons.check_circle_outline : Icons.cancel_outlined));
        return (icon, _bucketColors[e.key]!, '${e.value.length}', e.key, _rupee.format(amt));
      }),
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
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: color))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(sub, style: const TextStyle(fontSize: 9, color: kMuted))),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _distributionCard(BuildContext context, Map<String, List<Map<String, dynamic>>> buckets, int total) {
    return InfoCard(
      children: [
        const Text('Disputes by Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _bucketColors[e.key], shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                        Text('${e.value.length} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 9.5, color: kMuted)),
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

  Widget _reasonsCard(List<MapEntry<String, List<Map<String, dynamic>>>> reasonEntries) {
    return InfoCard(
      children: [
        const Text('Disputes by Reason', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        if (reasonEntries.isEmpty)
          const Text('No disputes in this view.', style: TextStyle(fontSize: 11, color: kMuted))
        else
          ...reasonEntries.map((e) {
            final total = e.value.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kIndigo.withOpacity(0.1), shape: BoxShape.circle), child: Icon(_reasonIcon(e.key), size: 15, color: kIndigo)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kDark))),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${e.value.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                      Text(_rupee.format(total), style: const TextStyle(fontSize: 9.5, color: kMuted)),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _agingRow(Map<String, List<Map<String, dynamic>>> agingBuckets, Map<String, Color> agingColors) {
    return InfoCard(
      children: [
        const Text('Disputes Aging', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: agingBuckets.entries.map((e) {
            final total = e.value.fold(0.0, (s, d) => s + ((d['amount'] as num).toDouble()));
            final color = agingColors[e.key]!;
            return SizedBox(
              width: 92,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.15))),
                child: Column(
                  children: [
                    Text(e.key, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('${e.value.length}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color)),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(total), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _detailsTable(AppStore store, List<Map<String, dynamic>> rows) {
    return InfoCard(
      children: [
        const Text('Dispute Status Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No disputes match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.take(30).map((d) {
            final bucket = _disputeBucket(d['status'] as String);
            final color = _bucketColors[bucket]!;
            final c = _customerFor(store, d['customer'] as String);
            return InkWell(
              onTap: () => _showDisputeDetail(context, d, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['customer'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                          Text('${d['invoice']}  ·  ${c.branch}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(d['amount']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
                          Text(DateFormat('dd MMM').format(d['raisedDate']), style: const TextStyle(fontSize: 8.5, color: kMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(bucket, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _showDisputeDetail(BuildContext context, Map<String, dynamic> d, Customer c) {
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
              Text(d['customer'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
              Text('${c.branch}  ·  ${context.read<AppStore>().salesmanDisplayName(c.assignedSalesmanId)}', style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 14),
              _kv('Invoice', (d['invoice'] as String?) ?? 'No invoice'),
              _kv('Amount', _rupee.format(d['amount'])),
              _kv('Reason', d['reason'] as String),
              _kv('Status', d['status'] as String),
              _kv('Raised On', DateFormat('dd MMM yyyy, hh:mm a').format(d['raisedDate'] as DateTime)),
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
          const Expanded(child: Text('Disputes are grouped by their current resolution status and raised reason.', style: TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(onTap: () => setState(() => store.refreshBusySync()), child: const Icon(Icons.refresh, size: 15, color: kBlue)),
        ],
      ),
    );
  }
}
