import 'package:flutter/material.dart';
import 'package:salesman_mobile/v3/screens/manager_dashboard_screen.dart';
import 'package:salesman_mobile/v3/screens/company_recovery_queue_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_tasks_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_reports_screen.dart';
import 'package:salesman_mobile/v3/screens/manager_profile_screen.dart';

/// Manager's fixed bottom navigation: Dashboard, Customers, Tasks, Reports,
/// Profile.
class ManagerScaffoldV3 extends StatefulWidget {
  const ManagerScaffoldV3({super.key});

  @override
  State<ManagerScaffoldV3> createState() => _ManagerScaffoldV3State();
}

class _ManagerScaffoldV3State extends State<ManagerScaffoldV3> {
  int _currentIndex = 0;

  void _goTo(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      ManagerDashboardScreen(onNavigate: _goTo),
      const CompanyRecoveryQueueScreen(),
      ManagerTasksScreen(onNavigate: _goTo),
      ManagerReportsScreen(onNavigate: _goTo),
      const ManagerProfileScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: pages),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: const Color(0xFFA0AEC0),
        selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        onTap: _goTo,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Customers'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), activeIcon: Icon(Icons.assignment), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
