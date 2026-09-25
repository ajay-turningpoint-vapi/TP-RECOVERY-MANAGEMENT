// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v2/screens/customer_list_screen.dart';
import 'package:salesman_mobile/v2/widgets/recovery_score_breakdown.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

// Indian digit grouping (₹1,23,456 not ₹123,456) — the plain
// `toStringAsFixed` interpolation this file used before didn't group at
// all, so a lakh-plus figure read as one long undifferentiated run of
// digits instead of the lakh/crore grouping every other real-money screen
// in this app already uses.
final _rupee =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// customerId -> total PTP amount the salesman promised that falls due
  /// today (summed if a customer has more than one scheduled PTP today).
  /// A PTP due today flips scheduled -> pendingVerification at the very
  /// midnight sync that starts that day (see ptpVerificationService.js), so
  /// both statuses count as "due today" here.
  Map<String, double> _ptpDueTodayAmountByCustomer(AppStore store) {
    final now = DateTime.now();
    final map = <String, double>{};
    for (final p in store.ptps) {
      if (p.status != PtpStatus.scheduled &&
          p.status != PtpStatus.pendingVerification) continue;
      if (p.promiseDate.year != now.year ||
          p.promiseDate.month != now.month ||
          p.promiseDate.day != now.day) continue;
      map[p.customerId] = (map[p.customerId] ?? 0) + p.amountPromised;
    }
    return map;
  }

  /// The day's whole workload for the Today's Recovery drill-down: every
  /// assigned customer still actionable ("Start Recovery" queue), PLUS any
  /// already worked today (now parked in Waiting / Monitoring but still shown
  /// so their recorded outcome can be reviewed / edited). Actionable ones
  /// first, then today's done ones — deduped.
  List<Customer> _todaysRecoveryCustomers(AppStore store) {
    final actionable = store.myCustomers
        .where((c) => c.currentRecoveryState != 'Waiting / Monitoring')
        .toList();
    final seen = actionable.map((c) => c.id).toSet();
    // Grounded in the real audit trail (store.recoveryDoneTodayCustomerIds),
    // not customer.updatedAt — the daily BUSY sync bumps updatedAt for the
    // whole portfolio regardless of activity, which used to make nearly
    // every resolved customer look "done today" right after that sync ran.
    final done = store.myCustomers
        .where((c) =>
            c.currentRecoveryState == 'Waiting / Monitoring' &&
            store.recoveryDoneTodayCustomerIds.contains(c.id) &&
            !seen.contains(c.id))
        .toList();
    return [...actionable, ...done];
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    // store.brokenPtpCount / mgmtInstructionCount / physicalVisitDueCount
    // are company-wide totals (used correctly by the Manager screens) — the
    // salesperson's own dashboard must scope them to their own portfolio,
    // not every salesman's customers/tasks.
    final myBrokenPtpCount = store.myCustomers
        .where((c) => c.reasonForAction.toLowerCase().contains('broken ptp'))
        .length;
    // Every open physical-visit task the salesman owns — including the one
    // auto-created on the 3rd No Answer (deadline next day 10 AM), which
    // must show here from the moment it's raised, not only once overdue.
    final myPhysicalVisitTasks = store.myTasks
        .where((t) =>
            t.type == TaskType.physicalVisit &&
            t.status != TaskStatus.completed)
        .toList();
    final myPhysicalVisitDueCount = myPhysicalVisitTasks.length;
    final myPhysicalVisitCustomerIds =
        myPhysicalVisitTasks.map((t) => t.customerId).toSet();
    // store.recoveryTarget / expectedCollection are also company-wide totals
    // (correctly used by the Manager reports screen) — scope them to this
    // salesperson's own portfolio and to PTPs actually due today.
    // This salesperson's portfolio-wide money position.
    final myTotalOutstanding =
        store.myCustomers.fold<double>(0.0, (s, c) => s + c.totalOutstanding);
    final myTotalOverdue = store.myCustomers
        .where((c) => c.totalDue > 0)
        .fold<double>(0.0, (s, c) => s + c.totalDue);
    // Recovery Target = the current month's tier percentage of total
    // overdue. Months cycle through the four fixed business tiers:
    // Jan/May/Sep -> 25%, Feb/Jun/Oct -> 35%, Mar/Jul/Nov -> 50%,
    // Apr/Aug/Dec -> 70%.
    const monthTierPct = <double>[0.25, 0.35, 0.50, 0.70];
    final myRecoveryTargetPct =
        monthTierPct[(DateTime.now().month - 1) % monthTierPct.length];
    final myRecoveryTarget = myTotalOverdue * myRecoveryTargetPct;
    final myPtpsDueToday = store.ptps.where((p) {
      final now = DateTime.now();
      return (p.status == PtpStatus.scheduled ||
              p.status == PtpStatus.pendingVerification) &&
          p.promiseDate.year == now.year &&
          p.promiseDate.month == now.month &&
          p.promiseDate.day == now.day &&
          store.myCustomers.any((c) => c.id == p.customerId);
    }).toList();
    final myPtpDueTodayAmount =
        myPtpsDueToday.fold(0.0, (s, p) => s + p.amountPromised);
    // Actual recovery so far — same primitive the Recovery Target report
    // uses: amount received on kept / partially-kept PTPs of my customers.
    final myCustomerIds = store.myCustomers.map((c) => c.id).toSet();
    final myRecovered = store.ptps
        .where((p) =>
            (p.status == PtpStatus.kept ||
                p.status == PtpStatus.partiallyKept) &&
            myCustomerIds.contains(p.customerId))
        .fold<double>(0.0, (s, p) => s + (p.amountReceived ?? 0));
    final aboveTarget = myRecovered >= myRecoveryTarget;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0052CC),
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Hello, ${store.currentUserFullName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white)),
                  const Text('Here\'s your recovery summary',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            if (store.myRecoveryScoreComponents?['total'] != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showRecoveryScoreBreakdown(context, store),
                child: _buildRecoveryScoreBadge(
                    store.myRecoveryScoreComponents!['total']!.round()),
              ),
            ],
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Portfolio money position — the two figures a salesperson
              // asks for first: what's owed overall and what's overdue now.
              Row(
                children: [
                  Expanded(
                    // Same 1.8 aspect ratio as the grid cards below.
                    child: AspectRatio(
                      aspectRatio: 1.8,
                      child: _buildStatCard(
                        context,
                        'Total Outstanding',
                        _rupee.format(myTotalOutstanding),
                        Icons.account_balance_wallet_outlined,
                        const Color(0xFF0052CC),
                        const Color(0xFFE3EDFB),
                        onTap: () {
                          final list = [...store.myCustomers]..sort((a, b) =>
                              b.totalOutstanding.compareTo(a.totalOutstanding));
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CustomerListScreen(
                                      title: 'Total Outstanding',
                                      customers: list,
                                      sortControlsView: true)));
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Same 1.8 aspect ratio as the grid cards below.
                    child: AspectRatio(
                      aspectRatio: 1.8,
                      child: _buildStatCard(
                        context,
                        'Total Overdue',
                        _rupee.format(myTotalOverdue),
                        Icons.currency_rupee,
                        const Color(0xFFE53935),
                        const Color(0xFFFDECEC),
                        onTap: () {
                          final list = store.myCustomers
                              .where((c) => c.totalDue > 0)
                              .toList()
                            ..sort((a, b) => b.totalDue.compareTo(a.totalDue));
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CustomerListScreen(
                                      title: 'Total Overdue',
                                      customers: list,
                                      overdueView: true)));
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Top Grid (2x2)
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.8,
                children: [
                  Builder(builder: (_) {
                    final recoveryCustomers = _todaysRecoveryCustomers(store);
                    final total = recoveryCustomers.length;
                    final doneToday = store.recoveryDoneTodayCount;
                    return _buildStatCard(
                      context,
                      "Today's Recovery Tasks",
                      '$doneToday/$total',
                      Icons.savings_outlined,
                      const Color(0xFF2E7D32),
                      const Color(0xFFE8F5E9),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CustomerListScreen(
                                    title: "Today's Recovery Tasks",
                                    customers: recoveryCustomers,
                                    showNextAction: true,
                                    todaysRecoveryView: true,
                                    sortControlsView: true)));
                      },
                    );
                  }),
                  _buildStatCard(
                    context,
                    'Broken PTP',
                    myBrokenPtpCount.toString(),
                    Icons.broken_image_outlined,
                    const Color(0xFFE53935),
                    const Color(0xFFFFEBEE),
                    tag: 'Attention Needed',
                    tagColor: const Color(0xFFFFEBEE),
                    tagTextColor: const Color(0xFFD32F2F),
                    onTap: () {
                      final filtered = store.myCustomers
                          .where(
                              (c) => c.reasonForAction.contains('Broken PTP'))
                          .toList();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CustomerListScreen(
                                  title: 'Broken PTPs',
                                  customers: filtered,
                                  sortControlsView: true)));
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Physical Visits',
                    myPhysicalVisitDueCount.toString(),
                    Icons.directions_walk,
                    const Color(0xFF00897B),
                    const Color(0xFFE0F2F1),
                    onTap: () {
                      final filtered = store.myCustomers
                          .where((c) =>
                              myPhysicalVisitCustomerIds.contains(c.id) ||
                              c.primaryNextAction.contains('Physical Visit'))
                          .toList();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CustomerListScreen(
                                  title: 'Physical Visits',
                                  customers: filtered,
                                  sortControlsView: true)));
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Total Collected',
                    _rupee.format(myRecovered),
                    Icons.payments_outlined,
                    const Color(0xFF2E7D32),
                    const Color(0xFFE8F5E9),
                    onTap: () {
                      final amountByCustomer = <String, double>{};
                      for (final p in store.ptps) {
                        if ((p.status == PtpStatus.kept ||
                                p.status == PtpStatus.partiallyKept) &&
                            myCustomerIds.contains(p.customerId)) {
                          amountByCustomer[p.customerId] =
                              (amountByCustomer[p.customerId] ?? 0) +
                                  (p.amountReceived ?? 0);
                        }
                      }
                      final filtered = store.myCustomers
                          .where((c) => amountByCustomer.containsKey(c.id))
                          .toList();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CustomerListScreen(
                                  title: 'Total Collected',
                                  customers: filtered,
                                  highlightAmountByCustomerId: amountByCustomer,
                                  highlightAmountLabel: 'COLLECTED',
                                  sortControlsView: true)));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Target Blue Box
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0052CC),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _blueMetricChip(
                              label: 'Recovery Target',
                              value: _rupee.format(myRecoveryTarget),
                              icon: Icons.track_changes,
                              trailing: _targetStatusIcon(aboveTarget),
                              onTap: () {
                                final filtered = store.myCustomers
                                    .where((c) => c.totalDue > 0)
                                    .toList();
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CustomerListScreen(
                                            title: 'Recovery Target Today',
                                            customers: filtered)));
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _blueMetricChip(
                              label: 'PTP Due Today',
                              value: _rupee.format(myPtpDueTodayAmount),
                              icon: Icons.handshake_outlined,
                              trailing: _countPill(
                                  '${myPtpsDueToday.length} ${myPtpsDueToday.length == 1 ? 'PTP' : 'PTPs'}'),
                              onTap: () {
                                final amountByCustomer =
                                    _ptpDueTodayAmountByCustomer(store);
                                final filtered = store.myCustomers
                                    .where((c) =>
                                        amountByCustomer.containsKey(c.id))
                                    .toList();
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CustomerListScreen(
                                            title: 'PTP Due Today',
                                            customers: filtered,
                                            highlightAmountByCustomerId:
                                                amountByCustomer,
                                            highlightAmountLabel:
                                                'PTP DUE TODAY',
                                            sortControlsView: true)));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Financial data updated 10:56 AM',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0052CC),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final next = store.getNextCustomer();
                          if (next != null) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => Customer360Screen(
                                        customer: next, recoveryQueue: true)));
                          } else {
                            showAppMessage(context,
                                message:
                                    'All assigned customers have been processed. Excellent work!');
                          }
                        },
                        child: const Text('START RECOVERY',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1.2)),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Compact Recovery Score chip shown at the far right of the greeting:
  // a white pill with a band-coloured score ring and a stacked label,
  // so it reads clearly against the blue app bar.
  Widget _buildRecoveryScoreBadge(int score) {
    final Color band = score >= 80
        ? const Color(0xFF2E7D32)
        : score >= 60
            ? const Color(0xFFF57C00)
            : const Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: band, width: 2),
            ),
            child: Text('$score%',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: band,
                    height: 1.0)),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RECOVERY',
                  style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2)),
              Text('SCORE',
                  style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2)),
            ],
          ),
          const Icon(Icons.expand_more, size: 16, color: Colors.white70),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value,
      IconData icon, Color iconColor, Color iconBgColor,
      {String? tag,
      Color? tagColor,
      Color? tagTextColor,
      VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration:
                      BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 14),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4A5568))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: title == 'Broken PTP' ||
                                    title == 'Total Overdue'
                                ? const Color(0xFFE53935)
                                : (title == 'Tasks Due Today'
                                    ? const Color(0xFF8E24AA)
                                    : (title == 'PTP Due Today'
                                        ? const Color(0xFFFBC02D)
                                        : const Color(0xFF1B2B48))))),
                  ),
                ),
                if (tag != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                          color: tagColor,
                          borderRadius: BorderRadius.circular(4)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(tag,
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: tagTextColor)),
                      ),
                    ),
                  )
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A tappable metric chip for the blue "Target" card — translucent white
  /// on the brand blue, chevron to signal the drill-down.
  Widget _blueMetricChip({
    required String label,
    required String value,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon,
                      size: 14, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            height: 1.15,
                            fontWeight: FontWeight.w500)),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: Colors.white.withValues(alpha: 0.75)),
                ],
              ),
              if (trailing != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: trailing)
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small coloured badge: green up-trend when recovery is at/above the
  /// target, red down-trend when below it.
  Widget _targetStatusIcon(bool above) {
    final color = above ? const Color(0xFF2E7D32) : const Color(0xFFE53935);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(above ? Icons.trending_up : Icons.trending_down,
              size: 12, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(above ? 'Above target' : 'Below target',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _countPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: const Color(0xFFFBC02D),
          borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFF3E2C00),
              fontSize: 11,
              fontWeight: FontWeight.w800)),
    );
  }
}
