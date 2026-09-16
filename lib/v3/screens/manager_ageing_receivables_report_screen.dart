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

/// Real per-customer synthetic invoice row for customers without a detailed
/// `invoices` list — built from their actual creditDays/oldestOverdueDays/
/// totalDue, not an invented number (mirrors the RE report's approach).
class _AgeingRow {
  final Customer customer;
  final String invoiceNo;
  final DateTime dueDate;
  final double outstanding;
  _AgeingRow({required this.customer, required this.invoiceNo, required this.dueDate, required this.outstanding});

  String bucket(DateTime now) {
    if (dueDate.isAfter(now)) return 'Not Due';
    final days = now.difference(dueDate).inDays;
    if (days <= 30) return '0 - 30 Days';
    if (days <= 60) return '31 - 60 Days';
    if (days <= 90) return '61 - 90 Days';
    return '90+ Days';
  }
}

const _bucketColors = {'Not Due': kGreen, '0 - 30 Days': kOrange, '31 - 60 Days': kRed, '61 - 90 Days': kPurple, '90+ Days': Color(0xFF991B1B)};

/// Manager's Ageing Receivables Report — same real per-invoice ageing
/// analysis as the RE's report, restyled to the Manager visual language.
class ManagerAgeingReceivablesReportScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerAgeingReceivablesReportScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerAgeingReceivablesReportScreen> createState() => _ManagerAgeingReceivablesReportScreenState();
}

enum _SortBy { dueDateAsc, amountDesc }

class _ManagerAgeingReceivablesReportScreenState extends State<ManagerAgeingReceivablesReportScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _SortBy _sort = _SortBy.dueDateAsc;

  List<_AgeingRow> _rowsFor(Customer c, DateTime now) {
    if (c.invoices.isNotEmpty) {
      final rows = c.invoices.map((inv) {
        final date = inv['date'] as DateTime;
        final amount = (inv['amount'] as num).toDouble();
        return _AgeingRow(customer: c, invoiceNo: inv['number'] as String, dueDate: date.add(Duration(days: c.creditDays)), outstanding: amount);
      }).toList();
      // Invoice face values don't reflect partial payments already made
      // against them (there's no per-invoice payment record) — reconcile
      // the last invoice's outstanding balance so the customer's rows sum
      // to their real, current totalDue (the same figure every other
      // screen in the app uses), instead of overstating exposure by the
      // amount already paid (mirrors the RE report's identical fix).
      final invoiceSum = rows.fold(0.0, (s, r) => s + r.outstanding);
      if (rows.isNotEmpty && invoiceSum != c.totalDue) {
        final last = rows.last;
        final adjusted = (last.outstanding - (invoiceSum - c.totalDue)).clamp(0.0, double.infinity);
        rows[rows.length - 1] = _AgeingRow(customer: last.customer, invoiceNo: last.invoiceNo, dueDate: last.dueDate, outstanding: adjusted);
      }
      return rows;
    }
    if (c.totalDue <= 0) return [];
    final due = now.subtract(Duration(days: c.oldestOverdueDays));
    return [_AgeingRow(customer: c, invoiceNo: 'AGG-${c.id}', dueDate: due, outstanding: c.totalDue)];
  }

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

    final customers = store.customers.where((c) => (_branch == 'All Branches' || c.branch == _branch) && (_salesman == 'All Salesmen' || c.assignedSalesmanId == _salesman)).toList();
    final allRows = <_AgeingRow>[];
    for (final c in customers) {
      allRows.addAll(_rowsFor(c, now));
    }
    allRows.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final buckets = <String, List<_AgeingRow>>{'Not Due': [], '0 - 30 Days': [], '31 - 60 Days': [], '61 - 90 Days': [], '90+ Days': []};
    for (final r in allRows) {
      buckets[r.bucket(now)]!.add(r);
    }
    final totalOutstanding = allRows.fold(0.0, (s, r) => s + r.outstanding);
    final customersWithDue = customers.where((c) => c.totalDue > 0).length;

    var rows = allRows.where((r) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return r.customer.name.toLowerCase().contains(q) || r.customer.assignedSalesmanId.toLowerCase().contains(q);
    }).toList();
    if (_sort == _SortBy.amountDesc) rows.sort((a, b) => b.outstanding.compareTo(a.outstanding));

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
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _filterRow(branches, salesmenNames),
                          const SizedBox(height: 14),
                          _statCards(totalOutstanding, customersWithDue, buckets),
                          const SizedBox(height: 20),
                          _distributionCard(buckets, totalOutstanding),
                          const SizedBox(height: 20),
                          _detailsTable(store, rows, now),
                          const SizedBox(height: 16),
                          _footer(store, now),
                        ],
                      ),
                    ),
                  ),
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
                Text('Ageing Receivables', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Outstanding amounts ageing bucket wise', style: TextStyle(fontSize: 10, color: kMuted)),
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

  Widget _statCards(double total, int customersWithDue, Map<String, List<_AgeingRow>> buckets) {
    final cards = [
      (Icons.currency_rupee, kBlue, _rupee.format(total), 'Total Outstanding', 'From $customersWithDue Customers'),
      ...buckets.entries.map((e) {
        final amt = e.value.fold(0.0, (s, r) => s + r.outstanding);
        final pct = total <= 0 ? 0.0 : amt / total * 100;
        return (e.key == 'Not Due' ? Icons.check_circle_outline : Icons.hourglass_bottom, _bucketColors[e.key]!, _rupee.format(amt), e.key, '${pct.toStringAsFixed(2)}% of Total');
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
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(sub, style: const TextStyle(fontSize: 9, color: kMuted))),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _distributionCard(Map<String, List<_AgeingRow>> buckets, double total) {
    return InfoCard(
      children: [
        const Text('Ageing Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: PieChart(PieChartData(centerSpaceRadius: 28, sectionsSpace: 2, sections: buckets.entries.where((e) => e.value.isNotEmpty).map((e) => PieChartSectionData(value: e.value.fold<double>(0, (s, r) => s + r.outstanding), color: _bucketColors[e.key], radius: 22, showTitle: false)).toList())),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buckets.entries.map((e) {
                  final amt = e.value.fold(0.0, (s, r) => s + r.outstanding);
                  final pct = total <= 0 ? 0.0 : amt / total * 100;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _bucketColors[e.key], shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600))),
                        Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 9.5, color: kMuted)),
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

  Widget _detailsTable(AppStore store, List<_AgeingRow> rows, DateTime now) {
    return InfoCard(
      children: [
        const Text('Ageing Receivables Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
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
              onTap: () => setState(() => _sort = _sort == _SortBy.dueDateAsc ? _SortBy.amountDesc : _SortBy.dueDateAsc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sort == _SortBy.amountDesc ? Icons.currency_rupee : Icons.arrow_upward, size: 13, color: kNavy),
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
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No receivables match this search.', style: TextStyle(fontSize: 12, color: kMuted)))
        else
          ...rows.take(30).map((r) {
            final bucket = r.bucket(now);
            final color = _bucketColors[bucket]!;
            final overdueDays = now.difference(r.dueDate).inDays;
            return InkWell(
              onTap: () => _showRowDetail(context, r, bucket, overdueDays),
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
                          Text(r.customer.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                          Text('${r.invoiceNo}  ·  ${r.customer.branch}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                          Text(overdueDays > 0 ? '$overdueDays Days Overdue' : '${-overdueDays} Days Left', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: overdueDays > 0 ? kRed : kGreen)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(r.outstanding), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
                          Text(DateFormat('dd MMM yyyy').format(r.dueDate), style: const TextStyle(fontSize: 8.5, color: kMuted)),
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

  void _showRowDetail(BuildContext context, _AgeingRow r, String bucket, int overdueDays) {
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
              Text(r.customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
              Text('${r.customer.branch}  ·  ${context.read<AppStore>().salesmanDisplayName(r.customer.assignedSalesmanId)}', style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 14),
              _kv('Invoice', r.invoiceNo),
              _kv('Outstanding', _rupee.format(r.outstanding)),
              _kv('Due Date', DateFormat('dd MMM yyyy').format(r.dueDate)),
              _kv('Status', overdueDays > 0 ? '$overdueDays days overdue' : '${-overdueDays} days left'),
              _kv('Ageing Bucket', bucket),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: r.customer, readOnly: true)));
                  },
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('View Full Customer 360', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Manager view is read-only.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
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

  Widget _footer(AppStore store, DateTime now) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(child: Text('Ageing is calculated from each invoice\'s due date, as on ${DateFormat('dd MMM yyyy').format(now)}.', style: const TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(onTap: () => setState(() => store.refreshBusySync()), child: const Icon(Icons.refresh, size: 15, color: kBlue)),
        ],
      ),
    );
  }
}
