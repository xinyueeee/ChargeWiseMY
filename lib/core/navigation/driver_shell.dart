import 'package:flutter/material.dart';

import '../../modules/auth/screens/profile_screen.dart';
import '../../modules/charging/screens/charging_screen.dart';
import '../../modules/feedback/screens/feedback_dashboard_screen.dart';
import '../../modules/home/screens/home_screen.dart';
import '../../modules/planning/screens/planning_dashboard_screen.dart';
import 'driver_navigation_shell.dart';

final driverShellKey = GlobalKey<DriverShellState>();

abstract final class DriverTab {
  static const home = 0;
  static const charging = 1;
  static const planning = 2;
  static const feedback = 3;
  static const profile = 4;
}

class DriverShell extends StatefulWidget {
  DriverShell({Key? key}) : super(key: key ?? driverShellKey);

  @override
  State<DriverShell> createState() => DriverShellState();
}

class DriverShellState extends State<DriverShell> {
  int _tabIndex = DriverTab.home;

  static const _tabLabels = [
    'Home',
    'Charging',
    'Planning',
    'Feedback',
    'Profile',
  ];

  static const _tabs = [
    HomeScreen(),
    ChargingScreen(),
    PlanningDashboardScreen(),
    FeedbackDashboardScreen(),
    ProfileScreen(),
  ];

  void switchTab(int index) {
    if (_tabIndex == index) return;
    setState(() => _tabIndex = index);
  }

  DriverNavigationConfig get _navConfig => DriverNavigationConfig(
        currentTab: _tabLabels[_tabIndex],
        onHomeTap: () => switchTab(DriverTab.home),
        onChargingTap: () => switchTab(DriverTab.charging),
        onPlanningTap: () => switchTab(DriverTab.planning),
        onFeedbackTap: () => switchTab(DriverTab.feedback),
        onProfileTap: () => switchTab(DriverTab.profile),
      );

  @override
  Widget build(BuildContext context) {
    final config = _navConfig;
    return Scaffold(
      body: DriverNavigationShell(
        config: config,
        child: IndexedStack(index: _tabIndex, children: _tabs),
      ),
      bottomNavigationBar: config.bottomBarFor(context),
    );
  }
}
