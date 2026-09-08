import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _navy = Color(0xFF1B2B48);
const _blue = Color(0xFF2563EB);

const _departments = [
  'Sales / Material Coordination',
  'Accounts',
  'Logistics',
  'Quality Control',
  'Customer Service'
];
const _priorities = ['Low', 'Medium', 'High'];
const _followUpModes = [
  'Task Only',
  'Notification Only',
  'Task + Notification'
];

class DisputeAssignView extends StatefulWidget {
  final String disputeId;
  final VoidCallback onBack;
  final VoidCallback onConfirmed;
  const DisputeAssignView(
      {super.key,
      required this.disputeId,
      required this.onBack,
      required this.onConfirmed});

  @override
  State<DisputeAssignView> createState() => _DisputeAssignViewState();
}

class _DisputeAssignViewState extends State<DisputeAssignView> {
  late String _owner;
  late String _department;
  late String _priority;
  late String _followUpMode;
  DateTime _deadlineDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _deadlineTime = const TimeOfDay(hour: 17, minute: 0);
  final _notesController = TextEditingController(
      text:
          'Inspect the issue, coordinate with the branch and confirm corrective action before the deadline.');
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final d = store.disputes.firstWhere((d) => d['id'] == widget.disputeId,
        orElse: () => store.disputes.first);
    final customer = store.customers.firstWhere((c) => c.name == d['customer'],
        orElse: () => store.customers.first);
    final amount = (d['amount'] as num).toDouble();
    final totalDue = (d['totalDue'] as num?)?.toDouble() ?? customer.totalDue;
    final undisputed = (totalDue - amount).clamp(0, double.infinity);

    if (!_initialized) {
      _owner = store.salesmen.isNotEmpty
          ? store.salesmen.first['name'] as String
          : '';
      _department = _departments.first;
      _priority = (d['priority'] as String?) ?? 'Medium';
      _followUpMode = _followUpModes.last;
      _initialized = true;
    }

    // Swapped in-place inside DisputesTab (already hosted inside
    // ReScaffoldV3's own Scaffold), not pushed as a new route — must not
    // nest a second competing Scaffold here (see the identical note in
    // dispute_details_view.dart for the confirmed rendering bug this caused).
    return Container(
      color: kBg,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: _navy),
                          onPressed: widget.onBack),
                    ),
                    const Text('Approve & Assign',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _navy)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: kOrange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('APPROVING DISPUTE',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: kOrange)),
                      ),
                      const SizedBox(height: 10),
                      InfoCard(children: [
                        Text(customer.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _navy)),
                        const SizedBox(height: 3),
                        Text(
                            'Customer ID: ${d['customerCode']}  ·  Invoice: ${d['invoice']}',
                            style:
                                const TextStyle(fontSize: 10.5, color: kMuted)),
                        Text('Branch: ${customer.branch}',
                            style:
                                const TextStyle(fontSize: 10.5, color: kMuted)),
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1, color: kBorder)),
                        KeyValueRow('Dispute Amount', _rupee.format(amount)),
                        KeyValueRow(
                            'Undisputed Amount', _rupee.format(undisputed),
                            valueColor: kGreen),
                        KeyValueRow('Reason', d['reason']),
                      ]),
                      const SizedBox(height: 18),
                      const SectionLabel('ASSIGNMENT DETAILS'),
                      InfoCard(children: [
                        _dropdownRow(
                            'Resolution Owner',
                            _owner,
                            store.salesmen
                                .map((s) => s['name'] as String)
                                .toList(),
                            (v) => setState(() => _owner = v),
                            optionLabel: store.salesmanDisplayName),
                        const Divider(height: 20, color: kBorder),
                        _dropdownRow(
                            'Internal Department',
                            _department,
                            _departments,
                            (v) => setState(() => _department = v)),
                        const Divider(height: 20, color: kBorder),
                        _dateRow('Deadline Date',
                            DateFormat('dd MMM yyyy').format(_deadlineDate),
                            () async {
                          final picked = await showDatePicker(
                              context: context,
                              initialDate: _deadlineDate,
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 60)));
                          if (picked != null) {
                            setState(() => _deadlineDate = picked);
                          }
                        }),
                        const Divider(height: 20, color: kBorder),
                        _dateRow('Deadline Time', _deadlineTime.format(context),
                            () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: _deadlineTime);
                          if (picked != null) {
                            setState(() => _deadlineTime = picked);
                          }
                        }),
                        const Divider(height: 20, color: kBorder),
                        _dropdownRow('Priority', _priority, _priorities,
                            (v) => setState(() => _priority = v),
                            valueColor: _priority == 'High'
                                ? kRed
                                : (_priority == 'Medium' ? kOrange : kGreen)),
                        const Divider(height: 20, color: kBorder),
                        _dropdownRow(
                            'Follow-up Mode',
                            _followUpMode,
                            _followUpModes,
                            (v) => setState(() => _followUpMode = v)),
                        const SizedBox(height: 14),
                        const Text('Notes for Resolution Owner',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: kMuted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                            controller: _notesController,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(10))),
                      ]),
                      const SizedBox(height: 18),
                      const SectionLabel('OPERATIONAL EFFECT'),
                      InfoCard(children: [
                        _effectRow(
                            Icons.trending_down,
                            kOrange,
                            'Disputed amount recovery',
                            'Paused after approval'),
                        const Divider(height: 20, color: kBorder),
                        _effectRow(Icons.trending_up, kGreen,
                            'Undisputed amount recovery', 'Continues normally'),
                        const Divider(height: 20, color: kBorder),
                        _effectRow(
                            Icons.verified_user_outlined,
                            _blue,
                            'Audit trail',
                            'Approval and assignment will be recorded'),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: kBorder))),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kRed),
                              foregroundColor: kRed,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          onPressed: widget.onBack,
                          child: const Text('Cancel',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          onPressed: () => _confirm(context, store, d),
                          child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Confirm Approval & Assign',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, AppStore store, Map<String, dynamic> d) async {
    final deadline = DateTime(_deadlineDate.year, _deadlineDate.month,
        _deadlineDate.day, _deadlineTime.hour, _deadlineTime.minute);
    final navigator = Navigator.of(context);
    try {
      await store.approveDispute(
          d['id'], _owner, deadline, _notesController.text.trim());
      showAppMessageAfter(navigator, message: 'Dispute approved and assigned for resolution.');
      widget.onConfirmed();
    } catch (e) {
      showAppMessageAfter(navigator, message: 'Could not approve: $e', isError: true);
    }
  }

  Widget _dropdownRow(String label, String value, List<String> options,
      ValueChanged<String> onChanged,
      {Color valueColor = kDark, String Function(String)? optionLabel}) {
    String labelFor(String o) => optionLabel != null ? optionLabel(o) : o;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.bold, color: valueColor),
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(labelFor(o))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _dateRow(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
          Row(children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: kMuted),
          ]),
        ],
      ),
    );
  }

  Widget _effectRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: kDark))),
        Text(value,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
