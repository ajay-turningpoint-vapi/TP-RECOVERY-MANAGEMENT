import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/control_dashboard_screen.dart';
import 'package:salesman_mobile/v3/screens/company_recovery_queue_screen.dart';
import 'package:salesman_mobile/v3/screens/re_tasks_screen.dart';
import 'package:salesman_mobile/v3/screens/disputes_tab.dart';
import 'package:salesman_mobile/v3/screens/reports_screen.dart';
import 'package:salesman_mobile/v2/screens/profile_screen.dart';
import 'package:salesman_mobile/widgets/data_loading.dart' show InitialDataLoader;

/// Bottom navigation matches the company's fixed IA: Dashboard, Customers,
/// Tasks, Disputes, Reports, Profile (same as salesman v2). Approvals,
/// Escalations, Notifications, 5 PM Control and Search live inside the
/// hamburger menu (see [MoreMenuScreen]), reachable from the Dashboard/
/// Tasks/Reports headers.
class ReScaffoldV3 extends StatefulWidget {
  const ReScaffoldV3({super.key});

  @override
  State<ReScaffoldV3> createState() => _ReScaffoldV3State();
}

class _ReScaffoldV3State extends State<ReScaffoldV3> {
  int _currentIndex = 0;

  void _goTo(int index) {
    setState(() => _currentIndex = index);
    // Pull fresh lists on every tab switch so a page that's been sitting
    // in the IndexedStack (e.g. the dashboard) reflects what other users
    // have done since it was last shown.
    context.read<AppStore>().refreshLiveData();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final openTasks = store.totalOpenTaskItemsCount;
    final disputesAwaitingReview = store.disputesAwaitingReviewCount;

    final pages = [
      ControlDashboardScreen(onNavigate: _goTo),
      const CompanyRecoveryQueueScreen(),
      const ReTasksScreen(),
      const DisputesTab(),
      const ReportsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: InitialDataLoader(
          child: IndexedStack(index: _currentIndex, children: pages),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: const Color(0xFFA0AEC0),
        selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        onTap: _goTo,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          const BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Customers'),
          BottomNavigationBarItem(icon: _badgeIcon(Icons.assignment_outlined, openTasks), activeIcon: _badgeIcon(Icons.assignment, openTasks), label: 'Tasks'),
          BottomNavigationBarItem(icon: _badgeIcon(Icons.chat_bubble_outline, disputesAwaitingReview), activeIcon: _badgeIcon(Icons.chat_bubble, disputesAwaitingReview), label: 'Disputes'),
          const BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Reports'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _badgeIcon(IconData icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(10)),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
