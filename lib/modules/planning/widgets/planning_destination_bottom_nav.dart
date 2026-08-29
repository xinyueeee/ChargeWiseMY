import 'package:flutter/material.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../core/navigation/driver_navigation_shell.dart';

/// Destinations shared by every Planning screen.
///
/// Each tap pops back to the Driver shell (removing this pushed screen and
/// any others above it) and switches the shell to the target tab - the
/// shell's IndexedStack keeps every tab's own state alive underneath, so
/// this never rebuilds anything, just changes what's visible.
DriverNavigationConfig planningDriverNavConfig(BuildContext context) =>
    DriverNavigationConfig(
      currentTab: 'Planning',
      onHomeTap: () => switchDriverTab(context, DriverTab.home),
      onChargingTap: () => switchDriverTab(context, DriverTab.charging),
      onPlanningTap: () => returnToPlanningRoot(context),
      onFeedbackTap: () => switchDriverTab(context, DriverTab.feedback),
      onProfileTap: () => switchDriverTab(context, DriverTab.profile),
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
