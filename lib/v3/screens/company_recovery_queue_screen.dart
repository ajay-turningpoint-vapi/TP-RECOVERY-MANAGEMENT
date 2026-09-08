import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _blue = Color(0xFF2563EB);

class CompanyRecoveryQueueScreen extends StatefulWidget {
  // False (default): the existing "who's overdue and needs recovery action"
  // queue — filtered and sorted by totalDue, matching the dashboard's
  // "Total Overdue" card exactly. True: the dashboard's "Total Outstanding"
  // card population instead (every customer with a live balance, not just
  // an overdue one) — same screen, filtered/sorted/displayed by
  // totalOutstanding instead so the list actually matches what that card
  // claims rather than silently reusing the overdue-only population.
  final bool showOutstanding;
  const CompanyRecoveryQueueScreen({super.key, this.showOutstanding = false});

  @override
  State<CompanyRecoveryQueueScreen> createState() => _CompanyRecoveryQueueScreenState();
}

enum _QueueSort { priority, nameAsc, nameDesc, amountDesc, amountAsc }

class _CompanyRecoveryQueueScreenState extends State<CompanyRecoveryQueueScreen> {
  String _salesmanFilter = 'All';
  String _branchFilter = 'All';
  String _quickFilter = 'All'; // All, Broken PTP, Escalated, No Owner, No Next Action
  String _query = '';
  _QueueSort _sort = _QueueSort.priority;

  // Priority per spec §14
  int _priorityRank(Customer c, AppStore store) {
    if (c.escalationLevel == 'L4') return 0;
    if (store.brokenPtps.any((p) => p.customerId == c.id)) return 1;
    if (c.ownerMappingRequired) return 2;
    if (!c.hasValidNextAction) return 3;
    if (c.escalationLevel == 'L3' || c.escalationLevel == 'L2') return 4;
    if (c.primaryNextAction.toLowerCase().contains('ptp')) return 5;
    if (c.oldestOverdueDays > 30) return 6;
    return 7;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    List<Customer> queue = store.customers.where((c) => widget.showOutstanding ? c.totalOutstanding > 0 : c.totalDue > 0).toList();
    if (_salesmanFilter != 'All') queue = queue.where((c) => c.assignedSalesmanId == _salesmanFilter).toList();
    if (_branchFilter != 'All') queue = queue.where((c) => c.branch == _branchFilter).toList();
    if (_quickFilter == 'Broken PTP') {
      final ids = store.brokenPtps.map((p) => p.customerId).toSet();
      queue = queue.where((c) => ids.contains(c.id)).toList();
    } else if (_quickFilter == 'Escalated') {
      queue = queue.where((c) => c.escalationLevel != 'none').toList();
    } else if (_quickFilter == 'No Owner') {
      queue = queue.where((c) => c.ownerMappingRequired).toList();
    } else if (_quickFilter == 'No Next Action') {
      queue = queue.where((c) => !c.hasValidNextAction).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      queue = queue.where((c) {
        return c.name.toLowerCase().contains(q) ||
            store.salesmanDisplayName(c.assignedSalesmanId).toLowerCase().contains(q) ||
            c.branch.toLowerCase().contains(q) ||
            c.contactNumber.contains(q);
      }).toList();
    }
    switch (_sort) {
      case _QueueSort.priority:
        queue.sort((a, b) => _priorityRank(a, store).compareTo(_priorityRank(b, store)));
        break;
      case _QueueSort.nameAsc:
        queue.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _QueueSort.nameDesc:
        queue.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _QueueSort.amountDesc:
        queue.sort((a, b) => (widget.showOutstanding ? b.totalOutstanding.compareTo(a.totalOutstanding) : b.totalDue.compareTo(a.totalDue)));
        break;
      case _QueueSort.amountAsc:
        queue.sort((a, b) => (widget.showOutstanding ? a.totalOutstanding.compareTo(b.totalOutstanding) : a.totalDue.compareTo(b.totalDue)));
        break;
    }

    final branches = ['All', ...{for (final c in store.customers) c.branch}];
    final salesmen = ['All', ...store.salesmen.map((s) => s['name'] as String)];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(widget.showOutstanding ? 'Total Outstanding' : 'Company Recovery Queue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _dark)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: ['All', 'Broken PTP', 'Escalated', 'No Owner', 'No Next Action']
                            .map((f) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(f, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    selected: _quickFilter == f,
                                    selectedColor: _blue.withOpacity(0.15),
                                    labelStyle: TextStyle(color: _quickFilter == f ? _blue : _muted),
                                    onSelected: (_) => setState(() => _quickFilter = f),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                              child: _dropdown('Salesman', _salesmanFilter, salesmen, (v) => setState(() => _salesmanFilter = v!),
                                  displayFor: (o) => o == 'All' ? o : store.salesmanDisplayName(o))),
                          const SizedBox(width: 8),
                          Expanded(child: _dropdown('Branch', _branchFilter, branches, (v) => setState(() => _branchFilter = v!))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
                              child: Row(
                                children: [
                                  const Icon(Icons.search, size: 16, color: _muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      onChanged: (v) => setState(() => _query = v),
                                      style: const TextStyle(fontSize: 12, color: _dark),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: 'Search by name, salesman, branch, mobile',
                                        hintStyle: TextStyle(fontSize: 11.5, color: _muted),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _showSortSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
                              child: const Row(
                                children: [
                                  Icon(Icons.swap_vert, size: 15, color: _blue),
                                  SizedBox(width: 4),
                                  Text('Sort by', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark)),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${queue.length} customers · one row per customer (invoice detail available underneath)', style: const TextStyle(fontSize: 11, color: _muted)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: queue.length,
                  itemBuilder: (ctx, i) {
                    final c = queue[i];
                    return _queueRow(context, c, i + 1, fmt, store);
                  },
                ),
              ),
            ],
          );
          if (constraints.maxWidth <= 600) return content;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: content,
            ),
          );
        },
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sortOption('Priority (Default)', _QueueSort.priority),
            _sortOption('Name: A to Z', _QueueSort.nameAsc),
            _sortOption('Name: Z to A', _QueueSort.nameDesc),
            _sortOption('Amount: High to Low', _QueueSort.amountDesc),
            _sortOption('Amount: Low to High', _QueueSort.amountAsc),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(String label, _QueueSort order) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: _sort == order ? const Icon(Icons.check, color: _blue) : null,
      onTap: () {
        setState(() => _sort = order);
        Navigator.pop(context);
      },
    );
  }

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged,
      {String Function(String)? displayFor}) {
    String text(String o) => displayFor != null ? displayFor(o) : o;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text('$label: ${text(o)}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _queueRow(BuildContext context, Customer c, int priority, NumberFormat fmt, AppStore store) {
    String state = c.currentRecoveryState;
    Color stateColor = const Color(0xFF64748B);
    if (c.escalationLevel == 'L4') {
      state = 'L4 — Management Attention';
      stateColor = const Color(0xFF991B1B);
    } else if (store.brokenPtps.any((p) => p.customerId == c.id)) {
      state = 'Broken PTP';
      stateColor = const Color(0xFFDC2626);
    } else if (c.ownerMappingRequired) {
      state = 'Owner Mapping Required';
      stateColor = const Color(0xFFEA580C);
    } else if (!c.hasValidNextAction) {
      state = 'No Valid Next Action';
      stateColor = const Color(0xFF7C3AED);
    } else if (c.escalationLevel != 'none') {
      state = '${c.escalationLevel} Escalation';
      stateColor = const Color(0xFFEA580C);
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(6)),
              child: Text('$priority', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _muted)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                  const SizedBox(height: 2),
                  Text(
                    c.ownerMappingRequired ? 'Unmapped · ${c.branch}' : '${store.salesmanDisplayName(c.assignedSalesmanId)} · ${c.branch}',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: stateColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(state, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: stateColor)),
                  ),
                ],
              ),
            ),
            Text(fmt.format(widget.showOutstanding ? c.totalOutstanding : c.totalDue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFDC2626))),
          ],
        ),
      ),
    );
  }
}
