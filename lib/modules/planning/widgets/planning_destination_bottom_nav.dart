import 'package:flutter/material.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../core/navigation/driver_navigation_shell.dart';

DriverNavigationConfig planningDriverNavConfig(BuildContext context) =>
    DriverNavigationConfig(
      currentTab: 'Planning',
      onHomeTap: () => switchDriverTab(context, DriverTab.home),
      onChargingTap: () => switchDriverTab(context, DriverTab.charging),
      onPlanningTap: () => returnToPlanningRoot(context),
      onFeedbackTap: () => switchDriverTab(context, DriverTab.feedback),
      onProfileTap: () => switchDriverTab(context, DriverTab.profile),
    );

class PlanningDestinationBottomNav extends StatelessWidget {
  const PlanningDestinationBottomNav({super.key});

  @override
  Widget build(BuildContext context) =>
      planningDriverNavConfig(context).bottomBarFor(context) ??
      const SizedBox.shrink();
}
