import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/escalation_case.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/widgets/data_loading.dart' show DataLoadingBar;

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _blue = Color(0xFF2563EB);

class EscalationsScreen extends StatefulWidget {
  // 0=L2, 1=L3, 2=L4, 3=Resolved — lets a dashboard tile ("L3 Escalations",
  // "L4 Management Attention") land directly on its own level instead of
  // always opening on L2.
  final int initialTabIndex;
  const EscalationsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<EscalationsScreen> createState() => _EscalationsScreenState();
}

class _EscalationsScreenState extends State<EscalationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final open = store.openEscalationCases;
    final l2 = open.where((e) => e.level == 'L2').toList();
    final l3 = open.where((e) => e.level == 'L3').toList();
    final l4 = open.where((e) => e.level == 'L4').toList();
    final resolved = store.visibleEscalationCases.where((e) => !e.isOpen).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Escalations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _dark)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
        bottom: TabBar(
          controller: _tab,
          labelColor: _blue,
          unselectedLabelColor: _muted,
          indicatorColor: _blue,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: [
            Tab(text: 'L2 (${l2.length})'),
            Tab(text: 'L3 (${l3.length})'),
            Tab(text: 'L4 (${l4.length})'),
            Tab(text: 'Resolved (${resolved.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          const DataLoadingBar(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _caseList(context, l2, store),
                _caseList(context, l3, store),
                _caseList(context, l4, store),
                _caseList(context, resolved, store),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _caseList(BuildContext context, List<EscalationCase> cases, AppStore store) {
    if (cases.isEmpty) {
      return const Center(child: Text('No cases in this category.', style: TextStyle(color: _muted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cases.length,
      itemBuilder: (ctx, i) {
        final e = cases[i];
        final color = levelColor(e.level);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _caseCard(context, e, color, store),
          ),
        );
      },
    );
  }

  Widget _caseCard(BuildContext context, EscalationCase e, Color color, AppStore store) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.25), width: 1.4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(e.level == 'L4' ? 'L4 · MANAGEMENT ATTENTION' : (e.level == 'L3' ? 'L3 · RE CONTROL' : 'L2 · RE SUPERVISION'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                    ),
                  ]),
                  Text(fmt.format(e.moneyAtRisk), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  final c = store.customers.firstWhere((c) => c.id == e.customerId, orElse: () => store.customers.first);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c)));
                },
                child: Text(e.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _blue, decoration: TextDecoration.underline)),
              ),
              const SizedBox(height: 4),
              Text('Reason: ${e.reason}', style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 10),
              _kv('Owner', store.salesmanDisplayName(e.ownerId)),
              _kv('Plan', e.plan),
              _kv('Deadline', DateFormat('dd MMM yyyy, hh:mm a').format(e.deadline)),
              if (e.resolvedAt != null) _kv('Resolved', DateFormat('dd MMM yyyy, hh:mm a').format(e.resolvedAt!)),
              if (e.history.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('AUDIT TRAIL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _muted, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                ...e.history.map((h) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $h', style: const TextStyle(fontSize: 11, color: _muted)),
                    )),
              ],
              if (e.isOpen) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (e.level != 'L4')
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: BorderSide(color: color), foregroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          onPressed: () => _escalateFurther(context, store, e),
                          child: const Text('Escalate Further', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    if (e.level != 'L4') const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () => _resolve(context, store, e),
                        child: const Text('Resolve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: _dark),
          children: [
            TextSpan(text: '$k: ', style: const TextStyle(color: _muted)),
            TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _escalateFurther(BuildContext context, AppStore store, EscalationCase e) {
    final nextLevel = e.level == 'L2' ? 'L3' : 'L4';
    final planController = TextEditingController(text: e.plan);
    DateTime deadline = DateTime.now().add(const Duration(days: 2));
    String? planError;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Escalate to $nextLevel', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plan *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(controller: planController, decoration: InputDecoration(border: const OutlineInputBorder(), errorText: planError), maxLines: 2),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: deadline, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (picked != null) setState(() => deadline = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('dd MMM yyyy').format(deadline)), const Icon(Icons.calendar_today, size: 16)]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: levelColor(nextLevel)),
              onPressed: () async {
                if (planController.text.trim().isEmpty) {
                  setState(() => planError = '$nextLevel cases require a plan (spec: no L3/L4 case without a plan)');
                  return;
                }
                final navigator = Navigator.of(context);
                try {
                  await store.escalateCustomer(e.customerId, nextLevel, e.reason, planController.text.trim(), e.ownerId, deadline);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  showAppMessageAfter(navigator, message: 'Escalated to $nextLevel.');
                } catch (err) {
                  showAppMessageAfter(navigator, message: 'Could not escalate: $err', isError: true);
                }
              },
              child: const Text('Escalate', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  void _resolve(BuildContext context, AppStore store, EscalationCase e) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resolve Escalation', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: noteController, decoration: const InputDecoration(hintText: 'Resolution note', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () async {
              if (noteController.text.trim().isEmpty) return;
              final navigator = Navigator.of(context);
              try {
                await store.resolveEscalation(e.id, noteController.text.trim());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                showAppMessageAfter(navigator, message: 'Escalation resolved.');
              } catch (err) {
                showAppMessageAfter(navigator, message: 'Could not resolve: $err', isError: true);
              }
            },
            child: const Text('Resolve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
