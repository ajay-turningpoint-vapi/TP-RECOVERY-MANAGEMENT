import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

enum _TeamTab { performance, target, overdue, branch }

/// Process compliance is judged purely on the salesman's own conduct —
/// never on collection %, so a hard portfolio never reads as a process
/// failure (same rule applied in manager_salesman_performance_screen.dart).
String _processCompliance(Map<String, dynamic> s) {
  final avg = ((s['taskCompletionRate'] as int) + (s['validNextActionRate'] as int)) / 2;
  if (avg >= 85) return 'Good';
  if (avg >= 65) return 'Fair';
  return 'Poor';
}

Color _processComplianceColor(String v) => v == 'Good' ? kGreen : (v == 'Fair' ? kOrange : kRed);

/// Customer difficulty is judged purely on portfolio composition — never
/// on the salesman's own task/process discipline.
String _customerDifficulty(Map<String, dynamic> s) {
  final total = s['customers'] as int;
  if (total <= 0) return 'Low';
  final hardCount = (s['brokenPtps'] as int) + (s['escalatedCustomers'] as int) + (s['highRiskCustomers'] as int);
  final ratio = hardCount / total;
  if (ratio >= 0.4) return 'High';
  if (ratio >= 0.15) return 'Moderate';
  return 'Low';
}

Color _customerDifficultyColor(String v) => v == 'High' ? kRed : (v == 'Moderate' ? kOrange : kGreen);

/// Manager's Team Recovery — overview of the salesmen team's performance and
/// recovery, with real per-tab sorting (Performance/Target/Overdue/Branch),
/// search, an Achievement Distribution breakdown, and a view-only detail
/// sheet per salesman (no reassignment/instruction actions).
class ManagerTeamRecoveryScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerTeamRecoveryScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerTeamRecoveryScreen> createState() => _ManagerTeamRecoveryScreenState();
}

class _ManagerTeamRecoveryScreenState extends State<ManagerTeamRecoveryScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }
  String _query = '';
  _TeamTab _tab = _TeamTab.performance;

  double _achievementOf(Map<String, dynamic> s) {
    final target = (s['collectionTarget'] as num).toDouble();
    final received = (s['collectionAchieved'] as num).toDouble();
    return target <= 0 ? 0.0 : (received / target * 100).clamp(0, 999).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;

    var salesmen = store.salesmen.where((s) => _branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == _branch).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      salesmen = salesmen.where((s) => (s['name'] as String).toLowerCase().contains(q) || (s['empId'] as String).toLowerCase().contains(q) || (((s['branch'] as String?) ?? 'Turning Point')).toLowerCase().contains(q)).toList();
    }

    switch (_tab) {
      case _TeamTab.performance:
        salesmen.sort((a, b) => _achievementOf(b).compareTo(_achievementOf(a)));
        break;
      case _TeamTab.target:
        salesmen.sort((a, b) => ((b['collectionTarget'] as num).toDouble()).compareTo((a['collectionTarget'] as num).toDouble()));
        break;
      case _TeamTab.overdue:
        salesmen.sort((a, b) => ((b['totalOverdue'] as num).toDouble()).compareTo((a['totalOverdue'] as num).toDouble()));
        break;
      case _TeamTab.branch:
        salesmen.sort((a, b) {
          final c = (((a['branch'] as String?) ?? 'Turning Point')).compareTo(((b['branch'] as String?) ?? 'Turning Point'));
          return c != 0 ? c : _achievementOf(b).compareTo(_achievementOf(a));
        });
        break;
    }

    final totalTarget = salesmen.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));
    final totalReceived = salesmen.fold(0.0, (s, m) => s + ((m['collectionAchieved'] as num).toDouble()));
    final totalOverdue = salesmen.fold(0.0, (s, m) => s + ((m['totalOverdue'] as num).toDouble()));
    final avgAchievement = totalTarget <= 0 ? 0.0 : (totalReceived / totalTarget * 100).clamp(0, 999).toDouble();

    final buckets = <String, List<Map<String, dynamic>>>{
      '≥ 90%': [], '75% - 89%': [], '50% - 74%': [], '25% - 49%': [], '< 25%': [],
    };
    for (final s in salesmen) {
      final a = _achievementOf(s);
      if (a >= 90) {
        buckets['≥ 90%']!.add(s);
      } else if (a >= 75) {
        buckets['75% - 89%']!.add(s);
      } else if (a >= 50) {
        buckets['50% - 74%']!.add(s);
      } else if (a >= 25) {
        buckets['25% - 49%']!.add(s);
      } else {
        buckets['< 25%']!.add(s);
      }
    }

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
                      _dateBranchRow(branches),
                      const SizedBox(height: 14),
                      _statCards(salesmen.length, totalTarget, totalReceived, avgAchievement, totalOverdue),
                      const SizedBox(height: 16),
                      _tabRow(),
                      const SizedBox(height: 10),
                      _searchExportRow(context, store),
                      const SizedBox(height: 10),
                      _table(context, salesmen, totalTarget, totalReceived, avgAchievement, totalOverdue),
                      const SizedBox(height: 16),
                      _achievementDistribution(context, buckets, salesmen.length),
                      const SizedBox(height: 16),
                      _footer(context, store),
                    ],
                  ),
                ),
              ],
            );
            if (constraints.maxWidth <= 900) return content;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: content,
              ),
            );
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
                Text('Team Recovery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kNavy)),
                Text('Overview of team performance and recovery', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _snack(context, 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.')),
          const SizedBox(width: 8),
          _headerIcon(Icons.filter_alt_outlined, () => _snack(context, 'Use the Branch filter and tabs below to scope this list.')),
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

  Widget _dateBranchRow(List<String> branches) {
    return Row(
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
                Flexible(child: Text('As on ${DateFormat('dd MMM yyyy').format(DateTime.now())}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark))),
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
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark),
                      items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) { if (v != null) { context.read<AppStore>().setBranchFilter(v); setState(() {}); } },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCards(int count, double target, double received, double achievement, double overdue) {
    final cards = [
      (Icons.groups_outlined, kPurple, '$count', 'Total Salesman', 'Active $count'),
      (Icons.gps_fixed, kBlue, _rupee.format(target), 'Total Target (₹)', '100%'),
      (Icons.swap_vert, kGreen, _rupee.format(received), 'Total Received (₹)', '100%'),
      (Icons.show_chart, kOrange, '${achievement.toStringAsFixed(2)}%', 'Achievement', ''),
      (Icons.warning_amber_rounded, kRed, _rupee.format(overdue), 'Overdue (₹)', ''),
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
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color))),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: kDark, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: kMuted)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabRow() {
    final tabs = [
      (_TeamTab.performance, 'By Performance'),
      (_TeamTab.target, 'By Target'),
      (_TeamTab.overdue, 'By Overdue'),
      (_TeamTab.branch, 'By Branch'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (value, label) = tabs[i];
          final selected = _tab == value;
          return InkWell(
            onTap: () => setState(() => _tab = value),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? kPurple : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? kPurple : kBorder),
              ),
              child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : kDark)),
            ),
          );
        },
      ),
    );
  }

  Widget _searchExportRow(BuildContext context, AppStore store) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 12.5, color: kDark),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12), border: InputBorder.none, hintText: 'Search by name, employee ID or branch', hintStyle: TextStyle(fontSize: 11.5, color: kMuted)),
                  ),
                ),
                const Icon(Icons.search, size: 18, color: kMuted),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () {
            store.incrementReportsGenerated();
            _snack(context, 'Team Recovery report exported.');
          },
          icon: const Icon(Icons.download, size: 15),
          label: const Text('Export', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, List<Map<String, dynamic>> salesmen, double totalTarget, double totalReceived, double avgAchievement, double totalOverdue) {
    return InfoCard(
      children: [
        const Row(
          children: [
            Expanded(flex: 4, child: Text('Salesman / Employee ID', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            Expanded(flex: 3, child: Text('Branch', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            Expanded(flex: 3, child: Text('Target/Received', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('Achv', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
          ],
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
        if (salesmen.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('No salesmen match this search.', style: TextStyle(fontSize: 12, color: kMuted))))
        else
          ...salesmen.map((s) => _salesmanRow(context, s)),
        if (salesmen.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total / Avg.', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kNavy)),
                    Text('${salesmen.length} Salesman', style: const TextStyle(fontSize: 10, color: kMuted)),
                  ],
                ),
              ),
              const Expanded(flex: 3, child: SizedBox()),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(totalTarget), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kBlue))),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(totalReceived), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen))),
                  ],
                ),
              ),
              Expanded(flex: 2, child: Text('${avgAchievement.toStringAsFixed(2)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kOrange))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _salesmanRow(BuildContext context, Map<String, dynamic> s) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    final branch = ((s['branch'] as String?) ?? 'Turning Point');
    final target = (s['collectionTarget'] as num).toDouble();
    final received = (s['collectionAchieved'] as num).toDouble();
    final overdue = (s['totalOverdue'] as num).toDouble();
    final achievement = _achievementOf(s);
    final color = achievement >= 75 ? kGreen : (achievement >= 50 ? kOrange : kRed);

    return InkWell(
      onTap: () => _showSalesmanDetail(context, s, achievement, color),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(radius: 15, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 10.5, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                        Text(branch, style: const TextStyle(fontSize: 9.5, color: kMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 3, child: Text(branch, style: const TextStyle(fontSize: 11, color: kDark, fontWeight: FontWeight.w600))),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(target), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark))),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(_rupee.format(received), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kGreen))),
                  Text('Overdue ${_rupee.format(overdue)}', style: const TextStyle(fontSize: 8.5, color: kRed)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${achievement.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(width: 44, height: 5, child: LinearProgressIndicator(value: (achievement / 100).clamp(0, 1).toDouble(), backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(color))),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 16, color: kMuted),
          ],
        ),
      ),
    );
  }

  Widget _achievementDistribution(BuildContext context, Map<String, List<Map<String, dynamic>>> buckets, int total) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Achievement Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
                  Text('(By Percentage)', style: TextStyle(fontSize: 10, color: kMuted)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _showDistributionDetail(context, buckets, total),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View Details', style: TextStyle(color: kBlue, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  Icon(Icons.chevron_right, size: 15, color: kBlue),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: buckets.entries.map((e) {
            final count = e.value.length;
            final pct = total <= 0 ? 0.0 : (count / total * 100);
            final color = e.key == '≥ 90%'
                ? kGreen
                : e.key == '75% - 89%'
                    ? kGreen
                    : e.key == '50% - 74%'
                        ? kOrange
                        : e.key == '25% - 49%'
                            ? kOrange
                            : kRed;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                  child: Column(
                    children: [
                      Text(e.key, textAlign: TextAlign.center, maxLines: 1, style: const TextStyle(fontSize: 8.5, color: kMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kDark)),
                      const SizedBox(height: 2),
                      Text('${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showDistributionDetail(BuildContext context, Map<String, List<Map<String, dynamic>>> buckets, int total) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Achievement Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
              const SizedBox(height: 12),
              ...buckets.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12.5, color: kDark, fontWeight: FontWeight.w600))),
                        Text('${e.value.length} of $total', style: const TextStyle(fontSize: 12.5, color: kMuted)),
                      ],
                    ),
                  )),
              const SizedBox(height: 4),
              const Text('Manager view is read-only — reassignment and instruction actions are taken by the Recovery Executive.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSalesmanDetail(BuildContext context, Map<String, dynamic> s, double achievement, Color color) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    final compliance = _processCompliance(s);
    final difficulty = _customerDifficulty(s);
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
                  CircleAvatar(radius: 20, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 13, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                        Text('${(s['branch'] as String?) ?? 'Turning Point'} Branch', style: const TextStyle(fontSize: 12, color: kMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _kv('Target', _rupee.format(s['collectionTarget'])),
              _kv('Received', _rupee.format(s['collectionAchieved'])),
              _kv('Overdue', _rupee.format(s['totalOverdue'])),
              _kv('Achievement', '${achievement.toStringAsFixed(2)}%'),
              _kv('PTP Kept %', '${s['ptpKeptPercent']}%'),
              _kv('Customers', '${s['customers']}'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _processComplianceColor(compliance).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _processComplianceColor(compliance).withOpacity(0.2))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Process Compliance', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                          Text(compliance, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _processComplianceColor(compliance))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _customerDifficultyColor(difficulty).withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _customerDifficultyColor(difficulty).withOpacity(0.2))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Customer Difficulty', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                          Text(difficulty, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _customerDifficultyColor(difficulty))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _kv('Task Completion Rate', '${s['taskCompletionRate']}%'),
              _kv('Valid Next Action Rate', '${s['validNextActionRate']}%'),
              _kv('Broken PTPs', '${s['brokenPtps']}'),
              _kv('Escalated Accounts (L1-L4)', '${s['escalatedCustomers']} of ${s['customers']}'),
              _kv('High Risk Accounts', '${s['highRiskCustomers']} of ${s['customers']}'),
              const SizedBox(height: 8),
              const Text('Manager view is read-only — reassignment and instruction actions are taken by the Recovery Executive.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
            ],
          ),
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
          Text(value, style: const TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppStore store) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Team recovery figures are real-time and based on the data available as on selected date.', style: TextStyle(fontSize: 10.5, color: kDark)),
                const SizedBox(height: 2),
                Text('Last synced ${DateFormat('hh:mm a').format(store.lastBusySync)}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => store.refreshBusySync()),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.refresh, size: 16, color: kBlue)),
          ),
        ],
      ),
    );
  }
}
