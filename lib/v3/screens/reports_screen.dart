import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/v3/screens/report_detail_screens.dart';
import 'package:salesman_mobile/v3/screens/more_menu_screen.dart';

const _navy = Color(0xFF1B2B48);
const _blue = Color(0xFF2563EB);

final _rupeeCompact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _dateRange = 'This Month';
  String _branch = 'All Branches';
  String _salesman = 'All Salesmen';
  ReportFilters _applied = const ReportFilters();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = ['All Branches', ...{for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}];
    // Values stay the internal salesman id (downstream reports match on it);
    // the dropdown only renders the real name.
    final salesmenNames = ['All Salesmen', ...store.salesmen.map((s) => s['name'] as String)];
    String salesmanLabel(String v) => v == 'All Salesmen' ? v : store.salesmanDisplayName(v);

    final reports = [
      (Icons.assignment_outlined, kBlue, 'Daily Recovery Summary', 'Collections, targets and daily closure', (BuildContext c) => DailyRecoverySummaryReport(filters: _applied)),
      (Icons.groups_outlined, kPurple, 'Salesman Performance Report', 'Score, target vs achieved, follow-up quality', (BuildContext c) => SalesmanPerformanceReport(filters: _applied)),
      (Icons.event_available_outlined, kGreen, 'PTP Report', 'Active, due today, kept and broken promises', (BuildContext c) => PtpReport(filters: _applied)),
      (Icons.link_off, kOrange, 'Broken PTP Report', 'Customers with failed payment commitments', (BuildContext c) => BrokenPtpReport(filters: _applied)),
      (Icons.help_outline, kIndigo, 'Dispute Status Report', 'Open, approved, resolved and pending disputes', (BuildContext c) => DisputeStatusReport(filters: _applied)),
      (Icons.pie_chart_outline, kBlue, 'Ageing Receivables Report', 'Outstanding by ageing bucket', (BuildContext c) => AgeingReceivablesReport(filters: _applied)),
      (Icons.swap_vert, kGreen, 'Expected vs Actual Collection', 'Compare commitments against real receipts', (BuildContext c) => ExpectedVsActualCollectionReport(filters: _applied)),
      (Icons.track_changes, kBlue, 'Recovery Target', 'Target vs actual recovery', (BuildContext c) => RecoveryTargetVsActualReport(filters: _applied)),
      (Icons.notifications_active_outlined, kOrange, 'No Follow-Up Accounts', 'Customers needing immediate attention', (BuildContext c) => NoFollowUpAccountsReport(filters: _applied)),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.menu, color: _navy), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoreMenuScreen()))),
                const Expanded(child: Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: _navy))),
              ],
            ),
            const SizedBox(height: 6),
            InfoCard(children: [
              _filterRow(Icons.calendar_today_outlined, kPurple, 'Date Range', _dateRange, ['Today', 'This Week', 'This Month', 'This Quarter', 'All Time'], (v) => setState(() => _dateRange = v)),
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: kBorder)),
              _filterRow(Icons.apartment_outlined, kBlue, 'Branch', _branch, branches, (v) => setState(() => _branch = v)),
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: kBorder)),
              _filterRow(Icons.person_outline, kBlue, 'Salesperson', _salesman, salesmenNames, (v) => setState(() => _salesman = v), labelFor: salesmanLabel),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => setState(() => _applied = ReportFilters(dateRange: _dateRange, branch: _branch, salesman: _salesman)),
                  icon: const Icon(Icons.filter_alt, size: 16),
                  label: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const Text('Quick Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
            const SizedBox(height: 10),
            _quickInsights(store),
            const SizedBox(height: 20),
            const Text('Available Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
              child: Column(
                children: reports.asMap().entries.map((entry) {
                  final i = entry.key;
                  final (icon, color, title, subtitle, builder) = entry.value;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () {
                          store.incrementReportsGenerated();
                          Navigator.push(context, MaterialPageRoute(builder: builder));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          child: Row(
                            children: [
                              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: color)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: _navy)),
                                    const SizedBox(height: 2),
                                    Text(subtitle, style: const TextStyle(fontSize: 10.5, color: kMuted)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, size: 18, color: kMuted),
                            ],
                          ),
                        ),
                      ),
                      if (i < reports.length - 1) const Divider(height: 1, color: kBorder),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterRow(IconData icon, Color color, String label, String value, List<String> options, ValueChanged<String> onChanged, {String Function(String)? labelFor}) {
    String text(String o) => labelFor != null ? labelFor(o) : o;
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kDark),
                  items: options.map((o) => DropdownMenuItem(value: o, child: Text(text(o), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) { if (v != null) onChanged(v); },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickInsights(AppStore store) {
    final keptPct = store.ptpKeptMtdPercent;
    final cards = <(IconData, Color, String, String, String)>[
      (Icons.account_balance_wallet_outlined, kBlue, _rupeeCompact.format(store.teamTotalOutstanding), 'Total Outstanding', '${store.customers.length} customers'),
      (Icons.shield_outlined, kRed, _rupeeCompact.format(store.moneyAtRisk), 'Money at Risk', '${store.atRiskAccounts.length} accounts'),
      (Icons.event_available_outlined, keptPct >= 75 ? kGreen : kOrange, '$keptPct%', 'PTP Kept (MTD)', 'Target 75%'),
      (Icons.priority_high, kPurple, '${store.openEscalationCases.length}', 'Open Escalations', 'L2 – L4'),
      (Icons.notifications_active_outlined, kOrange, '${store.noFollowUpAccounts.length}', 'No Follow-Up', '4+ days idle'),
      (Icons.assignment_late_outlined, kRed, '${store.overdueTaskCount}', 'Overdue Tasks', 'past deadline'),
    ];
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (icon, color, value, label, sub) = cards[i];
          return Container(
            width: 142,
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 14, color: color)),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w700)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kMuted)),
              ],
            ),
          );
        },
      ),
    );
  }
}
