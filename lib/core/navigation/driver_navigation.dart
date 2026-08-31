import 'package:flutter/material.dart';

import 'driver_shell.dart';

export 'driver_shell.dart' show DriverTab;

void switchDriverTab(BuildContext context, int tab) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  driverShellKey.currentState?.switchTab(tab);
}

void returnToDriverHome(BuildContext context) =>
    switchDriverTab(context, DriverTab.home);

void returnToPlanningRoot(BuildContext context) =>
    switchDriverTab(context, DriverTab.planning);
