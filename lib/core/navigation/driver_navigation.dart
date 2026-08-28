import 'package:flutter/material.dart';

abstract final class DriverRouteNames {
  static const charging = '/driver/charging';
  static const planning = '/driver/planning';
  static const profile = '/driver/profile';
  static const feedback = '/driver/feedback';
}

void openDriverModule(
  BuildContext context, {
  required String routeName,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context);
  navigator.popUntil((route) => route.isFirst);
  navigator.push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: builder,
    ),
  );
}

void returnToDriverHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

void returnToPlanningRoot(
  BuildContext context, {
  required WidgetBuilder fallbackBuilder,
}) {
  final navigator = Navigator.of(context);
  var foundPlanningRoot = false;
  navigator.popUntil((route) {
    if (route.settings.name == DriverRouteNames.planning) {
      foundPlanningRoot = true;
      return true;
    }
    return route.isFirst;
  });
  if (!foundPlanningRoot) {
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: DriverRouteNames.planning),
        builder: fallbackBuilder,
      ),
    );
  }
}
