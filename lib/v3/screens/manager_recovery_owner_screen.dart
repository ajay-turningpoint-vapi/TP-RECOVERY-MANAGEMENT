import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

// Owner table columns — fixed widths (not Expanded/flex) so a long name
// gets real room instead of being squeezed by the numeric columns; the
// table scrolls horizontally when it doesn't fit instead of shrinking
// everything down to illegible text.
const double _ownerColName = 160;
const double _ownerColBranch = 90;
const double _ownerColAmounts = 110;
const double _ownerColAchv = 60;
const double _ownerColTrailing = 26;
const double _ownerColGap = 10;
const double _ownerTableWidth = _ownerColName + _ownerColBranch + _ownerColAmounts + _ownerColAchv + _ownerColTrailing + _ownerColGap * 4;

/// Manager's Recovery Owner — View All: every salesman with a real
/// target/received/achievement/overdue summary, derived from the shared
/// store. View-only (no reassignment or instruction actions).
class ManagerRecoveryOwnerScreen extends StatefulWidget {
  const ManagerRecoveryOwnerScreen({super.key});

  @override
  State<ManagerRecoveryOwnerScreen> createState() => _ManagerRecoveryOwnerScreenState();
}

class _ManagerRecoveryOwnerScreenState extends State<ManagerRecoveryOwnerScreen> {
  String get _branch => context.read<AppStore>().branchFilter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;

    var owners = store.salesmen.where((s) => _branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == _branch).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      owners = owners.where((s) => (s['name'] as String).toLowerCase().contains(q) || (s['empId'] as String).toLowerCase().contains(q) || (((s['branch'] as String?) ?? 'Turning Point')).toLowerCase().contains(q)).toList();
    }

    final totalTarget = owners.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));
    final totalReceived = owners.fold(0.0, (s, m) => s + ((m['collectionAchieved'] as num).toDouble()));
    final totalOverdue = owners.fold(0.0, (s, m) => s + ((m['totalOverdue'] as num).toDouble()));
    final achievementPercent = totalTarget <= 0 ? 0.0 : (totalReceived / totalTarget * 100).clamp(0, 999).toDouble();

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, store),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _searchBar(),
                  const SizedBox(height: 10),
                  _dateBranchRow(branches),
                  const SizedBox(height: 14),
                  _statCards(owners.length, totalTarget, totalReceived, achievementPercent, totalOverdue),
                  const SizedBox(height: 16),
                  _table(context, owners, totalTarget, totalReceived, achievementPercent, totalOverdue),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: kNavy), tooltip: 'Back', onPressed: () => Navigator.pop(context)),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recovery Owner – View All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: kNavy)),
                Text('All recovery owners with summary of performance', style: TextStyle(fontSize: 10, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _snack(context, 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.')),
          const SizedBox(width: 8),
          _headerIcon(Icons.filter_alt_outlined, () => _snack(context, 'Use the Branch filter below to scope this list.')),
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

  Widget _searchBar() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(fontSize: 12.5, color: kDark),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.search, size: 18, color: kMuted),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        hintText: 'Search by name, employee ID or branch',
        hintStyle: const TextStyle(fontSize: 12, color: kMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
      ),
    );
  }

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
      (Icons.person_outline, kPurple, '$count', 'Total Owners'),
      (Icons.gps_fixed, kBlue, _rupee.format(target), 'Total Target (₹)'),
      (Icons.swap_vert, kGreen, _rupee.format(received), 'Total Received (₹)'),
      (Icons.show_chart, kOrange, '${achievement.toStringAsFixed(2)}%', 'Achievement'),
      (Icons.warning_amber_rounded, kRed, _rupee.format(overdue), 'Overdue (₹)'),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (icon, color, value, label) = cards[i];
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _table(BuildContext context, List<Map<String, dynamic>> owners, double totalTarget, double totalReceived, double totalAchievement, double totalOverdue) {
    return InfoCard(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _ownerTableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SizedBox(width: _ownerColName, child: Text('Owner Name / ID', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _ownerColGap),
                    SizedBox(width: _ownerColBranch, child: Text('Branch', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _ownerColGap),
                    SizedBox(width: _ownerColAmounts, child: Text('Target/Received', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _ownerColGap),
                    SizedBox(width: _ownerColAchv, child: Text('Achv', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
                    SizedBox(width: _ownerColGap),
                    SizedBox(width: _ownerColTrailing),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                if (owners.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('No recovery owners match this search.', style: TextStyle(fontSize: 12, color: kMuted))))
                else
                  ...owners.map((s) => _ownerRow(context, s)),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
                Row(
                  children: [
                    SizedBox(
                      width: _ownerColName,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: kNavy)),
                          Text('${owners.length} Owners', style: const TextStyle(fontSize: 10, color: kMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: _ownerColGap),
                    const SizedBox(width: _ownerColBranch),
                    const SizedBox(width: _ownerColGap),
                    SizedBox(
                      width: _ownerColAmounts,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_rupee.format(totalTarget), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kBlue)),
                          Text(_rupee.format(totalReceived), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen)),
                        ],
                      ),
                    ),
                    const SizedBox(width: _ownerColGap),
                    SizedBox(width: _ownerColAchv, child: Text('${totalAchievement.toStringAsFixed(2)}%', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kOrange))),
                    const SizedBox(width: _ownerColGap),
                    const SizedBox(width: _ownerColTrailing),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ownerRow(BuildContext context, Map<String, dynamic> s) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
    final branch = ((s['branch'] as String?) ?? 'Turning Point');
    final target = (s['collectionTarget'] as num).toDouble();
    final received = (s['collectionAchieved'] as num).toDouble();
    final overdue = (s['totalOverdue'] as num).toDouble();
    final achievement = target <= 0 ? 0.0 : (received / target * 100).clamp(0, 999).toDouble();
    final color = achievement >= 75 ? kGreen : (achievement >= 50 ? kOrange : kRed);

    return InkWell(
      onTap: () => _showOwnerDetail(context, s, achievement, color),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _ownerColName,
              child: Row(
                children: [
                  CircleAvatar(radius: 15, backgroundColor: avatarColorFor(name).withOpacity(0.15), child: Text(initialsFor(name), style: TextStyle(color: avatarColorFor(name), fontSize: 10.5, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: kBlue.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                          child: const Text('Salesman', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: kBlue)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _ownerColGap),
            SizedBox(width: _ownerColBranch, child: Text(branch, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kDark, fontWeight: FontWeight.w600))),
            const SizedBox(width: _ownerColGap),
            SizedBox(
              width: _ownerColAmounts,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_rupee.format(target), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kDark)),
                  Text(_rupee.format(received), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: kGreen)),
                  Text('Overdue ${_rupee.format(overdue)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8.5, color: kRed)),
                ],
              ),
            ),
            const SizedBox(width: _ownerColGap),
            SizedBox(
              width: _ownerColAchv,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(width: 24, height: 24, child: CircularProgressIndicator(value: (achievement / 100).clamp(0, 1).toDouble(), strokeWidth: 2.5, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(color))),
                  const SizedBox(height: 2),
                  Text('${achievement.toStringAsFixed(0)}%', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
            const SizedBox(width: _ownerColGap),
            const SizedBox(width: _ownerColTrailing, child: Icon(Icons.chevron_right, size: 16, color: kMuted)),
          ],
        ),
      ),
    );
  }

  void _showOwnerDetail(BuildContext context, Map<String, dynamic> s, double achievement, Color color) {
    final name = (s['fullName'] as String?) ?? s['name'] as String;
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
}
