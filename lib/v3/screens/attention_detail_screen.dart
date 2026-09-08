import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart' show AttachmentsSection;
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';

const _dark = Color(0xFF0F172A);
const _navy = Color(0xFF1B2B48);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFEEF1F5);
const _bg = Color(0xFFF8FAFC);
const _blue = Color(0xFF2563EB);
const _red = Color(0xFFDC2626);
const _orange = Color(0xFFEA580C);
const _purple = Color(0xFF7C3AED);
const _green = Color(0xFF16A34A);

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

const List<Color> _avatarPalette = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
];

Color _avatarColorFor(String name) => _avatarPalette[name.hashCode.abs() % _avatarPalette.length];
String _initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase();
}

enum AttentionCategory { noCall, overdueTargets }

class AttentionDetailScreen extends StatelessWidget {
  final String salesmanName;
  final AttentionCategory category;
  const AttentionDetailScreen({super.key, required this.salesmanName, required this.category});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final s = store.salesmen.firstWhere((s) => s['name'] == salesmanName, orElse: () => store.salesmen.first);
    final owned = store.customers.where((c) => c.assignedSalesmanId == salesmanName).toList()
      ..sort((a, b) => b.totalDue.compareTo(a.totalDue));
    final ownedIds = owned.map((c) => c.id).toSet();
    final ownedPtps = store.ptps.where((p) => ownedIds.contains(p.customerId)).toList();

    final avgDebtorDays = owned.isEmpty ? 0 : (owned.fold(0, (s, c) => s + c.oldestOverdueDays) / owned.length).round();
    PromiseToPay? lastKept;
    for (final p in ownedPtps.where((p) => p.status == PtpStatus.kept)) {
      if (lastKept == null || p.promiseDate.isAfter(lastKept.promiseDate)) lastKept = p;
    }
    final ptpsDueTodayNotAddressed = ownedPtps.where((p) => p.status == PtpStatus.scheduled && _isToday(p.promiseDate)).length;
    final newCustomersNotContacted = owned.where((c) => c.oldestOverdueDays <= 3).length;

    final isNoCall = category == AttentionCategory.noCall;
    final bannerText = isNoCall
        ? 'Salesman has not connected with any overdue customer today.'
        : 'Salesman has not achieved today\'s collection target.';
    final priorityLabel = isNoCall ? 'High Priority' : 'Medium Priority';
    final priorityColor = isNoCall ? _red : _orange;
    final subtitle = isNoCall ? 'Salesman No Call Today' : 'Salesman Overdue Targets';

    final events = _buildTimeline(s, owned, ownedPtps);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _navy,
        centerTitle: true,
        title: Column(
          children: [
            const Text('ATTENTION DETAILS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navy)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert, color: _dark), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: priorityColor.withOpacity(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(isNoCall ? Icons.phone_missed_outlined : Icons.trending_down, size: 15, color: priorityColor),
                const SizedBox(width: 8),
                Expanded(child: Text(bannerText, style: TextStyle(fontSize: 11.5, color: priorityColor, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: priorityColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(priorityLabel, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: priorityColor)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _headerCard(s, owned, avgDebtorDays, lastKept),
                        const SizedBox(height: 14),
                        Text(isNoCall ? 'NO CALL SUMMARY (Today)' : 'TARGET SUMMARY (Today)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _navy, letterSpacing: 0.3)),
                        const SizedBox(height: 10),
                        isNoCall
                            ? _noCallSummaryGrid(owned.length, owned.fold(0.0, (a, c) => a + c.totalDue), ptpsDueTodayNotAddressed, newCustomersNotContacted)
                            : _targetSummaryGrid(s),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isNoCall ? 'TOP OVERDUE CUSTOMERS NOT CALLED' : 'TOP OVERDUE CUSTOMERS', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _navy, letterSpacing: 0.3)),
                            if (owned.isNotEmpty) const Text('View All', style: TextStyle(fontSize: 11.5, color: _blue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _customersTable(context, owned.take(5).toList(), s),
                        const SizedBox(height: 18),
                        const Text('RECENT ACTIVITY', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _navy, letterSpacing: 0.3)),
                        const SizedBox(height: 10),
                        _timeline(events),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _border))),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _blue), foregroundColor: _blue, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _contactSalesman(context, s),
                  icon: const Icon(Icons.call_outlined, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Contact Salesman', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _assignTask(context, store, s, owned),
                  icon: const Icon(Icons.assignment_outlined, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Assign Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _addNote(context, store, s),
                  icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Add Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Widget _headerCard(Map<String, dynamic> s, List owned, int avgDebtorDays, PromiseToPay? lastKept) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(builder: (_) {
                final display = (s['fullName'] as String?) ?? (s['name'] as String);
                return CircleAvatar(radius: 26, backgroundColor: _avatarColorFor(display).withOpacity(0.15), child: Text(_initialsFor(display), style: TextStyle(color: _avatarColorFor(display), fontSize: 16, fontWeight: FontWeight.bold)));
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text((s['fullName'] as String?) ?? s['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: _navy))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(5)),
                          child: const Text('Salesman', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _blue)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(children: [const Icon(Icons.people_outline, size: 12, color: _muted), const SizedBox(width: 4), Text('${s['customers']} Customers', style: const TextStyle(fontSize: 11, color: _muted))]),
                    const SizedBox(height: 3),
                    Row(children: [const Icon(Icons.location_on_outlined, size: 12, color: _muted), const SizedBox(width: 4), Text('${s['branch']} Branch', style: const TextStyle(fontSize: 11, color: _muted))]),
                    const SizedBox(height: 3),
                    CallablePhoneNumber(phoneNumber: s['phone'] as String?, iconColor: _muted, iconSize: 12, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Overdue', style: TextStyle(fontSize: 10, color: _muted)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(s['totalOverdue']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _red))),
                  const SizedBox(height: 4),
                  Text('Overdue Customers: ${owned.length}', style: const TextStyle(fontSize: 9.5, color: _muted)),
                ],
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: _border)),
          Row(
            children: [
              Expanded(child: _miniStat('Last PTP Kept', lastKept != null ? DateFormat('dd MMM yyyy').format(lastKept.promiseDate) : 'None yet', _green, Icons.event_available_outlined)),
              Expanded(child: _miniStat('PTP Kept % (MTD)', '${s['ptpKeptPercent']}%', _red, Icons.percent)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _miniStat('Avg Debtor Days', '$avgDebtorDays Days', _orange, Icons.timelapse_outlined)),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9.5, color: _muted)),
        const SizedBox(height: 3),
        Row(children: [Icon(icon, size: 11, color: color), const SizedBox(width: 4), Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color))]),
      ],
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label1, String label2) {
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 14, color: color)),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
          const SizedBox(height: 3),
          Text(label1, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: _dark, fontWeight: FontWeight.w600)),
          Text(label2, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8.5, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _statRow(List<Widget> tiles) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => tiles[i],
      ),
    );
  }

  Widget _noCallSummaryGrid(int overdueCustomers, double overdueAmount, int ptpsDue, int newCustomers) {
    return _statRow([
      _statTile(Icons.phone_missed_outlined, _red, '$overdueCustomers', 'Overdue Customers', 'Not Called'),
      _statTile(Icons.currency_rupee, _orange, _rupee.format(overdueAmount), 'Overdue Amount', 'Not Called'),
      _statTile(Icons.event_busy_outlined, _purple, '$ptpsDue', 'PTPs Due Today', 'Not Addressed'),
      _statTile(Icons.person_add_alt_outlined, _blue, '$newCustomers', 'New Customers', 'Not Contacted'),
    ]);
  }

  Widget _targetSummaryGrid(Map<String, dynamic> s) {
    return _statRow([
      _statTile(Icons.flag_outlined, _navy, _rupee.format(s['collectionTarget']), 'Collection', 'Target'),
      _statTile(Icons.trending_up, _green, _rupee.format(s['collectionAchieved']), 'Achieved', '${s['collectionAchievedPercent']}%'),
      _statTile(Icons.currency_rupee, _red, _rupee.format(s['totalOverdue']), 'Overdue', 'Amount'),
      _statTile(Icons.assignment_late_outlined, _orange, '${s['overdueTasks']}', 'Overdue', 'Tasks'),
    ]);
  }

  Widget _customersTable(BuildContext context, List owned, Map<String, dynamic> s) {
    if (owned.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: const Center(child: Text('No overdue customers.', style: TextStyle(color: _muted, fontSize: 12))),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Customer Name', style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Overdue Amt', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Days', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Credit Health', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          ...owned.map((c) => GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 13, backgroundColor: _avatarColorFor(c.name).withOpacity(0.15), child: Text(_initialsFor(c.name), style: TextStyle(color: _avatarColorFor(c.name), fontSize: 9, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: Text(c.name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark), overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(c.totalDue), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _red)))),
                      Expanded(flex: 2, child: Text('${c.oldestOverdueDays}d', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: _dark))),
                      Expanded(flex: 2, child: Text(c.creditHealthBand, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, color: _muted))),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  List<_TimelineEvent> _buildTimeline(Map<String, dynamic> s, List owned, List<PromiseToPay> ownedPtps) {
    final events = <_TimelineEvent>[];
    for (final p in ownedPtps) {
      final customer = owned.cast<dynamic>().firstWhere((c) => c.id == p.customerId, orElse: () => null);
      final customerName = customer?.name ?? '';
      if (p.status == PtpStatus.broken) {
        events.add(_TimelineEvent(icon: Icons.event_busy, color: _orange, title: 'PTP missed by customer', subtitle: '$customerName • ${_rupee.format(p.amountPromised)}', date: p.promiseDate, tag: 'Missed PTP', tagColor: _orange));
      } else if (p.status == PtpStatus.kept) {
        events.add(_TimelineEvent(icon: Icons.event_available, color: _purple, title: 'PTP marked as kept', subtitle: '$customerName • ${_rupee.format(p.amountPromised)}', date: p.promiseDate, tag: 'PTP Kept', tagColor: _purple));
      }
    }
    events.sort((a, b) => b.date.compareTo(a.date));
    return events.take(6).toList();
  }

  Widget _timeline(List<_TimelineEvent> events) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: const Center(child: Text('No recent activity.', style: TextStyle(color: _muted, fontSize: 12))),
      );
    }
    return Column(
      children: events.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final isLast = i == events.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: e.color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(e.icon, size: 13, color: e.color)),
                  if (!isLast) Expanded(child: Container(width: 1.4, color: _border)),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: _dark)),
                            if (e.subtitle != null) Text(e.subtitle!, style: const TextStyle(fontSize: 10.5, color: _muted)),
                            const SizedBox(height: 2),
                            Text(DateFormat('dd MMM yyyy · hh:mm a').format(e.date), style: const TextStyle(fontSize: 10, color: _muted)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: e.tagColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(e.tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: e.tagColor)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _contactSalesman(BuildContext context, Map<String, dynamic> s) {
    // Real Call/WhatsApp picker (same as every other phone number in the
    // app — see widgets/call_helper.dart) instead of a fake "Calling…"
    // dialog that never actually dialed anything.
    contactActions(context, s['phone'] as String?);
  }

  void _assignTask(BuildContext context, AppStore store, Map<String, dynamic> s, List<Customer> owned) {
    if (owned.isEmpty) {
      showAppMessage(context, message: 'No customer available to attach this task to.');
      return;
    }
    Customer target = owned.first;
    String priority = 'Critical';
    final reasonController = TextEditingController();
    DateTime deadline = DateTime.now().add(const Duration(days: 1));
    String? reasonError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(builder: (context, setState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: _navy.withOpacity(0.08), shape: BoxShape.circle), child: const Icon(Icons.assignment_outlined, color: _navy, size: 18)),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Assign Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy))),
                  IconButton(icon: const Icon(Icons.close, size: 20, color: _muted), onPressed: () => Navigator.pop(sheetCtx)),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Creates a Management Instruction owned by ${(s['fullName'] as String?) ?? s['name']} on the chosen customer. This is a direct, RE-issued required action that overrides the salesperson\'s own judgment on next step — use it when a salesman is not self-directing correctly and needs a specific push.',
                  style: const TextStyle(fontSize: 11.5, color: _muted, height: 1.4),
                ),
                const SizedBox(height: 18),
                const Text('Customer *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _dark)),
                const SizedBox(height: 6),
                DropdownButtonFormField<Customer>(
                  value: target,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: owned.map((c) => DropdownMenuItem(value: c, child: Text('${c.name} · ${_rupee.format(c.totalDue)} due', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) { if (v != null) setState(() => target = v); },
                ),
                const SizedBox(height: 16),
                const Text('Task Instruction *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _dark)),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: 'e.g. Visit customer today and obtain a firm PTP before 5 PM', border: const OutlineInputBorder(), errorText: reasonError),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Priority *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _dark)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: priority,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                          items: ['Critical', 'High', 'Normal'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (v) { if (v != null) setState(() => priority = v); },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Deadline *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _dark)),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(context: context, initialDate: deadline, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                            if (picked != null) setState(() => deadline = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.5)), borderRadius: BorderRadius.circular(4)),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(DateFormat('dd MMM yyyy').format(deadline), style: const TextStyle(fontSize: 13)),
                              const Icon(Icons.calendar_today, size: 15, color: _muted),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      if (reasonController.text.trim().isEmpty) {
                        setState(() => reasonError = 'Task instruction is required');
                        return;
                      }
                      final navigator = Navigator.of(context);
                      Navigator.pop(sheetCtx);
                      try {
                        await store.assignManagementInstruction(target.id, s['name'], reasonController.text.trim(), deadline, priority: priority);
                        showAppMessageAfter(navigator, message: '$priority task assigned to ${(s['fullName'] as String?) ?? s['name']} on ${target.name}.');
                      } catch (e) {
                        showAppMessageAfter(navigator, message: 'Could not assign: $e', isError: true);
                      }
                    },
                    child: const Text('Assign Task', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _addNote(BuildContext context, AppStore store, Map<String, dynamic> s) {
    final controller = TextEditingController();
    final existingNotes = store.notesFor(s['name']);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(builder: (context, setState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: _navy.withOpacity(0.08), shape: BoxShape.circle), child: const Icon(Icons.sticky_note_2_outlined, color: _navy, size: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Notes — ${(s['fullName'] as String?) ?? s['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy))),
                  IconButton(icon: const Icon(Icons.close, size: 20, color: _muted), onPressed: () => Navigator.pop(sheetCtx)),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'A private RE-to-RE record kept against this salesperson — not sent to them and not a task. Use it to log context for the next control review (e.g. "spoke to him, promised improvement by Friday") so it isn\'t lost between shifts.',
                  style: TextStyle(fontSize: 11.5, color: _muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (existingNotes.isNotEmpty) ...[
                  const Text('PREVIOUS NOTES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _muted, letterSpacing: 0.4)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
                    child: Scrollbar(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(10),
                        itemCount: existingNotes.length,
                        separatorBuilder: (_, __) => const Divider(height: 14, color: _border),
                        itemBuilder: (ctx, i) {
                          final n = existingNotes[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n['note'] as String, style: const TextStyle(fontSize: 12, color: _dark)),
                              const SizedBox(height: 3),
                              Text('${n['author']} · ${DateFormat('dd MMM yyyy, hh:mm a').format(n['timestamp'] as DateTime)}', style: const TextStyle(fontSize: 9.5, color: _muted)),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('New Note', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _dark)),
                const SizedBox(height: 6),
                TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Add a note for this salesman…', border: OutlineInputBorder())),
                const SizedBox(height: 18),
                // Same refId scheme as every Tasks-screen item — evidence
                // attached here (e.g. a screenshot of a WhatsApp
                // conversation) shows up wherever this salesman's refId is
                // referenced.
                AttachmentsSection(refId: s['name'] as String),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      if (controller.text.trim().isEmpty) return;
                      store.addSalesmanNote(s['name'], controller.text.trim());
                      Navigator.pop(sheetCtx);
                      showAppMessage(context, message: 'Note added.');
                    },
                    child: const Text('Save Note', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _TimelineEvent {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final DateTime date;
  final String tag;
  final Color tagColor;
  _TimelineEvent({required this.icon, required this.color, required this.title, this.subtitle, required this.date, required this.tag, required this.tagColor});
}
