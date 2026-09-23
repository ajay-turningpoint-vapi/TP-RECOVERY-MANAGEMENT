import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/widgets/data_loading.dart' show LoadingAppBarStrip;

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

/// A plain, real list of PTPs — what an RE actually wants from a dashboard
/// stat card (see control_dashboard_screen.dart): "show me who's in this
/// number", not a fresh analytics report. Every PTP-related card
/// ("Expected Collection Today", "Total PTPs", "Today's Overdue") lands
/// here with a different pre-filtered `ptps` list; nothing here is
/// re-derived — the caller decides exactly what belongs in the list.
class PtpListScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<PromiseToPay> ptps;
  final Color amountColor;

  const PtpListScreen({super.key, required this.title, required this.subtitle, required this.ptps, this.amountColor = _dark});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final rows = [...ptps]..sort((a, b) => a.promiseDate.compareTo(b.promiseDate));
    final totalAmount = rows.fold<double>(0, (s, p) => s + p.amountPromised);

    Customer customerFor(String id) => store.customers.firstWhere((c) => c.id == id, orElse: () => store.customers.first);

    String statusLabel(PtpStatus s) {
      switch (s) {
        case PtpStatus.scheduled:
          return 'Scheduled';
        case PtpStatus.pendingVerification:
          return 'Pending Verification';
        case PtpStatus.kept:
          return 'Kept';
        case PtpStatus.partiallyKept:
          return 'Partially Kept';
        case PtpStatus.broken:
          return 'Broken';
        case PtpStatus.financialSyncPending:
          return 'Sync Pending';
      }
    }

    Color statusColor(PtpStatus s) {
      switch (s) {
        case PtpStatus.kept:
        case PtpStatus.partiallyKept:
          return const Color(0xFF16A34A);
        case PtpStatus.broken:
          return const Color(0xFFDC2626);
        default:
          return const Color(0xFF2563EB);
      }
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _dark)),
        bottom: const LoadingAppBarStrip(color: Color(0xFF2563EB)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
                  ),
                  Text(fmt.format(totalAmount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: amountColor)),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Nothing here.', style: TextStyle(color: _muted, fontSize: 13)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final p = rows[i];
                        final c = customerFor(p.customerId);
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c))),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                                      const SizedBox(height: 3),
                                      Text('${store.salesmanDisplayName(c.assignedSalesmanId)} · ${c.branch}', style: const TextStyle(fontSize: 11, color: _muted)),
                                      const SizedBox(height: 3),
                                      Text('Promised ${DateFormat('dd MMM yyyy').format(p.promiseDate)}', style: const TextStyle(fontSize: 11, color: _muted)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: statusColor(p.status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text(statusLabel(p.status), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: statusColor(p.status))),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(fmt.format(p.amountPromised), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                                    const SizedBox(height: 4),
                                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
