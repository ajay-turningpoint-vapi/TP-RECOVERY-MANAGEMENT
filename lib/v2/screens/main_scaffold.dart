import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/screens/dashboard_screen.dart';
import 'package:salesman_mobile/v2/screens/tasks_screen.dart';
import 'package:salesman_mobile/v2/screens/customers_screen.dart';
import 'package:salesman_mobile/v2/screens/profile_screen.dart';
import 'package:salesman_mobile/widgets/data_loading.dart' show InitialDataLoader;

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DashboardScreen(),
    const TasksScreen(),
    const CustomersScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final openTasks = store.myOpenTaskCount;
    final dueCustomers = store.myCustomers.length;
    return Scaffold(
      body: InitialDataLoader(child: _pages[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0052CC),
        unselectedItemColor: const Color(0xFFA0AEC0),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          context.read<AppStore>().refreshLiveData();
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: openTasks > 0,
              label: Text(openTasks > 99 ? '99+' : '$openTasks'),
              backgroundColor: const Color(0xFFE53935),
              child: const Icon(Icons.assignment),
            ),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: dueCustomers > 0,
              label: Text(dueCustomers > 99 ? '99+' : '$dueCustomers'),
              backgroundColor: const Color(0xFF0052CC),
              child: const Icon(Icons.people),
            ),
            label: 'Customers',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
