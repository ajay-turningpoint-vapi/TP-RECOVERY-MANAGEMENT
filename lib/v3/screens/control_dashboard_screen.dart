import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v3/screens/needs_attention_screen.dart';
import 'package:salesman_mobile/v3/screens/five_pm_control_screen.dart';
import 'package:salesman_mobile/v3/screens/company_recovery_queue_screen.dart';
import 'package:salesman_mobile/v3/screens/ptp_list_screen.dart';
import 'package:salesman_mobile/v3/screens/escalations_screen.dart';
import 'package:salesman_mobile/v3/screens/approvals_list_screen.dart';
import 'package:salesman_mobile/v3/screens/report_detail_screens.dart' show SalesmanScoreDetailScreen;

const _bg = Color(0xFFF7F8FA);
const _dark = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _border = Color(0xFFEEF1F5);

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

const List<Color> _avatarPalette = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
];

class ControlDashboardScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  const ControlDashboardScreen({super.key, required this.onNavigate});

  @override
  State<ControlDashboardScreen> createState() => _ControlDashboardScreenState();
}

class _ControlDashboardScreenState extends State<ControlDashboardScreen> {
  String _branchFilter = 'All Branches';
  int _visibleSalesmen = 5;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    List<Map<String, dynamic>> salesmen = store.salesmen;
    if (_branchFilter != 'All Branches') {
      // Same null-safe fallback as the filter's own option list below —
      // otherwise selecting 'Turning Point' would compare it against a raw
      // null and match nobody.
      salesmen = salesmen.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == _branchFilter).toList();
    }
    final visible = salesmen.take(_visibleSalesmen).toList();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, store),
                  _buildDateBranchRow(store),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildStatCards(context, store),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildAttentionSection(context, store),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildPerformanceSection(context, salesmen, visible),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------
  Widget _buildHeader(BuildContext context, AppStore store) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, ${store.currentUserFullName}!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _dark)),
                const Text('Recovery Executive', style: TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined, color: _dark, size: 19),
            tooltip: '5 PM Control',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FivePmControlScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBranchRow(AppStore store) {
    // s['branch'] is null for the overwhelming majority of real salesmen
    // (BUSY sync never populates it — confirmed live: 30 of 32 users) — an
    // unguarded `as String` here crashed this whole screen for every RE on
    // load. 'Turning Point' groups them under one real, honest filter option
    // rather than a crash.
    final branches = ['All Branches', ...{for (final s in store.salesmen) (s['branch'] as String?) ?? 'Turning Point'}];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 15, color: _dark),
              const SizedBox(width: 6),
              Text('Today, ${DateFormat('dd MMM yyyy').format(DateTime.now())}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _dark)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _branchFilter,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 15, color: _muted),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _muted),
                items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                onChanged: (v) => setState(() {
                  _branchFilter = v!;
                  _visibleSalesmen = 5;
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Stat cards
  // -------------------------------------------------------------------
  Widget _buildStatCards(BuildContext context, AppStore store) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final scheduledPtps = store.ptps.where((p) => p.status == PtpStatus.scheduled).toList();
    final scheduledAmount = scheduledPtps.fold<double>(0, (s, p) => s + p.amountPromised);
    final overduePtps = scheduledPtps.where((p) => p.promiseDate.isBefore(startOfToday)).toList();
    final overduePtpAmount = overduePtps.fold<double>(0, (s, p) => s + p.amountPromised);
    final brokenAmount = store.brokenPtps.fold<double>(0, (s, p) => s + p.amountPromised);
    // Same population as reportService.getDashboard's dueTodayPtpAmount/
    // dueTodayPtpCount (server) — kept in sync here so the "Expected
    // Collection Today" card's list matches its own number exactly.
    final dueTodayPtps = store.ptps
        .where((p) => (p.status == PtpStatus.scheduled || p.status == PtpStatus.pendingVerification) && !p.promiseDate.isBefore(startOfToday) && p.promiseDate.isBefore(startOfToday.add(const Duration(days: 1))))
        .toList();

    void go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    final cards = [
      _StatCardData(Icons.account_balance_wallet_outlined, const Color(0xFF2563EB), 'Total Outstanding', _rupee.format(store.teamTotalOutstanding), '${store.customers.length} Customers', _muted,
          onTap: () => go(const CompanyRecoveryQueueScreen(showOutstanding: true))),
      _StatCardData(Icons.currency_rupee, const Color(0xFFDC2626), 'Total Overdue', _rupee.format(store.totalOverdueAmount), '${store.totalOverdueCustomerCount} Customers', _muted,
          onTap: () => go(const CompanyRecoveryQueueScreen())),
      // Same data as the old "Today's PTPs" card (scheduled PTPs whose
      // promise date is today — server: reportService.getDashboard's
      // dueTodayPtpAmount/dueTodayPtpCount), just renamed to match how the
      // business actually talks about it and moved up into the first
      // visible row (was last in this scrollable row, off-screen until
      // scrolled to) since it's one of the first things an RE wants to see.
      _StatCardData(Icons.event_available_outlined, const Color(0xFF2563EB), 'Expected Collection Today', _rupee.format(store.dueTodayPtpAmount), '${store.dueTodayPtpCount} PTPs Active Today', _muted,
          onTap: () => go(PtpListScreen(title: 'Expected Collection Today', subtitle: '${dueTodayPtps.length} PTP(s) promised for today', ptps: dueTodayPtps))),
      // Amount shown as the prominent `value` (large/bold) and count as the
      // smaller `sub` line — matching Total Outstanding/Overdue above, so
      // the money figure is what actually stands out on every card in this
      // row, not the count.
      _StatCardData(Icons.handshake_outlined, const Color(0xFF7C3AED), 'Total PTPs', _rupee.format(scheduledAmount), '${scheduledPtps.length} PTPs', _muted,
          onTap: () => go(PtpListScreen(title: 'Total PTPs', subtitle: '${scheduledPtps.length} scheduled PTP(s)', ptps: scheduledPtps, amountColor: const Color(0xFF7C3AED)))),
      _StatCardData(Icons.link_off, const Color(0xFFDC2626), 'Total Broken PTPs', _rupee.format(brokenAmount), '${store.brokenPtps.length} Broken', const Color(0xFFDC2626),
          onTap: () => go(PtpListScreen(title: 'Total Broken PTPs', subtitle: '${store.brokenPtps.length} broken PTP(s)', ptps: store.brokenPtps, amountColor: const Color(0xFFDC2626)))),
      _StatCardData(Icons.event_busy_outlined, const Color(0xFFEA580C), "Today's Overdue", _rupee.format(overduePtpAmount), '${overduePtps.length} Overdue', const Color(0xFFEA580C),
          onTap: () => go(PtpListScreen(title: "Today's Overdue", subtitle: '${overduePtps.length} scheduled PTP(s) past their promise date', ptps: overduePtps, amountColor: const Color(0xFFEA580C)))),
    ];

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 150, child: _statCard(cards[i])),
      ),
    );
  }

  Widget _statCard(_StatCardData c) {
    return InkWell(
      onTap: c.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 128,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: c.color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(c.icon, color: c.color, size: 15),
                ),
                const Icon(Icons.chevron_right, size: 15, color: _muted),
              ],
            ),
            Text(c.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.w600, height: 1.2)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(c.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _dark)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(c.sub, style: TextStyle(fontSize: 9.5, color: c.subColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Needs Your Attention
  // -------------------------------------------------------------------
  Widget _buildAttentionSection(BuildContext context, AppStore store) {
    void openTab(int tab) => Navigator.push(context, MaterialPageRoute(builder: (_) => NeedsAttentionScreen(initialTab: tab)));
    final overdueTaskSalesmen = store.tasks.where((t) => t.isOverdue).map((t) => t.ownerId).toSet().length;

    // Ordered by urgency: act-now first (queue not being worked, a promise
    // already broken, an active RE-owned escalation), then act-soon
    // (behind target, recovery stalled), then the approvals queue.
    final tiles = [
      _AttentionTileData(Icons.assignment_late_outlined, const Color(0xFFDC2626), '$overdueTaskSalesmen', 'Overdue\nTasks', 'Not working queue',
          onTap: () => openTab(8)),
      _AttentionTileData(Icons.link_off, const Color(0xFFDC2626), '${store.brokenPtps.length}', 'Broken\nPTPs', 'Review / escalate',
          onTap: () => openTab(11)),
      // L3 and L4 used to be two separate tiles, but both opened the same
      // EscalationsScreen (just a different starting tab) — one real
      // "Escalations" tile covering both is simpler and avoids sending an
      // RE to the same screen twice for what reads as two different things.
      _AttentionTileData(Icons.priority_high, const Color(0xFF9333EA), '${store.openEscalationCases.length}', 'Escalations', 'L2 / L3 / L4',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EscalationsScreen()))),
      _AttentionTileData(Icons.trending_down, const Color(0xFFEA580C), '${store.salesmenOverdueTargetsCount}', 'Salesman Needing\nAttention', 'Behind target',
          onTap: () => openTab(2)),
      _AttentionTileData(Icons.help_outline, const Color(0xFFB45309), '${store.noValidNextActionCustomers.length}', 'No Next\nAction', 'Recovery stalled',
          onTap: () => openTab(9)),
      // Pending Approvals replaces the old, narrower "Outcome Edit
      // Requests" tile — it's every pending "salesperson asked for a
      // decision" item (disputes, PTP corrections, task extensions,
      // outcome edits/corrections) in one real count, see
      // AppStore.pendingApprovalsCount / ApprovalsListScreen.
      _AttentionTileData(Icons.fact_check_outlined, const Color(0xFFDB2777), '${store.pendingApprovalsCount}', 'Pending\nApprovals', 'Approve / Reject',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalsListScreen()))),
      _AttentionTileData(Icons.warning_amber_rounded, const Color(0xFFDC2626), '${store.criticalApprovalsCount}', 'Critical\nApprovals', 'High priority',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalsListScreen(onlyCritical: true)))),
    ];
    final visibleAttentionCount = tiles.fold(0, (s, t) => s + int.parse(t.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Needs Your Attention', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: _dark)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20),
              child: Text('$visibleAttentionCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NeedsAttentionScreen())),
              child: const Text('View All  ›', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 134,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 1),
            physics: const BouncingScrollPhysics(),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(width: 150, child: _attentionTile(tiles[i])),
          ),
        ),
      ],
    );
  }

  Widget _attentionTile(_AttentionTileData t) {
    return InkWell(
      onTap: t.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 134,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(t.icon, color: t.color, size: 18),
            Text(t.value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: t.color)),
            Text(t.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: _dark, fontWeight: FontWeight.w600, height: 1.2)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(t.tag, style: TextStyle(fontSize: 8.5, color: t.color, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Salesmen Performance
  // -------------------------------------------------------------------
  Widget _buildPerformanceSection(BuildContext context, List<Map<String, dynamic>> all, List<Map<String, dynamic>> visible) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Salesmen Performance (Today)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: _dark))),
              if (all.length >= 10)
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NeedsAttentionScreen())),
                  child: const Text('View All  ›', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(flex: 5, child: Text('Salesman', style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Total Overdue', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Due Today', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Tasks', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Kept %', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: _muted, fontWeight: FontWeight.bold))),
              SizedBox(width: 14),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: _border)),
          if (all.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: Text('No salesmen match this filter.', style: TextStyle(fontSize: 12, color: _muted))))
          else
            ...visible.asMap().entries.map((entry) => _performanceRow(context, entry.value, entry.key)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Showing 1 to ${visible.length} of ${all.length} Salesmen', style: const TextStyle(fontSize: 11, color: _muted)),
              if (visible.length < all.length)
                GestureDetector(
                  onTap: () => setState(() => _visibleSalesmen = (_visibleSalesmen + 5).clamp(0, all.length)),
                  child: const Text('Load More  ⌄', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _performanceRow(BuildContext context, Map<String, dynamic> s, int index) {
    final name = s['name'] as String;
    final displayName = (s['fullName'] as String?) ?? name;
    final initials = displayName.trim().split(RegExp(r'\s+')).map((p) => p[0]).take(2).join().toUpperCase();
    final color = _avatarPalette[index % _avatarPalette.length];
    final totalOverdue = (s['totalOverdue'] as num).toDouble();
    final dueToday = (s['dueTodayPtps'] as num).toDouble();
    // 'Calls' column had no real data source (no call-log table exists) —
    // replaced with the real, already-tracked Task Completion Rate.
    final taskCompletionRate = s['taskCompletionRate'] as int;
    final kept = s['ptpKeptPercent'] as int;
    final keptColor = kept >= 75 ? const Color(0xFF16A34A) : (kept >= 60 ? const Color(0xFFEA580C) : const Color(0xFFDC2626));

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesmanScoreDetailScreen(salesman: s, store: context.read<AppStore>()))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              // Was flex: 3, competing with two currency columns of the same
              // weight — any name past ~5 characters hard-truncated to
              // "AAKA…". Widened, and the name itself now shrinks to fit
              // (like the numeric columns already did) instead of clipping,
              // so a real full name (even a long one) stays fully legible.
              flex: 5,
              child: Row(
                children: [
                  CircleAvatar(radius: 13, backgroundColor: color.withOpacity(0.15), child: Text(initials, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(displayName, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _dark)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(_rupee.format(totalOverdue), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark)),
              ),
            ),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(_rupee.format(dueToday), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text('$taskCompletionRate%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark)),
            ),
            Expanded(
              flex: 2,
              child: Text('$kept%', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: keptColor)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _StatCardData {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final Color subColor;
  final VoidCallback? onTap;
  _StatCardData(this.icon, this.color, this.label, this.value, this.sub, this.subColor, {this.onTap});
}

class _AttentionTileData {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String tag;
  final VoidCallback? onTap;
  _AttentionTileData(this.icon, this.color, this.value, this.label, this.tag, {this.onTap});
}
