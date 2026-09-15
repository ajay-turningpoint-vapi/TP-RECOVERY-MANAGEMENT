import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';

/// Manager view — the Recovery Executive's own performance at a glance:
/// how much is waiting on the RE and for how long, how fast decisions are
/// turned around, and how the RE is doing on the escalations they own.
/// Data: GET /api/reports/re-performance (reportService.getRePerformance).
class ManagerRePerformanceScreen extends StatelessWidget {
  const ManagerRePerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppStore>().apiClient;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kDark,
        title: const Text('RE Performance',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kDark)),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: api.getRePerformance(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
            }
            if (snap.hasError || snap.data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load RE performance.\n${snap.error ?? ''}',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: kMuted)),
                ),
              );
            }
            final d = snap.data!;
            final q = (d['queue'] as Map).cast<String, dynamic>();
            final t = (d['turnaround'] as Map).cast<String, dynamic>();
            final byRe = ((d['escalationsByRe'] as List?) ?? const []).cast<dynamic>();

            final totalPending = (q['totalPending'] as num?)?.toInt() ?? 0;
            final oldest = (q['oldestPendingDays'] as num?)?.toInt() ?? 0;
            final pendColor = totalPending == 0 ? kGreen : (totalPending < 5 ? kOrange : kRed);

            return ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // ---- Headline ----
                Row(
                  children: [
                    Expanded(child: _bigStat('Pending decisions', '$totalPending', pendColor)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _bigStat('Oldest waiting', oldest == 0 ? '—' : '${oldest}d',
                            oldest >= 7 ? kRed : (oldest >= 3 ? kOrange : kDark))),
                  ],
                ),
                const SizedBox(height: 18),

                // ---- Queue breakdown ----
                const SectionLabel('WAITING ON THE RE'),
                InfoCard(children: [
                  _queueRow('Disputes to approve', q['disputes']),
                  const Divider(height: 18, color: kBorder),
                  _queueRow('Payment claims to verify', q['paymentClaims']),
                  const Divider(height: 18, color: kBorder),
                  _queueRow('PTP corrections', q['ptpCorrections']),
                  const Divider(height: 18, color: kBorder),
                  _queueRow('Internal actions', q['internalActions']),
                ]),
                const SizedBox(height: 18),

                // ---- Turnaround ----
                const SectionLabel('DECISION TURNAROUND  (LAST 30 DAYS)'),
                InfoCard(children: [
                  KeyValueRow('Disputes decided', '${(t['disputesDecided30d'] as num?)?.toInt() ?? 0}'),
                  KeyValueRow('Avg time to decide', '${t['avgDecisionDays'] ?? 0} days',
                      valueColor: ((t['avgDecisionDays'] as num?)?.toDouble() ?? 0) >= 3 ? kRed : kDark),
                  KeyValueRow('Approved', '${(t['approvedPct'] as num?)?.toInt() ?? 0}%'),
                ]),
                const SizedBox(height: 18),

                // ---- Escalations owned, per RE ----
                const SectionLabel('ESCALATIONS OWNED'),
                if (byRe.isEmpty)
                  const InfoCard(children: [Text('No Recovery Executive on record.', style: TextStyle(fontSize: 12.5, color: kMuted))])
                else
                  ...byRe.map((raw) {
                    final r = (raw as Map).cast<String, dynamic>();
                    final open = (r['openEscalations'] as num?)?.toInt() ?? 0;
                    final overdue = (r['overdueEscalations'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InfoCard(children: [
                        Text('${r['reName']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavy)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _miniStat('Open', '$open', open > 0 ? kOrange : kGreen)),
                            Expanded(child: _miniStat('Overdue', '$overdue', overdue > 0 ? kRed : kGreen)),
                            Expanded(child: _miniStat('Resolved 30d', '${(r['resolvedEscalations30d'] as num?)?.toInt() ?? 0}', kDark)),
                            Expanded(child: _miniStat('Avg resolve', '${r['avgResolveDays'] ?? 0}d', kDark)),
                          ],
                        ),
                      ]),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bigStat(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _miniStat(String label, String value, Color color) => Column(
        children: [
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 1),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, color: kMuted, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _queueRow(String label, dynamic statRaw) {
    final s = ((statRaw as Map?) ?? const {}).cast<String, dynamic>();
    final count = (s['count'] as num?)?.toInt() ?? 0;
    final oldest = (s['oldestDays'] as num?)?.toInt() ?? 0;
    final avg = (s['avgAgeDays'] as num?)?.toInt() ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12.5, color: kDark, fontWeight: FontWeight.w600)),
              if (count > 0 && oldest > 0)
                Text('oldest ${oldest}d  ·  avg ${avg}d', style: const TextStyle(fontSize: 10, color: kMuted)),
            ],
          ),
        ),
        Text('$count',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: count == 0 ? kGreen : (oldest >= 7 ? kRed : kOrange))),
      ],
    );
  }
}
