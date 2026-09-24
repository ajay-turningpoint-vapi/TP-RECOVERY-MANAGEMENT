import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_list_screen.dart';
import 'package:salesman_mobile/v3/screens/report_detail_screens.dart' show SalesmanScoreDetailScreen;
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum _SortBy { overdueDesc, overdueAsc, keptDesc, keptAsc, nameAsc }

const _sortLabels = {
  _SortBy.overdueDesc: 'Overdue: High to Low',
  _SortBy.overdueAsc: 'Overdue: Low to High',
  _SortBy.keptDesc: 'Kept %: High to Low',
  _SortBy.keptAsc: 'Kept %: Low to High',
  _SortBy.nameAsc: 'Name: A to Z',
};

/// The real "Salesmen Performance" list behind the RE dashboard's "View
/// All" — the dashboard card only ever shows a handful with "Load More".
/// (Previously that button was a copy-paste bug that opened
/// NeedsAttentionScreen instead of any salesmen list at all.)
class ReSalesmenListScreen extends StatefulWidget {
  const ReSalesmenListScreen({super.key});

  @override
  State<ReSalesmenListScreen> createState() => _ReSalesmenListScreenState();
}

class _ReSalesmenListScreenState extends State<ReSalesmenListScreen> {
  String _query = '';
  _SortBy _sort = _SortBy.overdueDesc;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;

    // Same "nothing to chase" convention as the dashboard card and the
    // manager's equivalent report — a ₹0 overdue row is just noise here.
    var salesmen = store.visibleSalesmen.where((s) => ((s['totalOverdue'] as num?) ?? 0) > 0).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      salesmen = salesmen.where((s) => ((s['fullName'] as String?) ?? (s['name'] as String? ?? '')).toLowerCase().contains(q)).toList();
    }
    switch (_sort) {
      case _SortBy.overdueDesc:
        salesmen.sort((a, b) => (b['totalOverdue'] as num).compareTo(a['totalOverdue'] as num));
        break;
      case _SortBy.overdueAsc:
        salesmen.sort((a, b) => (a['totalOverdue'] as num).compareTo(b['totalOverdue'] as num));
        break;
      case _SortBy.keptDesc:
        salesmen.sort((a, b) => (b['ptpKeptPercent'] as int).compareTo(a['ptpKeptPercent'] as int));
        break;
      case _SortBy.keptAsc:
        salesmen.sort((a, b) => (a['ptpKeptPercent'] as int).compareTo(b['ptpKeptPercent'] as int));
        break;
      case _SortBy.nameAsc:
        salesmen.sort((a, b) => ((a['fullName'] as String?) ?? a['name'] as String).compareTo((b['fullName'] as String?) ?? b['name'] as String));
        break;
    }

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                children: [
                  _searchAndFilterRow(store, branches),
                  const SizedBox(height: 12),
                  Text('${salesmen.length} salesmen', style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  if (salesmen.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No salesmen match this search.', style: TextStyle(fontSize: 13, color: kMuted))),
                    )
                  else
                    ...salesmen.map((s) => _salesmanCard(context, s)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: kNavy), tooltip: 'Back', onPressed: () => Navigator.pop(context)),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Salesmen Performance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Search and filter the full team', style: TextStyle(fontSize: 10.5, color: kMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchAndFilterRow(AppStore store, List<String> branches) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 12.5, color: kDark),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, size: 18, color: kMuted),
              hintText: 'Search salesman by name...',
              hintStyle: const TextStyle(fontSize: 12, color: kMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBlue)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dropdownPill(Icons.apartment_outlined, kBlue, store.branchFilter, branches, (v) {
                store.setBranchFilter(v);
                setState(() {});
              }),
            ),
            const SizedBox(width: 10),
            Expanded(child: _sortDropdown()),
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
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: Row(
        children: [
          const Icon(Icons.sort, size: 14, color: kPurple),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_SortBy>(
                value: _sort,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 15, color: kMuted),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark),
                items: _sortLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _sort = v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesmanCard(BuildContext context, Map<String, dynamic> s) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    final branch = (s['branch'] as String?) ?? 'Turning Point';
    final totalOverdue = (s['totalOverdue'] as num).toDouble();
    final dueToday = (s['dueTodayPtps'] as num).toDouble();
    final taskCompletionRate = s['taskCompletionRate'] as int;
    final kept = s['ptpKeptPercent'] as int;
    final keptColor = kept >= 75 ? kGreen : (kept >= 60 ? kOrange : kRed);
    final salesmanId = s['name'] as String;
    final customerCount = s['customers'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesmanScoreDetailScreen(salesman: s, store: context.read<AppStore>()))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 18, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 12, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: kDark)),
                          Text(branch, style: const TextStyle(fontSize: 10.5, color: kMuted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: kMuted),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: kBorder),
                const SizedBox(height: 12),
                // A single evenly-spaced 2x2 grid — every cell is the same
                // Expanded width whether it's the tappable Customers chip
                // or a plain figure, so nothing balloons out with dead
                // whitespace next to it.
                Row(
                  children: [
                    Expanded(child: _customersStat(context, salesmanId, name, customerCount)),
                    const SizedBox(width: 10),
                    Expanded(child: _stat('Total Overdue', _rupee.format(totalOverdue), kDark)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _stat('Due Today', _rupee.format(dueToday), const Color(0xFFEA580C))),
                    const SizedBox(width: 10),
                    Expanded(child: _stat('Tasks', '$taskCompletionRate%', kDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _stat('Kept', '$kept%', keptColor)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tapping this specifically opens that salesman's customers, reusing
  /// the existing Customers list screen rather than building a new one —
  /// nested inside the card's own InkWell (which opens the score detail),
  /// so this small pill intercepts its own taps correctly.
  Widget _customersStat(BuildContext context, String salesmanId, String name, int count) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          final store = context.read<AppStore>();
          final owned = store.customers.where((c) => c.assignedSalesmanId == salesmanId).toList()..sort((a, b) => b.totalDue.compareTo(a.totalDue));
          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerListScreen(title: '$name — Customers', customers: owned, sortControlsView: true)));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: kBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 12, color: kBlue),
                  const SizedBox(width: 4),
                  const Expanded(child: Text('Customers', style: TextStyle(fontSize: 9.5, color: kBlue, fontWeight: FontWeight.w700))),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: kBlue),
                ],
              ),
              const SizedBox(height: 3),
              Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kBlue)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: color))),
        ],
      ),
    );
  }
}
