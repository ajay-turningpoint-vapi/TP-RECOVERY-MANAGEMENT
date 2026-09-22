import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/escalation_case.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Manager's Management Attention — the L4 escalation queue (per the build
/// guide, the top of the escalation ladder: L1 Salesperson Led → L2 RE
/// Supervision → L3 RE Control → L4 Management Attention). Each case shows
/// exposure, owner, reason, current plan and full history, and lets the
/// Manager issue a real, tracked Management Instruction — the one action
/// the build guide explicitly assigns to Management (§17, §34). This is
/// deliberately the one Manager screen with a real write action; every
/// other Manager screen in this app stays view-only by design.
class ManagerManagementAttentionScreen extends StatefulWidget {
  const ManagerManagementAttentionScreen({super.key});

  @override
  State<ManagerManagementAttentionScreen> createState() => _ManagerManagementAttentionScreenState();
}

class _ManagerManagementAttentionScreenState extends State<ManagerManagementAttentionScreen> {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final cases = List<EscalationCase>.from(store.l4Cases)..sort((a, b) => a.deadline.compareTo(b.deadline));
    final totalMoneyAtRisk = cases.fold<double>(0.0, (s, c) => s + c.moneyAtRisk);
    final pendingInstructions = store.mgmtInstructionCount;
    final overdueInstructions = store.tasks.where((t) => t.type.toString() == 'TaskType.managementInstruction' && t.isOverdue).length;

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
                      _statCards(cases.length, totalMoneyAtRisk, pendingInstructions, overdueInstructions),
                      const SizedBox(height: 16),
                      if (cases.isEmpty)
                        const InfoCard(children: [
                          Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('No open L4 cases — nothing requires Management Attention right now.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kMuted)))),
                        ])
                      else
                        ...cases.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _caseCard(context, store, c))),
                      const SizedBox(height: 16),
                      _footer(context, store),
                    ],
                  ),
                ),
              ],
            );
            if (constraints.maxWidth <= 700) return content;
            return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: content));
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
                Text('Management Attention', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kNavy)),
                Text('L4 cases requiring an executive decision', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _snack(context, 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.')),
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

  Widget _statCards(int total, double moneyAtRisk, int pendingInstructions, int overdueInstructions) {
    final cards = [
      (Icons.warning_amber_rounded, kRed, '$total', 'L4 Cases', 'Open'),
      (Icons.account_balance_wallet_outlined, kRed, _rupee.format(moneyAtRisk), 'Money at Risk', ''),
      (Icons.assignment_outlined, kPurple, '$pendingInstructions', 'Pending Instructions', ''),
      (Icons.hourglass_bottom, kOrange, '$overdueInstructions', 'Overdue Instructions', ''),
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
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kDark, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 8.5, color: kMuted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _caseCard(BuildContext context, AppStore store, EscalationCase c) {
    final overdue = c.deadline.isBefore(DateTime.now());
    return InkWell(
      onTap: () => _showCaseDetail(context, store, c),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kRed.withOpacity(0.25))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: kRed.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: const Text('L4', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: kRed))),
                const SizedBox(width: 8),
                Expanded(child: Text(c.customerName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: kNavy))),
                const Icon(Icons.chevron_right, size: 16, color: kMuted),
              ],
            ),
            const SizedBox(height: 6),
            Text(c.reason, style: const TextStyle(fontSize: 11, color: kDark)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Exposure', style: TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
                      Text(_rupee.format(c.moneyAtRisk), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kRed)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Owner', style: TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
                      Text(store.salesmanDisplayName(c.ownerId), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deadline', style: TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
                      Text(DateFormat('dd MMM yyyy').format(c.deadline), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: overdue ? kRed : kDark)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCaseDetail(BuildContext context, AppStore store, EscalationCase c) {
    final customer = store.customers.firstWhere((cu) => cu.id == c.customerId, orElse: () => store.customers.first);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(c.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: kRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Text('L4', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kRed))),
                ],
              ),
              Text('${customer.branch}  ·  Owner: ${store.salesmanDisplayName(c.ownerId)}', style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 16),
              _kv('Exposure', _rupee.format(c.moneyAtRisk)),
              _kv('Overdue', _rupee.format(customer.totalDue)),
              _kv('Reason', c.reason),
              _kv('Deadline', DateFormat('dd MMM yyyy, hh:mm a').format(c.deadline)),
              const SizedBox(height: 10),
              const Text('Current Plan', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 4),
              Text(c.plan, style: const TextStyle(fontSize: 12, color: kDark)),
              const SizedBox(height: 12),
              const Text('History', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavy)),
              const SizedBox(height: 6),
              ...c.history.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 5, color: kMuted)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(h, style: const TextStyle(fontSize: 11.5, color: kDark))),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showIssueInstructionDialog(context, store, c, customer);
                  },
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Issue Management Instruction', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Reassignment and dispute actions are taken by the Recovery Executive. This is the one Management action available on this screen.', style: TextStyle(fontSize: 10.5, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  void _showIssueInstructionDialog(BuildContext context, AppStore store, EscalationCase c, Customer customer) {
    final descController = TextEditingController();
    String owner = c.ownerId;
    String priority = 'Critical';
    DateTime deadline = DateTime.now().add(const Duration(days: 1));
    final salesmenNames = store.salesmen.map((s) => s['name'] as String).toList();
    if (!salesmenNames.contains(owner) && salesmenNames.isNotEmpty) owner = salesmenNames.first;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Management Instruction', style: TextStyle(fontWeight: FontWeight.bold, color: kNavy, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: ${c.customerName}', style: const TextStyle(fontSize: 12.5, color: kDark, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Instruction', hintText: 'e.g. RE must personally supervise the next recovery action.', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: owner,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Owner', border: OutlineInputBorder(), isDense: true),
                  items: salesmenNames.map((n) => DropdownMenuItem(value: n, child: Text(store.salesmanDisplayName(n)))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => owner = v); },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: priority,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder(), isDense: true),
                  items: const [DropdownMenuItem(value: 'Critical', child: Text('Critical')), DropdownMenuItem(value: 'High', child: Text('High')), DropdownMenuItem(value: 'Medium', child: Text('Medium'))],
                  onChanged: (v) { if (v != null) setDialogState(() => priority = v); },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: dialogCtx, initialDate: deadline, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
                    if (picked != null) setDialogState(() => deadline = DateTime(picked.year, picked.month, picked.day, 17));
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Deadline', border: OutlineInputBorder(), isDense: true),
                    child: Text(DateFormat('dd MMM yyyy, hh:mm a').format(deadline), style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel', style: TextStyle(color: kMuted))),
            LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white),
              onPressed: () async {
                if (descController.text.trim().isEmpty) {
                  showAppMessage(dialogCtx, message: 'Enter an instruction before issuing it.');
                  return;
                }
                final navigator = Navigator.of(context);
                try {
                  await store.assignManagementInstruction(c.customerId, owner, descController.text.trim(), deadline, priority: priority);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  showAppMessageAfter(navigator, message: 'Management Instruction issued to $owner — due ${DateFormat('dd MMM yyyy').format(deadline)}.');
                } catch (e) {
                  showAppMessageAfter(navigator, message: 'Could not issue instruction: $e', isError: true);
                }
              },
              child: const Text('Issue Instruction', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
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
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: kBlue),
          SizedBox(width: 8),
          Expanded(child: Text('L4 cases are opened when RE Control (L3) does not resolve the exposure — the highest-ever escalation level is always retained, even after resolution.', style: TextStyle(fontSize: 10, color: kDark))),
        ],
      ),
    );
  }
}
