import 'package:flutter/material.dart';

import '../../modules/planning/widgets/planning_widgets.dart';

/// Width at which the Driver destinations move from the bottom bar to a side
/// rail. A phone in portrait stays well below this; a phone in landscape and
/// any tablet sit above it, which is where a bottom bar wastes vertical space
/// that is already scarce.
const double kDriverNavigationRailBreakpoint = 700;

/// True when the current layout should use the side rail instead of the
/// bottom bar. Both [DriverNavigationShell] and
/// [DriverNavigationConfig.bottomBarFor] consult this, so exactly one of the
/// two navigation surfaces is ever mounted.
bool useDriverNavigationRail(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDriverNavigationRailBreakpoint;

/// One Driver destination, shared by the bottom bar and the rail so the two
/// never drift apart.
class _DriverDestination {
  const _DriverDestination(this.tab, this.icon, this.label);

  final String tab;
  final IconData icon;
  final String label;
}

/// Canonical Driver destinations, in the same order as [FloatingBottomNav].
const List<_DriverDestination> _driverDestinations = <_DriverDestination>[
  _DriverDestination('Home', Icons.home_outlined, 'Home'),
  _DriverDestination('Charging', Icons.bolt_outlined, 'Charging'),
  _DriverDestination('Planning', Icons.map_outlined, 'Planning'),
  _DriverDestination('Feedback', Icons.warning_amber_outlined, 'Feedback'),
  _DriverDestination('Profile', Icons.person_outline, 'Profile'),
];

/// The destinations and callbacks for one Driver screen, declared once and
/// used by whichever navigation surface the current layout calls for.
///
/// Navigation behaviour is unchanged: the same callbacks the bottom bar
/// already invoked are reused verbatim, so route stacks, `popUntil` logic and
/// Android back behaviour stay exactly as they were.
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

  /// The bottom bar, or `null` when the rail is in use.
  ///
  /// Returning `null` is what guarantees the two surfaces are never mounted
  /// at the same time.
  Widget? bottomBarFor(BuildContext context) =>
      useDriverNavigationRail(context)
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

/// Wraps a screen body so wide layouts get a leading [NavigationRail].
///
/// In narrow layouts the body is returned untouched and the screen's own
/// `bottomNavigationBar` supplies the destinations.
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
              // Phone landscape is short, and 1.5x text makes each label
              // taller. Scrolling keeps every destination reachable instead
              // of overflowing.
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
                      // A destination with no callback stays inert, matching
                      // the bottom bar's behaviour for that screen.
                      config._callbackFor(_driverDestinations[index].tab)?.call();
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
