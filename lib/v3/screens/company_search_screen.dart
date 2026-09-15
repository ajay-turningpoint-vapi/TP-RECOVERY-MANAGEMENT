import 'package:flutter/material.dart';
import 'package:salesman_mobile/v2/utils/initials.dart';
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

class CompanySearchScreen extends StatefulWidget {
  const CompanySearchScreen({super.key});

  @override
  State<CompanySearchScreen> createState() => _CompanySearchScreenState();
}

class _CompanySearchScreenState extends State<CompanySearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String get _branchFilter => context.read<AppStore>().branchFilter;
  String _stateFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    List<Customer> results = store.searchCustomers(_query);
    if (!store.isAllBranches) results = results.where((c) => c.branch == store.branchFilter).toList();
        if (_stateFilter != 'All') results = results.where((c) => c.currentRecoveryState == _stateFilter).toList();

    final branches = store.branchOptions;
    final states = ['All', ...{for (final c in store.customers) c.currentRecoveryState}];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search customer, BUSY code, salesman, branch…',
            border: InputBorder.none,
            hintStyle: TextStyle(fontSize: 14, color: _muted),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _filterDropdown('Branch', _branchFilter, branches, (v) { if (v != null) context.read<AppStore>().setBranchFilter(v); setState(() {}); }),
                    const SizedBox(width: 8),
                    _filterDropdown('State', _stateFilter, states, (v) => setState(() => _stateFilter = v!)),
                  ],
                ),
              ),
              const Divider(height: 1, color: _border),
              Expanded(
                child: _query.isEmpty
                    ? const Center(child: Text('Type to search company-wide records.', style: TextStyle(color: _muted)))
                    : results.isEmpty
                        ? const Center(child: Text('No matches found.', style: TextStyle(color: _muted)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: results.length,
                            itemBuilder: (ctx, i) {
                              final c = results[i];
                              return GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                                  child: Row(
                                    children: [
                                      CircleAvatar(radius: 18, backgroundColor: const Color(0xFFE3F2FD), child: Text(avatarInitials(c.name), style: const TextStyle(color: _blue, fontWeight: FontWeight.bold, fontSize: 12))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                                            Text('${c.branch} · ${store.salesmanDisplayName(c.assignedSalesmanId)}', style: const TextStyle(fontSize: 11, color: _muted)),
                                          ],
                                        ),
                                      ),
                                      Text(fmt.format(c.totalDue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFDC2626))),
                                    ],
                                  ),
                                ),
                              );
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

  Widget _filterDropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text('$label: $o'))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
