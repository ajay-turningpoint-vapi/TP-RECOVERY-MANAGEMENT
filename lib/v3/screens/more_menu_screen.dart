import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/re_team_tab.dart';
import 'package:salesman_mobile/v2/screens/re_approvals_tab.dart';
import 'package:salesman_mobile/v3/screens/escalations_screen.dart';
import 'package:salesman_mobile/v3/screens/needs_attention_screen.dart';
import 'package:salesman_mobile/v3/screens/notifications_screen.dart';
import 'package:salesman_mobile/v3/screens/five_pm_control_screen.dart';
import 'package:salesman_mobile/v3/screens/company_search_screen.dart';

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _border = Color(0xFFE2E8F0);

class MoreMenuScreen extends StatelessWidget {
  const MoreMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final pendingApprovals = store.tasks.where((t) => t.approvalStatus == 'Pending').length +
        store.disputes.where((d) => d['status'] == 'Pending Approval').length +
        store.paymentClaims.where((p) => p['status'] == 'Awaiting Verification' || p['status'] == 'Sync Pending').length +
        store.ptpCorrectionRequests.length +
        store.pendingOutcomeCorrectionCount +
        store.pendingOutcomeEditCount;

    final items = <_MenuItem>[
      _MenuItem('Approvals', Icons.inbox_outlined, const Color(0xFF2563EB), (ctx) => const Scaffold(body: SafeArea(child: ReApprovalsTab())), badge: pendingApprovals),
      _MenuItem('Escalations', Icons.trending_up_outlined, const Color(0xFFDC2626), (ctx) => const EscalationsScreen(), badge: store.openEscalationCases.length),
      _MenuItem('Needs Attention', Icons.warning_amber_outlined, const Color(0xFFEA580C), (ctx) => const NeedsAttentionScreen(), badge: store.needsAttentionBadgeCount),
      _MenuItem('Salesmen', Icons.people_outline, const Color(0xFF059669), (ctx) => const ReTeamTab()),
      _MenuItem('Search', Icons.search, const Color(0xFF0F172A), (ctx) => const CompanySearchScreen()),
      _MenuItem('Notifications', Icons.notifications_none, const Color(0xFF9333EA), (ctx) => const NotificationsScreen(), badge: store.unreadNotificationCount),
      _MenuItem('5 PM Control', Icons.history, const Color(0xFF991B1B), (ctx) => const FivePmControlScreen()),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('${store.currentUserFullName} · ${store.userRole == 'MANAGEMENT' ? 'Manager' : 'Recovery Executive'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _dark)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final grid = GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: items.map((m) {
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: m.builder)),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: m.color.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(m.icon, color: m.color, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark)),
                    ],
                  ),
                  if (m.badge > 0)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                        child: Text('${m.badge}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
          );
          if (constraints.maxWidth > 600) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: grid,
              ),
            );
          }
          return grid;
        },
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData icon;
  final Color color;
  final Widget Function(BuildContext) builder;
  final int badge;
  _MenuItem(this.label, this.icon, this.color, this.builder, {this.badge = 0});
}
