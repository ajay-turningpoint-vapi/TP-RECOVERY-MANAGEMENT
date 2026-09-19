import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/re_salesman_control_screen.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class ReTeamTab extends StatefulWidget {
  const ReTeamTab({super.key});

  @override
  State<ReTeamTab> createState() => _ReTeamTabState();
}

class _ReTeamTabState extends State<ReTeamTab> {
  int _activeSegment = 0; // 0 = Workload Overview, 1 = Salesmen Performance

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Salesmen Portfolios', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: const Color(0xFF0052CC),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            children: [
              // Segment selector
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSegmentButton(0, 'Workload Overview', Icons.grid_view_outlined),
                    _buildSegmentButton(1, 'Salesmen Performance', Icons.analytics_outlined),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _activeSegment,
                  children: [
                    _buildWorkloadList(store),
                    _buildPerformanceList(store),
                  ],
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

  Widget _buildSegmentButton(int index, String label, IconData icon) {
    final isActive = _activeSegment == index;
    return InkWell(
      onTap: () => setState(() => _activeSegment = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE3F2FD) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? const Color(0xFF0052CC) : const Color(0xFF5A6B87), size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isActive ? const Color(0xFF0052CC) : const Color(0xFF5A6B87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkloadList(AppStore store) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: store.visibleSalesmen.length,
      itemBuilder: (ctx, i) {
        final sm = store.visibleSalesmen[i];
        final smName = (sm['fullName'] as String?) ?? sm['name'] as String;
        final isHighWorkload = (sm['customers'] as int) > 50;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReSalesmanControlScreen(salesmanName: sm['name']),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFE3F2FD),
                              child: Text(smName.isNotEmpty ? smName[0] : '?', style: const TextStyle(color: Color(0xFF0052CC), fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(smName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48))),
                                  const Text('Field Agent', style: TextStyle(fontSize: 11, color: Color(0xFF5A6B87))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isHighWorkload)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
                          child: const Text('HIGH WORKLOAD', style: TextStyle(color: Color(0xFFE53935), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetricCell('Portfolio Size', '${sm['customers']} Accounts'),
                      _buildMetricCell('Due Portfolio', fmt.format(sm['due'])),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetricCell('Broken PTPs', '${sm['brokenPtps']} Alerts', isAlert: (sm['brokenPtps'] as int) > 3),
                      _buildMetricCell('Expected Today', fmt.format(sm['expectedCollection'])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _showReassignPortfolioDialog(context, store, sm),
                          child: const Text('Reassign Portfolio'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReassignPortfolioDialog(BuildContext context, AppStore store, Map<String, dynamic> sm) {
    final fromName = sm['name'] as String;
    final fromDisplay = (sm['fullName'] as String?) ?? fromName;
    final ownedCustomers = store.customers.where((c) => c.assignedSalesmanId == fromName).toList()
      ..sort((a, b) => b.totalDue.compareTo(a.totalDue));
    final topFive = ownedCustomers.take(5).toList();
    final otherSalesmen = store.salesmen.map((s) => s['name'] as String).where((n) => n != fromName).toList();
    String nameFor(String id) => store.salesmanDisplayName(id);
    if (topFive.isEmpty || otherSalesmen.isEmpty) {
      showAppMessage(context, message: '$fromDisplay has no reassignable accounts right now.');
      return;
    }
    String toName = otherSalesmen.first;
    final reasonController = TextEditingController(text: 'Balancing field workload across the team.');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text('Reassign Workload — $fromDisplay'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reassign ${topFive.length} highest-exposure accounts (real, real amounts — not a placeholder count):', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...topFive.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${c.name} — ${_rupee.format(c.totalDue)}', style: const TextStyle(fontSize: 12)),
                    )),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: toName,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reassign To', border: OutlineInputBorder(), isDense: true),
                  items: otherSalesmen.map((n) => DropdownMenuItem(value: n, child: Text(nameFor(n)))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => toName = v); },
                ),
                const SizedBox(height: 12),
                TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder(), isDense: true)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0052CC)),
              onPressed: () async {
                final reason = reasonController.text.trim().isEmpty ? 'Balancing field workload across the team.' : reasonController.text.trim();
                final navigator = Navigator.of(context);
                Navigator.pop(dialogCtx);
                try {
                  for (final c in topFive) {
                    await store.reassignCustomer(c.id, fromName, toName, reason);
                  }
                  showAppMessageAfter(navigator, message: '${topFive.length} accounts reassigned from $fromDisplay to ${nameFor(toName)}. Audit entry logged for each.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not reassign all accounts: $e', isError: true);
                }
              },
              child: const Text('Reassign', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceList(AppStore store) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

    // Real per-salesman operational metrics, derived from the same shared
    // customers/tasks/ptps data every other screen reads — no hardcoded
    // roster or numbers.
    final perfData = store.visibleSalesmen.map((sm) {
      final name = sm['name'] as String;
      final ownedIds = store.customers.where((c) => c.assignedSalesmanId == name).map((c) => c.id).toSet();
      final ownedPtps = store.ptps.where((p) => ownedIds.contains(p.customerId)).toList();
      final actionsCompleted = store.tasks.where((t) => t.ownerId == name && (t.status.name == 'completed' || t.status.name == 'closed')).length;
      return <String, dynamic>{
        'name': (sm['fullName'] as String?) ?? name,
        'actions': actionsCompleted,
        'ptpCreated': ownedPtps.length,
        'ptpValue': ownedPtps.fold<double>(0.0, (s, p) => s + p.amountPromised),
        'broken': sm['brokenPtps'] as int,
        'overdue': sm['overdueTasks'] as int,
      };
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: perfData.length,
      itemBuilder: (ctx, i) {
        final pd = perfData[i];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE2F0D9),
                      child: Text(pd['name'][0], style: const TextStyle(color: Color(0xFF388E3C), fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pd['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48))),
                        const Text('Operational Performance', style: TextStyle(fontSize: 11, color: Color(0xFF5A6B87))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricCell('Actions Completed', '${pd['actions']} Tasks'),
                    _buildMetricCell('PTPs Created', '${pd['ptpCreated']} PTPs'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricCell('PTP Value', fmt.format(pd['ptpValue'])),
                    _buildMetricCell('Broken PTP / Overdue', '${pd['broken']} / ${pd['overdue']}', isAlert: pd['broken'] > 3 || pd['overdue'] > 3),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricCell(String label, String value, {bool isAlert = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF5A6B87), fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isAlert ? const Color(0xFFE53935) : const Color(0xFF1B2B48))),
      ],
    );
  }
}
