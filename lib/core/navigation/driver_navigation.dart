import 'package:flutter/material.dart';

import 'driver_shell.dart';

export 'driver_shell.dart' show DriverTab;

/// Pops back to the Driver shell (removing any pushed detail screens, e.g.
/// a proposal or report view) and switches it to [tab] - the replacement
/// for the old route-push-based tab navigation now that all five Driver
/// destinations live inside one [DriverShell] IndexedStack rather than as
/// separate pushed routes.
void switchDriverTab(BuildContext context, int tab) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  driverShellKey.currentState?.switchTab(tab);
}

void returnToDriverHome(BuildContext context) =>
    switchDriverTab(context, DriverTab.home);

/// "Planning" tab tap from anywhere, including from deep inside a pushed
/// Planning detail screen. Popping back to the shell always lands on
/// PlanningDashboardScreen's own state (it never got disposed - it's an
/// IndexedStack child, not a route), so this no longer needs the old
/// find-a-named-route-or-push-a-fallback logic.
void returnToPlanningRoot(BuildContext context) =>
    switchDriverTab(context, DriverTab.planning);
