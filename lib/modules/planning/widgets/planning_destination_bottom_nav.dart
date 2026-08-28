import 'package:flutter/material.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../../auth/screens/profile_screen.dart';
import '../../charging/screens/charging_screen.dart';
import '../../feedback/screens/feedback_dashboard_screen.dart';
import '../screens/planning_dashboard_screen.dart';

/// Destinations shared by every Planning screen.
///
/// The callbacks are the ones the Planning bottom bar has always used, so
/// route stacks and back behaviour are unchanged; only the surface that
/// renders them varies with layout width.
DriverNavigationConfig planningDriverNavConfig(BuildContext context) =>
    DriverNavigationConfig(
      currentTab: 'Planning',
      onHomeTap: () => returnToDriverHome(context),
      onChargingTap: () => openDriverModule(
        context,
        routeName: DriverRouteNames.charging,
        builder: (_) => const ChargingScreen(),
      ),
      onPlanningTap: () => returnToPlanningRoot(
        context,
        fallbackBuilder: (_) => const PlanningDashboardScreen(),
      ),
      onFeedbackTap: () => openDriverModule(
        context,
        routeName: DriverRouteNames.feedback,
        builder: (_) => const FeedbackDashboardScreen(),
      ),
      onProfileTap: () => openDriverModule(
        context,
        routeName: DriverRouteNames.profile,
        builder: (_) => const ProfileScreen(),
      ),
    );

/// Planning bottom bar. Returns nothing in wide layouts, where
/// [DriverNavigationShell] renders the same destinations as a side rail.
class PlanningDestinationBottomNav extends StatelessWidget {
  const PlanningDestinationBottomNav({super.key});

  @override
  Widget build(BuildContext context) =>
      planningDriverNavConfig(context).bottomBarFor(context) ??
      const SizedBox.shrink();
}
