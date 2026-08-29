import 'package:flutter/material.dart';

import '../../modules/auth/screens/profile_screen.dart';
import '../../modules/charging/screens/charging_screen.dart';
import '../../modules/feedback/screens/feedback_dashboard_screen.dart';
import '../../modules/home/screens/home_screen.dart';
import '../../modules/planning/screens/planning_dashboard_screen.dart';
import 'driver_navigation_shell.dart';

/// There is only ever one [DriverShell] alive at a time (it's the Driver
/// side's single root route), so a static key is enough to let any screen -
/// however deeply it's pushed on top - switch tabs without needing a
/// BuildContext that's actually a descendant of the shell. See
/// switchDriverTab() in driver_navigation.dart, which is what callers
/// should use instead of reaching for this key directly.
final driverShellKey = GlobalKey<DriverShellState>();

/// Names for the five tab indexes, so call sites read as
/// `DriverTab.charging` rather than a bare `1`.
abstract final class DriverTab {
  static const home = 0;
  static const charging = 1;
  static const planning = 2;
  static const feedback = 3;
  static const profile = 4;
}

/// Hosts all five Driver destinations as an [IndexedStack] so switching
/// tabs is an instant visibility swap - no rebuild, no refetch - matching
/// how AdminShell already behaves. Each tab screen keeps its own Scaffold
/// (and AppBar, where it has one); this shell only owns the bottom nav /
/// rail and which tab is currently showing.
///
/// Trade-off, deliberately accepted: every tab's widgets (including
/// GoogleMap instances on Home and Charging) stay resident in memory for as
/// long as the app is open, not just while visible. That's what makes the
/// switch instant.
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

  // Built once and kept alive for the shell's whole lifetime - this is the
  // entire point of IndexedStack: constructing a fresh widget per switch
  // would defeat it by disposing/recreating state exactly like the old
  // push-based navigation did.
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
