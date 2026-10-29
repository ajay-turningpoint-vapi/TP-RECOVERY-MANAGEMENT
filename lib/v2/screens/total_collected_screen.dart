import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// One line item in a Total Collected section — the customer it came from,
/// the amount, and a short subtitle (date / mode) shown under the name.
class CollectedRow {
  final Customer customer;
  final double amount;
  final String subtitle;
  const CollectedRow({required this.customer, required this.amount, required this.subtitle});
}

/// Drill-down for the salesman dashboard's "Total Collected" card — unlike
/// [CustomerListScreen] (one highlighted amount per customer), this shows
/// the three components that make up the card's figure: a fixed "How this
/// adds up" summary, then a tab per component so its customer rows can be
/// browsed one list at a time instead of one long scroll.
class TotalCollectedScreen extends StatelessWidget {
  final double ptpTotal;
  final double advanceTotal;
  final double paymentClaimTotal;
  final List<CollectedRow> ptpRows;
  final List<CollectedRow> advanceRows;
  final List<CollectedRow> paymentClaimRows;

  const TotalCollectedScreen({
    super.key,
    required this.ptpTotal,
    required this.advanceTotal,
    required this.paymentClaimTotal,
    required this.ptpRows,
    required this.advanceRows,
    required this.paymentClaimRows,
  });

  static const _ptpColor = Color(0xFF2E7D32);
  static const _advanceColor = Color(0xFF0052CC);
  static const _claimColor = Color(0xFF8A6D0B);

  @override
  Widget build(BuildContext context) {
    final grandTotal = ptpTotal + advanceTotal + paymentClaimTotal;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF1B2B48),
          title: const Text('Total Collected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48))),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _summaryCard(grandTotal),
            ),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: Color(0xFF1B2B48),
                unselectedLabelColor: Color(0xFF5A6B87),
                indicatorColor: Color(0xFF0052CC),
                labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                unselectedLabelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                isScrollable: false,
                tabs: [
                  Tab(text: 'PTP Payments'),
                  Tab(text: 'Advance Payments'),
                  Tab(text: 'Payment Already Made'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _sectionList(context, ptpTotal, ptpRows, _ptpColor),
                  _sectionList(context, advanceTotal, advanceRows, _advanceColor),
                  _sectionList(context, paymentClaimTotal, paymentClaimRows, _claimColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(double grandTotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How this adds up', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48))),
          const SizedBox(height: 14),
          _summaryRow('PTP Payments', ptpTotal, _ptpColor),
          const SizedBox(height: 8),
          _summaryRow('Advance Payments', advanceTotal, _advanceColor),
          const SizedBox(height: 8),
          _summaryRow('Payment Already Made (Verified)', paymentClaimTotal, _claimColor),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Color(0xFFEDF2F7))),
          _summaryRow('Total Collected', grandTotal, const Color(0xFF1B2B48), bold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amount, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: bold ? 13 : 12.5, color: bold ? const Color(0xFF1B2B48) : const Color(0xFF5A6B87), fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        Text(_rupee.format(amount), style: TextStyle(fontSize: bold ? 15 : 13, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _sectionList(BuildContext context, double total, List<CollectedRow> rows, Color color) {
    if (rows.isEmpty) {
      return const Center(child: Text('Nothing here yet.', style: TextStyle(color: Color(0xFF5A6B87), fontSize: 12.5)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = rows[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: r.customer))),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.15))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.customer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                      const SizedBox(height: 3),
                      Text(r.subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF5A6B87))),
                    ],
                  ),
                ),
                Text(_rupee.format(r.amount), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5A6B87)),
              ],
            ),
          ),
        );
      },
    );
  }
}
