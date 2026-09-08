import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/v3/screens/manager_daily_recovery_summary_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_team_recovery_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_salesman_performance_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_ptp_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_broken_ptp_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_dispute_status_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_dispute_management_summary_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_ageing_receivables_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_expected_vs_actual_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_no_follow_up_report_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_priority_accounts_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_alerts_reminders_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_management_attention_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_recovery_owner_screen.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Manager Reports — a real-time report launcher over the same shared data
/// as the RE's Reports tab, restyled to match the Manager's dashboard
/// visual language (Quick Summary card + Reports list + Custom Reports).
class ManagerReportsScreen extends StatefulWidget {
  final void Function(int)? onNavigate;
  const ManagerReportsScreen({super.key, this.onNavigate});

  @override
  State<ManagerReportsScreen> createState() => _ManagerReportsScreenState();
}

class _ManagerReportsScreenState extends State<ManagerReportsScreen> {
  String _branch = 'All Branches';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = ['All Branches', ...{for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}];

    final target = store.recoveryTarget;
    final received = store.totalReceivedAllTime;
    final achievedPercent = target <= 0 ? 0.0 : (received / target * 100).clamp(0, 999);
    final overdue = store.totalOverdueAmount;
    final overduePercentOfTarget = target <= 0 ? 0.0 : (overdue / target * 100).clamp(0, 999);
    final salesmenCount = _branch == 'All Branches' ? store.salesmen.length : store.salesmen.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == _branch).length;

    final reports = [
      (Icons.warning_amber_rounded, kRed, 'Management Attention', 'L4 cases requiring an executive decision.', (BuildContext c) => const ManagerManagementAttentionScreen()),
      (Icons.assignment_outlined, kBlue, 'Daily Recovery Summary', 'Target vs Received summary for the day.', (BuildContext c) => ManagerDailyRecoverySummaryScreen(initialBranch: _branch)),
      (Icons.groups_outlined, kPurple, 'Team Recovery', 'Salesmen team performance and recovery overview.', (BuildContext c) => ManagerTeamRecoveryScreen(initialBranch: _branch)),
      (Icons.badge_outlined, kTeal, 'Recovery Owner', 'Every recovery owner with a real target/received/achievement summary.', (BuildContext c) => const ManagerRecoveryOwnerScreen()),
      (Icons.priority_high, kRed, 'Priority Accounts', 'High-priority customer accounts needing attention.', (BuildContext c) => ManagerPriorityAccountsScreen(initialBranch: _branch)),
      (Icons.notifications_active_outlined, kOrange, 'Alerts & Reminders', 'Stay on top of what needs your attention.', (BuildContext c) => const ManagerAlertsRemindersScreen()),
      (Icons.person_outline, kGreen, 'Salesman Performance', 'Individual salesman performance and achievement.', (BuildContext c) => ManagerSalesmanPerformanceScreen(initialBranch: _branch)),
      (Icons.event_available_outlined, kOrange, 'PTP Reports', 'Promise to Pay reports and analysis.', (BuildContext c) => ManagerPtpReportScreen(initialBranch: _branch)),
      (Icons.link_off, kRed, 'Broken PTP Reports', 'Analysis of broken promises and follow-up status.', (BuildContext c) => ManagerBrokenPtpReportScreen(initialBranch: _branch)),
      (Icons.gavel_outlined, kBlue, 'Dispute Status Report', 'Summary of all disputes by status and reason.', (BuildContext c) => ManagerDisputeStatusReportScreen(initialBranch: _branch)),
      (Icons.summarize_outlined, kPurple, 'Dispute Management – Summary', 'Overview of all disputes and their status.', (BuildContext c) => ManagerDisputeManagementSummaryScreen(initialBranch: _branch)),
      (Icons.hourglass_empty, kTeal, 'Ageing Receivables', 'Outstanding amounts ageing bucket wise.', (BuildContext c) => ManagerAgeingReceivablesReportScreen(initialBranch: _branch)),
      (Icons.pie_chart_outline, kPurple, 'Expected vs Actual Recovery', 'Compare expected recovery vs actual received.', (BuildContext c) => ManagerExpectedVsActualScreen(initialBranch: _branch)),
      (Icons.groups_outlined, kMuted, 'No Follow-up Report', 'Accounts with no follow-up in the selected period.', (BuildContext c) => ManagerNoFollowUpReportScreen(initialBranch: _branch)),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: kNavy)),
                      Text('View performance, recovery and analytical reports', style: TextStyle(fontSize: 11.5, color: kMuted)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _showHelp(context),
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Help', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 14, color: kPurple),
                        const SizedBox(width: 6),
                        Flexible(child: Text('As on ${DateFormat('dd MMM yyyy').format(DateTime.now())}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                    child: Row(
                      children: [
                        const Icon(Icons.apartment_outlined, size: 14, color: kBlue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _branch,
                              isDense: true,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down, size: 15, color: kMuted),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark),
                              items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) { if (v != null) setState(() => _branch = v); },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('Quick Summary (As on ${DateFormat('dd MMM yyyy').format(DateTime.now())})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy))),
                GestureDetector(
                  onTap: () => widget.onNavigate?.call(0),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View Dashboard', style: TextStyle(color: kBlue, fontSize: 11.5, fontWeight: FontWeight.bold)),
                      Icon(Icons.chevron_right, size: 15, color: kBlue),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _quickSummary(target, received, achievedPercent.toDouble(), overdue, overduePercentOfTarget.toDouble(), salesmenCount),
            const SizedBox(height: 20),
            const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy)),
            const SizedBox(height: 8),
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
                                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
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
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _statTile((IconData, Color, String, String, String) c) {
    final (icon, color, value, label, sub) = c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withOpacity(0.14), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: kDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kMuted)),
        ],
      ),
    );
  }

  Widget _quickSummary(double target, double received, double achievedPercent, double overdue, double overduePercentOfTarget, int salesmenCount) {
    final tiles = <(IconData, Color, String, String, String)>[
      (Icons.gps_fixed, kPurple, _rupee.format(target), 'Total Target (₹)', '100%'),
      (Icons.swap_vert, kGreen, _rupee.format(received), 'Total Received (₹)', '${achievedPercent.toStringAsFixed(2)}%'),
      (Icons.show_chart, kOrange, '${achievedPercent.toStringAsFixed(2)}%', 'Achievement', 'vs Target'),
      (Icons.warning_amber_rounded, kRed, _rupee.format(overdue), 'Total Overdue (₹)', '${overduePercentOfTarget.toStringAsFixed(2)}% of Target'),
      (Icons.groups_outlined, kBlue, '$salesmenCount', 'Total Salesman', 'Active'),
    ];
    return InfoCard(
      children: [
        Row(children: [
          Expanded(child: _statTile(tiles[0])),
          const SizedBox(width: 10),
          Expanded(child: _statTile(tiles[1])),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _statTile(tiles[2])),
          const SizedBox(width: 10),
          Expanded(child: _statTile(tiles[3])),
        ]),
        const SizedBox(height: 10),
        _statTile(tiles[4]),
      ],
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('About Reports', style: TextStyle(fontWeight: FontWeight.bold, color: kNavy)),
        content: const Text(
          'Reports are generated in real time from the current recovery data. Use the Branch filter to scope every report, tap a report to view its full breakdown, or use Build Your Own Report to create a custom view.',
          style: TextStyle(fontSize: 13, color: kDark),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it', style: TextStyle(color: kBlue, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
