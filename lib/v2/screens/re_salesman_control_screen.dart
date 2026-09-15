import 'package:flutter/material.dart';
import 'package:salesman_mobile/v2/utils/initials.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:intl/intl.dart';

class ReSalesmanControlScreen extends StatelessWidget {
  final String salesmanName;

  const ReSalesmanControlScreen({super.key, required this.salesmanName});

  Color _getBadgeBgColor(String priority) {
    if (priority == 'High') return const Color(0xFFFFEBEE);
    if (priority == 'Medium') return const Color(0xFFFFF3E0);
    return const Color(0xFFE8F5E9);
  }

  Color _getBadgeColor(String priority) {
    if (priority == 'High') return const Color(0xFFE53935);
    if (priority == 'Medium') return const Color(0xFFF57C00);
    return const Color(0xFF388E3C);
  }

  String _getPriority(double due) {
    if (due >= 100000) return 'High';
    if (due >= 50000) return 'Medium';
    return 'Low';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

    // Dynamic filtering based on assignedSalesmanId
    final assignedCustomers = store.customers.where((c) => c.assignedSalesmanId.toLowerCase() == salesmanName.toLowerCase()).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text('$salesmanName\'s Portfolio', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: const Color(0xFF0052CC),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = _buildBody(context, assignedCustomers, fmt);
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

  Widget _buildBody(BuildContext context, List<Customer> assignedCustomers, NumberFormat fmt) {
    return Column(
        children: [
          // Top Stats Summary
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryStat('${assignedCustomers.length}', 'Assigned Clients'),
                const VerticalDivider(width: 1),
                _buildSummaryStat(
                  fmt.format(assignedCustomers.fold<double>(0.0, (sum, c) => sum + c.totalDue)),
                  'Total Outstanding',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Customer List header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Text('CUSTOMER PORTFOLIO',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5A6B87), letterSpacing: 0.5)),
                const Spacer(),
                Text('${assignedCustomers.length} Records', style: const TextStyle(fontSize: 11, color: Color(0xFF5A6B87))),
              ],
            ),
          ),
          // List
          Expanded(
            child: assignedCustomers.isEmpty
                ? const Center(child: Text('No customers assigned to this agent.', style: TextStyle(color: Color(0xFF5A6B87))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: assignedCustomers.length,
                    itemBuilder: (ctx, i) {
                      final c = assignedCustomers[i];
                      final priority = _getPriority(c.totalDue);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.withOpacity(0.15)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Customer360Screen(customer: c),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFFE3F2FD),
                                  child: Text(avatarInitials(c.name), style: const TextStyle(color: Color(0xFF0052CC), fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                              child: Text(c.name,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48)),
                                                  overflow: TextOverflow.ellipsis)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: _getBadgeBgColor(priority), borderRadius: BorderRadius.circular(4)),
                                            child: Text(priority, style: TextStyle(color: _getBadgeColor(priority), fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'State: ${c.currentRecoveryState}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF5A6B87)),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('DUE', style: TextStyle(fontSize: 9, color: Color(0xFF5A6B87), fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(fmt.format(c.totalDue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
  }

  Widget _buildSummaryStat(String val, String label) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B2B48))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF5A6B87))),
      ],
    );
  }
}
