import 'package:flutter/material.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../auth/screens/profile_screen.dart';
import '../../charging/screens/charging_screen.dart';
import '../screens/planning_dashboard_screen.dart';
import 'planning_widgets.dart';

class PlanningDestinationBottomNav extends StatelessWidget {
  const PlanningDestinationBottomNav({super.key});

  @override
  Widget build(BuildContext context) => FloatingBottomNav(
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
        onProfileTap: () => openDriverModule(
          context,
          routeName: DriverRouteNames.profile,
          builder: (_) => const ProfileScreen(),
        ),
      );
}
