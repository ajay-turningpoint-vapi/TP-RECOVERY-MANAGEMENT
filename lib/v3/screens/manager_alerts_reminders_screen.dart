import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/v3/screens/manager_priority_accounts_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_ptp_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_no_follow_up_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_dispute_status_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_ageing_receivables_report_screen.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum _AlertGroup { overdue, ptp, followUp, disputes }

class _AlertItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;
  final String countLabel;
  final double? amount;
  final String amountLabel;
  final _AlertGroup group;
  final Widget Function(BuildContext) screenBuilder;
  _AlertItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.countLabel,
    this.amount,
    this.amountLabel = 'Total Overdue',
    required this.group,
    required this.screenBuilder,
  });
}

// Time-aware, not date-only: a PTP promised for 2 minutes ago is expired
// right now, not merely "today" — the old date-truncated comparison hid
// same-day lateness from this alert for the rest of the calendar day.
bool _isPastDue(DateTime d) => d.isBefore(DateTime.now());

/// Manager's Alerts & Reminders — a real-time hub over the same shared
/// data as the Dashboard's Alerts card, grouped into Overdue/PTP/No
/// Follow-up/Disputes, with search, sort, and drill-through to the already
/// view-only Manager report screens (no actions live on this screen).
class ManagerAlertsRemindersScreen extends StatefulWidget {
  const ManagerAlertsRemindersScreen({super.key});

  @override
  State<ManagerAlertsRemindersScreen> createState() => _ManagerAlertsRemindersScreenState();
}

class _ManagerAlertsRemindersScreenState extends State<ManagerAlertsRemindersScreen> {
  _AlertGroup? _activeGroup;
  String _query = '';
  bool _sortByCountDesc = true;
  bool _notificationsEnabled = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    final overdueCustomers = store.customers.where((c) => c.totalDue > 0 && c.oldestOverdueDays >= 30).toList();
    final ptpDueToday = store.ptps.where((p) => p.status == PtpStatus.scheduled && _isSameDay(p.promiseDate, DateTime.now())).toList();
    final noFollowUp = store.noFollowUpAccounts;
    // 'Awaiting Verification' belongs to the canonical in-progress bucket
    // (see AppStore's _disputeInProgressStatuses), not awaiting-review —
    // matching store.disputesAwaitingReviewCount and the Dispute Status
    // Report's own bucketing exactly.
    final disputesAwaiting = store.disputes.where((d) => d['status'] == 'Pending Approval').toList();
    final ptpExpired = store.ptps.where((p) => (p.status == PtpStatus.scheduled || p.status == PtpStatus.financialSyncPending) && _isPastDue(p.promiseDate)).toList();
    final recentlyCreatedNoActivity = store.customers.where((c) => c.totalDue > 0 && c.auditHistory.isEmpty).toList();
    final highCreditDays = store.customers.where((c) => c.totalDue > 0 && c.oldestOverdueDays > c.creditDays).toList();
    final topPriority = store.customers.where((c) => c.totalDue > 0 && c.oldestOverdueDays >= 60 && c.totalDue >= 200000).toList();

    final items = <_AlertItem>[
      _AlertItem(
        icon: Icons.warning_amber_rounded, color: kRed,
        title: 'Customers with 30+ days overdue', subtitle: 'Immediate attention required',
        count: overdueCustomers.length, countLabel: 'Customers',
        amount: overdueCustomers.fold<double>(0.0, (s, c) => s + c.totalDue),
        group: _AlertGroup.overdue, screenBuilder: (_) => const ManagerPriorityAccountsScreen(),
      ),
      _AlertItem(
        icon: Icons.hourglass_empty, color: kOrange,
        title: 'PTP due today', subtitle: 'Follow-up required to keep promises',
        count: ptpDueToday.length, countLabel: 'Promises',
        amount: ptpDueToday.fold<double>(0.0, (s, p) => s + p.amountPromised), amountLabel: 'Total Amount',
        group: _AlertGroup.ptp, screenBuilder: (_) => const ManagerPtpReportScreen(),
      ),
      _AlertItem(
        icon: Icons.phone_disabled_outlined, color: kPurple,
        title: 'No follow-up accounts (5:00 PM missed)', subtitle: 'Follow-up not done by salesperson',
        count: noFollowUp.length, countLabel: 'Accounts',
        amount: noFollowUp.fold<double>(0.0, (s, c) => s + c.totalDue),
        group: _AlertGroup.followUp, screenBuilder: (_) => const ManagerNoFollowUpReportScreen(),
      ),
      _AlertItem(
        icon: Icons.description_outlined, color: kBlue,
        title: 'Disputes awaiting review', subtitle: 'Pending your review and assignment',
        count: disputesAwaiting.length, countLabel: 'Disputes',
        amount: disputesAwaiting.fold<double>(0.0, (s, d) => s + ((d['amount'] as num).toDouble())), amountLabel: 'Total Amount',
        group: _AlertGroup.disputes, screenBuilder: (_) => const ManagerDisputeStatusReportScreen(),
      ),
      _AlertItem(
        icon: Icons.event_busy_outlined, color: kRed,
        title: 'Accounts with PTP expired', subtitle: 'Promises are past due date',
        count: ptpExpired.length, countLabel: 'Accounts',
        amount: ptpExpired.fold<double>(0.0, (s, p) => s + p.amountPromised),
        group: _AlertGroup.ptp, screenBuilder: (_) => const ManagerPtpReportScreen(),
      ),
      _AlertItem(
        icon: Icons.apartment_outlined, color: kOrange,
        title: 'Recently created accounts (No activity)', subtitle: 'No follow-up done since account creation',
        count: recentlyCreatedNoActivity.length, countLabel: 'Accounts',
        amount: recentlyCreatedNoActivity.fold<double>(0.0, (s, c) => s + c.totalDue),
        group: _AlertGroup.followUp, screenBuilder: (_) => const ManagerNoFollowUpReportScreen(),
      ),
      _AlertItem(
        icon: Icons.autorenew, color: kGreen,
        title: 'High credit days accounts', subtitle: 'Credit days exceeded the limit',
        count: highCreditDays.length, countLabel: 'Accounts',
        amount: highCreditDays.fold<double>(0.0, (s, c) => s + c.totalDue),
        group: _AlertGroup.overdue, screenBuilder: (_) => const ManagerAgeingReceivablesReportScreen(),
      ),
      _AlertItem(
        icon: Icons.star_outline, color: kTeal,
        title: 'Top priority accounts', subtitle: 'High overdue + high amount',
        count: topPriority.length, countLabel: 'Accounts',
        amount: topPriority.fold<double>(0.0, (s, c) => s + c.totalDue),
        group: _AlertGroup.overdue, screenBuilder: (_) => const ManagerPriorityAccountsScreen(),
      ),
    ];

    final groupTotals = {
      for (final g in _AlertGroup.values) g: items.where((i) => i.group == g).fold(0, (s, i) => s + i.count),
    };
    final allTotal = items.fold(0, (s, i) => s + i.count);

    var visible = _activeGroup == null ? items : items.where((i) => i.group == _activeGroup).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      visible = visible.where((i) => i.title.toLowerCase().contains(q) || i.subtitle.toLowerCase().contains(q)).toList();
    }
    visible = List.of(visible)..sort((a, b) => _sortByCountDesc ? b.count.compareTo(a.count) : a.count.compareTo(b.count));

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
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
                          _statCards(overdueCustomers.length, ptpDueToday.length, noFollowUp.length, disputesAwaiting.length, ptpExpired.length + recentlyCreatedNoActivity.length + highCreditDays.length + topPriority.length),
                          const SizedBox(height: 16),
                          _tabRow(allTotal, groupTotals),
                          const SizedBox(height: 10),
                          _searchSortRow(),
                          const SizedBox(height: 10),
                          if (visible.isEmpty)
                            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No alerts match this search.', style: TextStyle(fontSize: 12, color: kMuted))))
                          else
                            ...visible.map((i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _alertCard(context, i))),
                          const SizedBox(height: 8),
                          _notificationsCard(context),
                          const SizedBox(height: 12),
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
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

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
                Text('Alerts & Reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kNavy)),
                Text('Stay on top of what needs your attention', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.filter_alt_outlined, () => _snack(context, 'Use the tabs below to filter by alert type.')),
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

  Widget _statCards(int overdue, int ptp, int followUp, int disputes, int other) {
    final cards = [
      (Icons.warning_amber_rounded, kRed, '$overdue', 'Overdue Alerts', 'Customers'),
      (Icons.hourglass_empty, kOrange, '$ptp', 'PTP Due Today', 'Promises'),
      (Icons.phone_disabled_outlined, kPurple, '$followUp', 'No Follow-up', 'Accounts'),
      (Icons.description_outlined, kBlue, '$disputes', 'Disputes Awaiting', 'Review'),
      (Icons.notifications_active_outlined, kGreen, '$other', 'Other Reminders', 'Items'),
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
            width: 118,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.15))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 16),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kDark, fontWeight: FontWeight.w600)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color))),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.5, color: kMuted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabRow(int allTotal, Map<_AlertGroup, int> groupTotals) {
    final tabs = <(_AlertGroup?, String, int)>[
      (null, 'All Alerts', allTotal),
      (_AlertGroup.overdue, 'Overdue', groupTotals[_AlertGroup.overdue]!),
      (_AlertGroup.ptp, 'PTP', groupTotals[_AlertGroup.ptp]!),
      (_AlertGroup.followUp, 'No Follow-up', groupTotals[_AlertGroup.followUp]!),
      (_AlertGroup.disputes, 'Disputes', groupTotals[_AlertGroup.disputes]!),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (group, label, count) = tabs[i];
          final selected = _activeGroup == group;
          return InkWell(
            onTap: () => setState(() => _activeGroup = group),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? kPurple : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? kPurple : kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : kDark)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(0.2) : kPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: selected ? Colors.white : kPurple)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _searchSortRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 12.5, color: kDark),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search, size: 18, color: kMuted),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: 'Search by customer name, ID or type',
              hintStyle: const TextStyle(fontSize: 11.5, color: kMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kNavy, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () => setState(() => _sortByCountDesc = !_sortByCountDesc),
          icon: const Icon(Icons.swap_vert, size: 15),
          label: const Text('Sort', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _alertCard(BuildContext context, _AlertItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: item.screenBuilder));
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: item.color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(item.icon, color: item.color, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kNavy)),
                  const SizedBox(height: 2),
                  Text(item.subtitle, style: const TextStyle(fontSize: 10.5, color: kMuted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${item.count} ${item.countLabel}', style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w600)),
                      if (item.amount != null) ...[
                        const Text('•', style: TextStyle(fontSize: 10.5, color: kMuted)),
                        Text('${item.amountLabel} ${_rupee.format(item.amount)}', style: TextStyle(fontSize: 10.5, color: item.color, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${item.count}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: item.color)),
                Text(item.countLabel, style: const TextStyle(fontSize: 9, color: kMuted)),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right, size: 16, color: kMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPurple.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: kPurple.withOpacity(0.15))),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kPurple.withOpacity(0.12), shape: BoxShape.circle), child: const Icon(Icons.notifications_none, color: kPurple, size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_notificationsEnabled ? 'Push notifications enabled' : 'Enable push notifications', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kNavy)),
                const SizedBox(height: 2),
                Text(_notificationsEnabled ? "You're set — new alerts will notify you in real-time." : 'Stay updated in real-time for important alerts and reminders.', style: const TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _notificationsEnabled
              ? const Icon(Icons.check_circle, color: kGreen, size: 22)
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: kPurple, side: const BorderSide(color: kPurple), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () {
                    setState(() => _notificationsEnabled = true);
                    _snack(context, 'Push notifications enabled for this device.');
                  },
                  child: const Text('Enable', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
        ],
      ),
    );
  }
}
