import 'package:flutter/material.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

/// The "Why this score" bottom sheet — the weighted breakdown of the
/// salesperson's Recovery Score (RMS-05). Shared by the Profile screen's
/// score card and the dashboard app-bar score badge.
void showRecoveryScoreBreakdown(BuildContext context, AppStore store) {
  final breakdown = store.myRecoveryScoreComponents ?? const <String, num>{};
  final total = (breakdown['total'] ?? 0).toInt();
  final band = recoveryScoreBand(total);
  final bandColor = recoveryScoreBandColor(band);

  const components = <(IconData, Color, String, String, int)>[
    (Icons.currency_rupee, Color(0xFF2563EB), 'collectionPerformance', 'Collection Performance', 40),
    (Icons.call_outlined, Color(0xFF16A34A), 'followUpDiscipline', 'Follow-Up Discipline', 20),
    (Icons.event_available_outlined, Color(0xFF7C3AED), 'ptpDiscipline', 'PTP Discipline & Quality', 15),
    (Icons.trending_down, Color(0xFFEA580C), 'oldOutstandingReduction', 'Old Outstanding Reduction', 10),
    (Icons.notifications_active_outlined, Color(0xFFDC2626), 'noFollowUpControl', 'No-Follow-Up Control', 10),
    (Icons.fact_check_outlined, Color(0xFF0D9488), 'processDiscipline', 'Process/Evidence Discipline', 5),
  ];

  Widget componentRow(IconData icon, Color color, String label, int weight, num value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$label ($weight%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B2B48))),
                      Text('$value%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (value.clamp(0, 100)) / 100,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFF0F2F5),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [bandColor, bandColor.withValues(alpha: 0.7)]), shape: BoxShape.circle),
                  child: Text('$total%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Why this score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1B2B48))),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: bandColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text(band, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: bandColor)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'A bad-paying customer does not automatically produce a bad score — this is your own follow-up discipline and collection performance.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF5A6B87), height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            for (final c in components) componentRow(c.$1, c.$2, c.$4, c.$5, breakdown[c.$3] ?? 0),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: bandColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: bandColor.withValues(alpha: 0.25))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Weighted Recovery Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                  Text('$total%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: bandColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String recoveryScoreBand(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 60) return 'Good';
  if (score >= 40) return 'Average';
  if (score >= 20) return 'Below Average';
  return 'Poor';
}

Color recoveryScoreBandColor(String band) {
  switch (band) {
    case 'Excellent':
      return const Color(0xFF16A34A);
    case 'Good':
      return const Color(0xFF0052CC);
    case 'Average':
      return const Color(0xFFF57C00);
    case 'Below Average':
      return const Color(0xFFEA580C);
    default:
      return const Color(0xFFE53935);
  }
}
