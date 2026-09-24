import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Manager's Profile — identity plus a real oversight summary (team size,
/// branches, portfolio) derived from the shared store, no fabricated
/// contact details. Replaces the "More" tab for this role.
class ManagerProfileScreen extends StatelessWidget {
  const ManagerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final name = store.currentUserFullName;
    final initials = name.trim().split(RegExp(r'\s+')).map((p) => p.isEmpty ? '' : p[0]).take(2).join().toUpperCase();
    final branches = {for (final s in store.salesmen) ((s['branch'] as String?) ?? 'Turning Point')};
    final teamSize = store.salesmen.length;
    final totalCustomers = store.customers.length;
    final totalOutstanding = store.totalOverdueAmount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF0052CC), Color(0xFF1E3A8A)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(radius: 43, backgroundColor: const Color(0xFFE3F2FD), child: Text(initials, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Color(0xFF0052CC)))),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFF4CAF50), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.check, size: 10, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text('Regional Manager', style: TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                    child: Text('Company-wide  ·  ${branches.length} Branches', style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(title: 'Oversight Summary'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statCard(Icons.groups_outlined, const Color(0xFF2563EB), '$teamSize', 'Team Size')),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(Icons.apartment_outlined, const Color(0xFF16A34A), '${branches.length}', 'Branches')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _statCard(Icons.people_alt_outlined, const Color(0xFF9333EA), '$totalCustomers', 'Total Customers')),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(Icons.currency_rupee, const Color(0xFFDC2626), _rupee.format(totalOutstanding), 'Total Outstanding')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Account Details'),
                  const SizedBox(height: 12),
                  _InfoTile(icon: Icons.badge_outlined, label: 'Login ID', value: store.currentUsername),
                  const _InfoTile(icon: Icons.work_outline, label: 'Role', value: 'Regional Manager'),
                  const _InfoTile(icon: Icons.visibility_outlined, label: 'Access Level', value: 'Company-wide — view only'),
                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Settings'),
                  const SizedBox(height: 12),
                  _ActionTile(icon: Icons.notifications_outlined, iconColor: const Color(0xFF0052CC), iconBg: const Color(0xFFE3F2FD), label: 'Notification Preferences', onTap: () => _showComingSoon(context)),
                  _ActionTile(icon: Icons.lock_outline, iconColor: const Color(0xFF8E24AA), iconBg: const Color(0xFFF3E5F5), label: 'Change Password', onTap: () => _showComingSoon(context)),
                  _ActionTile(icon: Icons.help_outline, iconColor: const Color(0xFFF57C00), iconBg: const Color(0xFFFFF3E0), label: 'Help & Support', onTap: () => _showComingSoon(context)),
                  const SizedBox(height: 12),
                  _ActionTile(icon: Icons.logout, iconColor: const Color(0xFFE53935), iconBg: const Color(0xFFFFEBEE), label: 'Logout', labelColor: const Color(0xFFE53935), onTap: () => _confirmLogout(context, store)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.withValues(alpha: 0.15))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 17)),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))),
          Text(label, style: const TextStyle(fontSize: 10.5, color: Color(0xFF5A6B87), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    showAppMessage(context, message: 'Coming soon');
  }

  void _confirmLogout(BuildContext context, AppStore store) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.logout, color: Color(0xFFE53935)), SizedBox(width: 8), Text('Logout', style: TextStyle(fontWeight: FontWeight.bold))]),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF5A6B87)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              Navigator.pop(context);
              store.logout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48)));
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.15))),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0052CC)),
            const SizedBox(width: 12),
            Text('$label: ', style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF1B2B48), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.iconColor, required this.iconBg, required this.label, this.labelColor = const Color(0xFF1B2B48), required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.15))),
        // See profile_screen.dart's _ActionTile — a newer Flutter throws
        // without a real Material ancestor for ListTile's background/ink.
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, color: iconColor, size: 18)),
            title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: labelColor)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFA0AEC0)),
            onTap: onTap,
          ),
        ),
      );
}
