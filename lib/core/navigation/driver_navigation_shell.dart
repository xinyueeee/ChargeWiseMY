import 'package:flutter/material.dart';

import '../../modules/planning/widgets/planning_widgets.dart';

const double kDriverNavigationRailBreakpoint = 700;

bool useDriverNavigationRail(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDriverNavigationRailBreakpoint;

class _DriverDestination {
  const _DriverDestination(this.tab, this.icon, this.label);

  final String tab;
  final IconData icon;
  final String label;
}

const List<_DriverDestination> _driverDestinations = <_DriverDestination>[
  _DriverDestination('Home', Icons.home_outlined, 'Home'),
  _DriverDestination('Charging', Icons.bolt_outlined, 'Charging'),
  _DriverDestination('Planning', Icons.map_outlined, 'Planning'),
  _DriverDestination('Feedback', Icons.warning_amber_outlined, 'Feedback'),
  _DriverDestination('Profile', Icons.person_outline, 'Profile'),
];

@immutable
class DriverNavigationConfig {
  const DriverNavigationConfig({
    required this.currentTab,
    this.onHomeTap,
    this.onChargingTap,
    this.onPlanningTap,
    this.onFeedbackTap,
    this.onProfileTap,
  });

  final String currentTab;
  final VoidCallback? onHomeTap;
  final VoidCallback? onChargingTap;
  final VoidCallback? onPlanningTap;
  final VoidCallback? onFeedbackTap;
  final VoidCallback? onProfileTap;

  VoidCallback? _callbackFor(String tab) => switch (tab) {
        'Home' => onHomeTap,
        'Charging' => onChargingTap,
        'Planning' => onPlanningTap,
        'Feedback' => onFeedbackTap,
        'Profile' => onProfileTap,
        _ => null,
      };

  Widget? bottomBarFor(BuildContext context) => useDriverNavigationRail(context)
      ? null
      : FloatingBottomNav(
          currentTab: currentTab,
          onHomeTap: onHomeTap,
          onChargingTap: onChargingTap,
          onPlanningTap: onPlanningTap,
          onFeedbackTap: onFeedbackTap,
          onProfileTap: onProfileTap,
        );
}

class DriverNavigationShell extends StatelessWidget {
  const DriverNavigationShell({
    super.key,
    required this.config,
    required this.child,
  });

  final DriverNavigationConfig config;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!useDriverNavigationRail(context)) return child;

    final selectedIndex = _driverDestinations.indexWhere(
      (destination) => destination.tab == config.currentTab,
    );

    return Row(
      children: <Widget>[
        SafeArea(
          right: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: selectedIndex < 0 ? null : selectedIndex,
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: 0,
                    backgroundColor: Colors.white,
                    indicatorColor: const Color(0x1A00B894),
                    selectedIconTheme: const IconThemeData(
                      color: Color(0xFF00B894),
                    ),
                    selectedLabelTextStyle: const TextStyle(
                      color: Color(0xFF00B894),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    unselectedIconTheme: const IconThemeData(
                      color: planningMutedTextColor,
                    ),
                    unselectedLabelTextStyle: const TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                    ),
                    destinations: <NavigationRailDestination>[
                      for (final destination in _driverDestinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          label: Text(destination.label),
                        ),
                    ],
                    onDestinationSelected: (index) {
                      config
                          ._callbackFor(_driverDestinations[index].tab)
                          ?.call();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFFE9EDF3)),
        Expanded(child: child),
      ],
    );
  }
}
