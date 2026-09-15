import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _crore(double v) => '${(v / 10000000).toStringAsFixed(2)} Cr';

/// Manager's Daily Recovery Summary — Target vs Received, branch-wise
/// breakdown and top customers by amount received, all derived live from
/// the shared store (real salesmen/PTPs/customers), matching the Manager
/// Reports visual language.
class ManagerDailyRecoverySummaryScreen extends StatefulWidget {
  final String initialBranch;
  const ManagerDailyRecoverySummaryScreen({super.key, this.initialBranch = 'All Branches'});

  @override
  State<ManagerDailyRecoverySummaryScreen> createState() => _ManagerDailyRecoverySummaryScreenState();
}

class _ManagerDailyRecoverySummaryScreenState extends State<ManagerDailyRecoverySummaryScreen> {
  String get _branch => context.read<AppStore>().branchFilter;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final branches = store.branchOptions;
    final now = DateTime.now();

    final salesmen = store.salesmen.where((s) => _branch == 'All Branches' || ((s['branch'] as String?) ?? 'Turning Point') == _branch).toList();
    final totalTarget = salesmen.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));
    final totalReceived = salesmen.fold(0.0, (s, m) => s + ((m['collectionAchieved'] as num).toDouble()));
    final variance = totalTarget - totalReceived;
    final achievementPercent = totalTarget <= 0 ? 0.0 : (totalReceived / totalTarget * 100).clamp(0, 999);

    final salesmenNames = salesmen.map((s) => s['name'] as String).toSet();
    final customerIds = store.customers.where((c) => salesmenNames.contains(c.assignedSalesmanId)).map((c) => c.id).toSet();
    final matured = store.ptps.where((p) => customerIds.contains(p.customerId) && (p.status == PtpStatus.kept || p.status == PtpStatus.partiallyKept)).toList();
    final paymentsCount = matured.length;
    final payingCustomerCount = matured.map((p) => p.customerId).toSet().length;

    final trend = store.collectionsTrendLast7Days;
    final maxTrend = trend.fold<double>(0, (m, t) => [m, (t['expected'] as num).toDouble(), (t['actual'] as num).toDouble()].reduce((a, b) => a > b ? a : b));
    final chartMax = maxTrend <= 0 ? 100000.0 : maxTrend * 1.15;
    final avgDailyTarget = trend.isEmpty ? 0.0 : trend.fold(0.0, (s, t) => s + ((t['expected'] as num).toDouble())) / trend.length;
    final avgDailyReceived = trend.isEmpty ? 0.0 : trend.fold(0.0, (s, t) => s + ((t['actual'] as num).toDouble())) / trend.length;
    Map<String, dynamic>? bestDay;
    for (final t in trend) {
      if (bestDay == null || ((t['actual'] as num).toDouble()) > ((bestDay['actual'] as num).toDouble())) bestDay = t;
    }

    // Branch-wise breakdown, derived from the real salesmen roster.
    final branchNames = {for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')}.toList()..sort();
    final branchRows = branchNames.map((b) {
      final inBranch = store.salesmen.where((s) => ((s['branch'] as String?) ?? 'Turning Point') == b);
      final target = inBranch.fold(0.0, (s, m) => s + ((m['collectionTarget'] as num).toDouble()));
      final received = inBranch.fold(0.0, (s, m) => s + ((m['collectionAchieved'] as num).toDouble()));
      return (branch: b, target: target, received: received, variance: target - received, achievement: target <= 0 ? 0.0 : (received / target * 100).clamp(0, 999).toDouble());
    }).where((r) => _branch == 'All Branches' || r.branch == _branch).toList()
      ..sort((a, b) => b.received.compareTo(a.received));

    // Top 5 customers by amount received, derived from real PTPs.
    final receivedByCustomer = <String, double>{};
    final paymentsByCustomer = <String, int>{};
    final lastModeByCustomer = <String, String>{};
    for (final p in matured) {
      receivedByCustomer[p.customerId] = (receivedByCustomer[p.customerId] ?? 0) + (p.amountReceived ?? 0);
      paymentsByCustomer[p.customerId] = (paymentsByCustomer[p.customerId] ?? 0) + 1;
      lastModeByCustomer[p.customerId] = p.paymentMode;
    }
    final topCustomerIds = receivedByCustomer.keys.toList()..sort((a, b) => receivedByCustomer[b]!.compareTo(receivedByCustomer[a]!));
    final topCustomers = topCustomerIds.take(5).map((id) {
      final c = store.customers.firstWhere((c) => c.id == id, orElse: () => store.customers.first);
      return (customer: c, received: receivedByCustomer[id]!, payments: paymentsByCustomer[id]!, mode: lastModeByCustomer[id]!);
    }).toList();

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
                  _dateBranchRow(branches),
                  const SizedBox(height: 14),
                  _statCards(totalTarget, totalReceived, variance, paymentsCount, payingCustomerCount),
                  const SizedBox(height: 20),
                  _recoveryTrendCard(trend, chartMax, avgDailyTarget, avgDailyReceived, bestDay, achievementPercent.toDouble()),
                  const SizedBox(height: 20),
                  _branchTable(branchRows, totalTarget, totalReceived, variance, achievementPercent.toDouble()),
                  const SizedBox(height: 20),
                  _topCustomersCard(context, topCustomers),
                  const SizedBox(height: 16),
                  _footer(store, now),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------
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
                Text('Daily Recovery Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                Text('Target vs Received summary for today', style: TextStyle(fontSize: 10.5, color: kMuted)),
              ],
            ),
          ),
          _headerIcon(Icons.calendar_today_outlined, () => _showDateInfo(context)),
          const SizedBox(width: 8),
          _headerIcon(Icons.filter_alt_outlined, () => _showFilterInfo(context)),
          const SizedBox(width: 8),
          _headerIcon(Icons.ios_share, () => _exportReport(context, store)),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
        child: Icon(icon, size: 17, color: kNavy),
      ),
    );
  }

  void _showDateInfo(BuildContext context) {
    showAppMessage(context, message: 'Showing data as on ${DateFormat('dd MMM yyyy').format(DateTime.now())}.');
  }

  void _showFilterInfo(BuildContext context) {
    showAppMessage(context, message: 'Use the Branch filter below to scope this report.');
  }

  void _exportReport(BuildContext context, AppStore store) {
    store.incrementReportsGenerated();
    showAppMessage(context, message: 'Report export started — you will be notified when it is ready.');
  }

  // -------------------------------------------------------------------
  // Date + Branch row
  // -------------------------------------------------------------------
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

  // -------------------------------------------------------------------
  // Stat cards
  // -------------------------------------------------------------------
  Widget _statCards(double target, double received, double variance, int payments, int customers) {
    final cards = [
      (Icons.gps_fixed, kPurple, _rupee.format(target), 'Total Target (₹)', '100%'),
      (Icons.swap_vert, kGreen, _rupee.format(received), 'Total Received (₹)', target <= 0 ? '0%' : '${(received / target * 100).clamp(0, 999).toStringAsFixed(2)}%'),
      (Icons.show_chart, kBlue, _rupee.format(variance), 'Variance (₹)', target <= 0 ? '0%' : '${(variance / target * 100).clamp(0, 999).toStringAsFixed(2)}%'),
      (Icons.account_balance_wallet_outlined, kOrange, '$payments', 'No. of Payments', 'Customers: $customers'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: cards.map((c) {
        final (icon, color, value, label, sub) = c;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.15))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 18),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kDark, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(fontSize: 9, color: kMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // -------------------------------------------------------------------
  // Recovery Trend
  // -------------------------------------------------------------------
  Widget _recoveryTrendCard(List<Map<String, dynamic>> trend, double chartMax, double avgTarget, double avgReceived, Map<String, dynamic>? bestDay, double achievement) {
    return InfoCard(
      children: [
        Row(
          children: [
            const Expanded(child: Text('Recovery Trend (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy))),
            _legendDash(kPurple, 'Target (₹)'),
            const SizedBox(width: 12),
            _legendDot(kGreen, 'Received (₹)'),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: chartMax,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(_crore(v), style: const TextStyle(fontSize: 8, color: kMuted)))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= trend.length) return const SizedBox();
                      return Padding(padding: const EdgeInsets.only(top: 6), child: Text(trend[i]['label'] as String, style: const TextStyle(fontSize: 8.5, color: kMuted)));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['expected'] as num).toDouble())],
                  isCurved: true,
                  color: kPurple,
                  barWidth: 2,
                  dashArray: [6, 4],
                  dotData: const FlDotData(show: true),
                ),
                LineChartBarData(
                  spots: [for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), (trend[i]['actual'] as num).toDouble())],
                  isCurved: true,
                  color: kGreen,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: kGreen.withOpacity(0.08)),
                ),
              ],
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: kBorder)),
        Row(
          children: [
            Expanded(child: _trendMetric('Average Daily Target', _crore(avgTarget), kDark)),
            Expanded(child: _trendMetric('Average Daily Received', _crore(avgReceived), kDark)),
            Expanded(child: _trendMetric('Best Day (Received)', bestDay == null ? '-' : '${_crore((bestDay['actual'] as num).toDouble())} (${bestDay['label']})', kGreen)),
            Expanded(child: _trendMetric('Achievement', '${achievement.toStringAsFixed(2)}%', kOrange)),
          ],
        ),
      ],
    );
  }

  Widget _trendMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color))),
      ],
    );
  }

  Widget _legendDash(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 14, height: 2, child: CustomPaint(painter: _DashPainter(color))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Branch table
  // -------------------------------------------------------------------
  Widget _branchTable(List<({String branch, double target, double received, double variance, double achievement})> rows, double totalTarget, double totalReceived, double totalVariance, double totalAchievement) {
    return InfoCard(
      children: [
        const Text('Target vs Received by Branch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(flex: 3, child: Text('Branch', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            Expanded(flex: 3, child: Text('Target (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            Expanded(flex: 3, child: Text('Received (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('Achv', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
          ],
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(r.branch, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark))),
                  Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(r.target), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark)))),
                  Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(r.received), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kGreen)))),
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(value: (r.achievement / 100).clamp(0, 1).toDouble(), strokeWidth: 2.5, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation<Color>(r.achievement >= 60 ? kGreen : (r.achievement >= 35 ? kOrange : kRed)))),
                      ],
                    ),
                  ),
                ],
              ),
            )),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
        Row(
          children: [
            const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kNavy))),
            Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(totalTarget), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kNavy)))),
            Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(totalReceived), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kGreen)))),
            Expanded(flex: 2, child: Text('${totalAchievement.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kOrange))),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Top 5 customers
  // -------------------------------------------------------------------
  Widget _topCustomersCard(BuildContext context, List<({dynamic customer, double received, int payments, String mode})> rows) {
    return InfoCard(
      children: [
        const Row(
          children: [
            Expanded(child: Text('Top 5 Customers (By Amount Received)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy))),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No payments received in this view.', style: TextStyle(fontSize: 12, color: kMuted)))
        else ...[
          const Row(
            children: [
              Expanded(flex: 4, child: Text('Customer', style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Received (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Mode', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.bold))),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.customer.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                          Text('${r.customer.branch}  ·  ${r.payments} payment${r.payments == 1 ? '' : 's'}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                        ],
                      ),
                    ),
                    Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_rupee.format(r.received), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kGreen)))),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Icon(_modeIcon(r.mode), size: 16, color: _modeColor(r.mode)),
                      ),
                    ),
                  ],
                ),
              )),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: kBorder)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_outlined, size: 13, color: _modeColor('NEFT')),
              const SizedBox(width: 4),
              const Text('NEFT', style: TextStyle(fontSize: 9.5, color: kMuted)),
              const SizedBox(width: 12),
              Icon(Icons.qr_code, size: 13, color: _modeColor('UPI')),
              const SizedBox(width: 4),
              const Text('UPI', style: TextStyle(fontSize: 9.5, color: kMuted)),
              const SizedBox(width: 12),
              Icon(Icons.receipt_long_outlined, size: 13, color: _modeColor('Cheque')),
              const SizedBox(width: 4),
              const Text('Cheque', style: TextStyle(fontSize: 9.5, color: kMuted)),
            ],
          ),
        ],
      ],
    );
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'UPI':
        return Icons.qr_code;
      case 'Cheque':
        return Icons.receipt_long_outlined;
      default:
        return Icons.account_balance_outlined;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'UPI':
        return kPurple;
      case 'Cheque':
        return kOrange;
      default:
        return kBlue;
    }
  }

  // -------------------------------------------------------------------
  // Footer
  // -------------------------------------------------------------------
  Widget _footer(AppStore store, DateTime now) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBlue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: kBlue.withOpacity(0.15))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: kBlue),
          const SizedBox(width: 8),
          Expanded(child: Text('All amounts are in INR. Data is as per payments received on ${DateFormat('dd MMM yyyy').format(now)}.', style: const TextStyle(fontSize: 10, color: kDark))),
          const SizedBox(width: 6),
          Text(DateFormat('hh:mm a').format(store.lastBusySync), style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => store.refreshBusySync()),
            child: const Icon(Icons.refresh, size: 15, color: kBlue),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + dashWidth, size.height / 2), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
