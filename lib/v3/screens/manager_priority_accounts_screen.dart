import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum _AccountTab { priority, overdue, brokenPtp, noFollowUp }

/// Status shown as a row badge — one dominant reason this customer needs
/// attention, derived from real store state (never fabricated).
String _statusFor(Customer c, AppStore store, Set<String> brokenIds) {
  if (brokenIds.contains(c.id)) return 'Broken PTP';
  if (store.daysSinceLastFollowUp(c) >= AppStore.noFollowUpThresholdDays) return 'No Follow-Up';
  if (c.creditHealthBand == 'Critical' || c.creditHealthBand == 'High' || c.escalationLevel == 'L2' || c.escalationLevel == 'L3' || c.escalationLevel == 'L4') return 'High Risk';
  return 'Overdue';
}

Color _statusColor(String status) {
  switch (status) {
    case 'Broken PTP':
      return kPurple;
    case 'High Risk':
      return kOrange;
    case 'No Follow-Up':
      return const Color(0xFFCA8A04);
    default:
      return kRed;
  }
}

/// Overall priority bucket — combines status severity with how overdue the
/// account is, real per-customer signals only.
String _priorityBucket(Customer c, String status) {
  if (status == 'Broken PTP' || c.escalationLevel == 'L4' || c.oldestOverdueDays >= 90) return 'Critical';
  if (status == 'High Risk' || c.oldestOverdueDays >= 60) return 'High';
  if (status == 'No Follow-Up' || c.oldestOverdueDays >= 30) return 'Medium';
  return 'Low';
}

Color _bucketColor(String bucket) {
  switch (bucket) {
    case 'Critical':
      return kRed;
    case 'High':
      return kOrange;
    case 'Medium':
      return kBlue;
    default:
      return kGreen;
  }
}

/// Manager's Priority Accounts — high-priority customer accounts needing
/// attention, tabbed by Priority/Overdue/Broken PTP/No Follow-Up, with a
/// searchable/sortable table and a view-only account detail sheet.
class ManagerPriorityAccountsScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerPriorityAccountsScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerPriorityAccountsScreen> createState() => _ManagerPriorityAccountsScreenState();
}

class _ManagerPriorityAccountsScreenState extends State<ManagerPriorityAccountsScreen> {
  late String _branch;

  @override
  void initState() {
    super.initState();
    _branch = widget.initialBranch;
  }
  String _salesman = 'All Salesmen';
  String _query = '';
  _AccountTab _tab = _AccountTab.priority;

  static const _bucketRank = {'Critical': 0, 'High': 1, 'Medium': 2, 'Low': 3};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = ['All Branches', ...{for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}];
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];
    final brokenIds = store.brokenPtps.map((p) => p.customerId).toSet();

    var customers = store.customers.where((c) => c.totalDue > 0 && (_branch == 'All Branches' || c.branch == _branch) && (_salesman == 'All Salesmen' || c.assignedSalesmanId == _salesman)).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      customers = customers.where((c) => c.name.toLowerCase().contains(q) || c.id.toLowerCase().contains(q) || c.branch.toLowerCase().contains(q)).toList();
    }

    final rows = customers.map((c) {
      final status = _statusFor(c, store, brokenIds);
      final bucket = _priorityBucket(c, status);
      final days = store.daysSinceLastFollowUp(c);
      return (c, status, bucket, days);
    }).toList();

    List<(Customer, String, String, int)> filtered;
    switch (_tab) {
      case _AccountTab.priority:
        filtered = rows.toList()..sort((a, b) {
          final r = _bucketRank[a.$3]!.compareTo(_bucketRank[b.$3]!);
          return r != 0 ? r : b.$1.totalDue.compareTo(a.$1.totalDue);
        });
        break;
      case _AccountTab.overdue:
        filtered = rows.where((r) => r.$1.oldestOverdueDays > 0).toList()..sort((a, b) => b.$1.oldestOverdueDays.compareTo(a.$1.oldestOverdueDays));
        break;
      case _AccountTab.brokenPtp:
        filtered = rows.where((r) => r.$2 == 'Broken PTP').toList()..sort((a, b) => b.$1.totalDue.compareTo(a.$1.totalDue));
        break;
      case _AccountTab.noFollowUp:
        filtered = rows.where((r) => r.$2 == 'No Follow-Up').toList()..sort((a, b) => b.$4.compareTo(a.$4));
        break;
    }

    final totalDue = filtered.fold(0.0, (s, r) => s + r.$1.totalDue);
    final totalOutstanding = filtered.fold(0.0, (s, r) => s + r.$1.totalOutstanding);
    final totalReceived = filtered.fold(0.0, (s, r) => s + (r.$1.totalOutstanding - r.$1.totalDue).clamp(0, double.infinity));
    // Real, always-non-negative overdue exposure: totalDue summed only
    // across accounts that are genuinely overdue (oldestOverdueDays > 0),
    // not "Total Due minus all-time collected" (which mixes two unrelated
    // figures and can go negative once a portfolio has collected more than
    // its current outstanding).
    final overdueExposure = filtered.where((r) => r.$1.oldestOverdueDays > 0).fold(0.0, (s, r) => s + r.$1.totalDue);
    final avgDays = filtered.isEmpty ? 0 : (filtered.fold(0, (s, r) => s + r.$1.oldestOverdueDays) / filtered.length).round();

    final buckets = <String, List<(Customer, String, String, int)>>{'Critical': [], 'High': [], 'Medium': [], 'Low': []};
    for (final r in filtered) {
      buckets[r.$3]!.add(r);
    }

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _filterRow(branches, salesmenNames),
                      const SizedBox(height: 14),
                      _statCards(filtered.length, totalDue, totalReceived, overdueExposure),
                      const SizedBox(height: 16),
                      _tabRow(),
                      const SizedBox(height: 10),
                      _searchExportRow(context, store),
                      const SizedBox(height: 10),
                      _table(context, filtered, store, totalOutstanding, totalDue, avgDays),
                      const SizedBox(height: 16),
                      _priorityDistribution(context, buckets, filtered.length),
                      const SizedBox(height: 16),
                      _footer(context, store),
                    ],
                  ),
                ),
              ],
            );
            if (constraints.maxWidth <= 700) return content;
            return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: content));
          },
        ),
      ),
    );
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
                Text('Priority Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kNavy)),
                Text('High-priority customer accounts needing attention', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _snack(context, 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.')),
          const SizedBox(width: 8),
          _headerIcon(Icons.filter_alt_outlined, () => _snack(context, 'Use the Branch/Salesman filters and tabs below to scope this list.')),
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
                items: options.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) { if (v != null) onChanged(v); },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCards(int count, double totalDue, double totalReceived, double overdue) {
    final cards = [
      (Icons.groups_outlined, kPurple, '$count', 'Total Accounts', 'Accounts'),
      (Icons.currency_rupee, kBlue, _rupee.format(totalDue), 'Total Due', ''),
      (Icons.swap_vert, kGreen, _rupee.format(totalReceived), 'Total Received', ''),
      (Icons.warning_amber_rounded, kRed, _rupee.format(overdue), 'Overdue', ''),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (icon, color, value, label, sub) = cards[i];
          return Container(
            width: 130,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.15))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 16),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color))),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kDark, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: kMuted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabRow() {
    final tabs = [
      (_AccountTab.priority, 'Priority'),
      (_AccountTab.overdue, 'Overdue'),
      (_AccountTab.brokenPtp, 'Broken PTP'),
      (_AccountTab.noFollowUp, 'No Follow-Up'),
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

  Widget _searchExportRow(BuildContext context, AppStore store) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12), border: InputBorder.none, hintText: 'Search by customer name, ID or city', hintStyle: TextStyle(fontSize: 11.5, color: kMuted)),
                  ),
                ),
                const Icon(Icons.search, size: 18, color: kMuted),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () {
            store.incrementReportsGenerated();
            _snack(context, 'Priority Accounts report exported.');
          },
          icon: const Icon(Icons.download, size: 15),
          label: const Text('Export', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, List<(Customer, String, String, int)> rows, AppStore store, double totalOutstanding, double totalDue, int avgDays) {
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
                    SizedBox(width: 150, child: Text('Customer', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 90, child: Text('City / Branch', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 90, child: Text('Total Outstanding', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 80, child: Text('Total Due', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 60, child: Text('Oldest Overdue', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 80, child: Text('Last Follow-Up', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 80, child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: 90, child: Text('Priority Due', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                if (rows.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('No priority accounts match this search.', style: TextStyle(fontSize: 12, color: kMuted))))
                else
                  ...rows.map((r) => _accountRow(context, r.$1, r.$2, r.$4)),
                if (rows.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                  Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total / Avg.', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kNavy)),
                            Text('${rows.length} Accounts', style: const TextStyle(fontSize: 10, color: kMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 90),
                      SizedBox(width: 90, child: Text(_rupee.format(totalOutstanding), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kBlue))),
                      SizedBox(width: 80, child: Text(_rupee.format(totalDue), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark))),
                      SizedBox(width: 60, child: Text('$avgDays', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kOrange))),
                      const SizedBox(width: 80),
                      const SizedBox(width: 80),
                      SizedBox(width: 90, child: Text(_rupee.format(totalDue), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kRed))),
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

  Widget _accountRow(BuildContext context, Customer c, String status, int days) {
    final color = _statusColor(status);
    return InkWell(
      onTap: () => _showAccountDetail(context, c, status, days),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: Row(
                children: [
                  CircleAvatar(radius: 15, backgroundColor: avatarColorFor(c.name).withOpacity(0.15), child: Text(initialsFor(c.name), style: TextStyle(color: avatarColorFor(c.name), fontSize: 10.5, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                        Text(c.branch, style: const TextStyle(fontSize: 9.5, color: kMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.branch, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600)),
                  const Text('Branch', style: TextStyle(fontSize: 9, color: kMuted)),
                ],
              ),
            ),
            SizedBox(width: 90, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(c.totalOutstanding), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark)))),
            SizedBox(width: 80, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(c.totalDue), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark)))),
            SizedBox(width: 60, child: Text('${c.oldestOverdueDays}', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c.oldestOverdueDays >= 60 ? kRed : kOrange))),
            SizedBox(
              width: 80,
              child: Text(
                days >= AppStore.noFollowUpThresholdDays ? 'No Follow-Up' : DateFormat('dd MMM yyyy').format(DateTime.now().subtract(Duration(days: days))),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: kMuted),
              ),
            ),
            SizedBox(
              width: 80,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(status, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color)),
                ),
              ),
            ),
            SizedBox(width: 90, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(c.totalDue), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kRed)))),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, size: 15, color: kMuted),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _priorityDistribution(BuildContext context, Map<String, List<(Customer, String, String, int)>> buckets, int total) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Priority Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
                  Text('(By Account Count)', style: TextStyle(fontSize: 10, color: kMuted)),
                ],
              ),
            ),
            if (total > 0)
              GestureDetector(
                onTap: () => _showDistributionDetail(context, buckets, total),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View Details', style: TextStyle(color: kBlue, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    Icon(Icons.chevron_right, size: 15, color: kBlue),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: buckets.entries.map((e) {
            final count = e.value.length;
            final pct = total <= 0 ? 0.0 : (count / total * 100);
            final color = _bucketColor(e.key);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                  child: Column(
                    children: [
                      Text(e.key, textAlign: TextAlign.center, maxLines: 1, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kDark)),
                      const SizedBox(height: 2),
                      Text('${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showDistributionDetail(BuildContext context, Map<String, List<(Customer, String, String, int)>> buckets, int total) {
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
              const Text('Priority Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
              const SizedBox(height: 12),
              ...buckets.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12.5, color: kDark, fontWeight: FontWeight.w600))),
                        Text('${e.value.length} of $total', style: const TextStyle(fontSize: 12.5, color: kMuted)),
                      ],
                    ),
                  )),
              const SizedBox(height: 4),
              const Text('Manager view is read-only — reassignment and instruction actions are taken by the Recovery Executive.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountDetail(BuildContext context, Customer c, String status, int days) {
    final color = _statusColor(status);
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
                  CircleAvatar(radius: 20, backgroundColor: avatarColorFor(c.name).withOpacity(0.15), child: Text(initialsFor(c.name), style: TextStyle(color: avatarColorFor(c.name), fontSize: 13, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                        Text('${c.branch} Branch', style: const TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _kv('Total Outstanding', _rupee.format(c.totalOutstanding)),
              _kv('Total Due', _rupee.format(c.totalDue)),
              _kv('Oldest Overdue', '${c.oldestOverdueDays} days'),
              _kv('Days Since Last Follow-Up', '$days days'),
              _kv('Salesman', context.read<AppStore>().salesmanDisplayName(c.assignedSalesmanId)),
              _kv('Priority', _priorityBucket(c, status)),
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
              const Text('Manager view is read-only — reassignment and instruction actions are taken by the Recovery Executive.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
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
                const Text('Priority accounts are real-time and based on the data available as on selected date.', style: TextStyle(fontSize: 10.5, color: kDark)),
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
