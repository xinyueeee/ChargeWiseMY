import 'package:chargewise_my/core/navigation/driver_navigation_shell.dart';
import 'package:chargewise_my/modules/planning/widgets/planning_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size phonePortrait = Size(411, 891);
const Size phoneLandscape = Size(891, 411);
const Size tabletPortrait = Size(800, 1280);
const Size tabletLandscape = Size(1280, 800);

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
  String currentTab = 'Planning',
  VoidCallback? onHomeTap,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final config = DriverNavigationConfig(
    currentTab: currentTab,
    onHomeTap: onHomeTap,
    onChargingTap: () {},
    onPlanningTap: () {},
    onFeedbackTap: () {},
    onProfileTap: () {},
  );

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: DriverNavigationShell(
              config: config,
              child: const Center(child: Text('screen content')),
            ),
            bottomNavigationBar: config.bottomBarFor(context),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('breakpoint', () {
    test('is a sensible width for phone landscape and tablets', () {
      expect(kDriverNavigationRailBreakpoint, 700);

      expect(phonePortrait.width < kDriverNavigationRailBreakpoint, isTrue);
      expect(phoneLandscape.width >= kDriverNavigationRailBreakpoint, isTrue);
      expect(tabletPortrait.width >= kDriverNavigationRailBreakpoint, isTrue);
      expect(tabletLandscape.width >= kDriverNavigationRailBreakpoint, isTrue);
    });
  });

  group('exactly one navigation surface is mounted', () {
    testWidgets('phone portrait uses the bottom bar only', (tester) async {
      await _pumpShell(tester, size: phonePortrait);

      expect(find.byType(FloatingBottomNav), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('phone landscape uses the rail only', (tester) async {
      await _pumpShell(tester, size: phoneLandscape);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingBottomNav), findsNothing);
    });

    testWidgets('tablet portrait uses the rail only', (tester) async {
      await _pumpShell(tester, size: tabletPortrait);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingBottomNav), findsNothing);
    });

    testWidgets('tablet landscape uses the rail only', (tester) async {
      await _pumpShell(tester, size: tabletLandscape);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(FloatingBottomNav), findsNothing);
    });
  });

  group('destinations and selection', () {
    testWidgets('the rail carries the same five destinations', (tester) async {
      await _pumpShell(tester, size: phoneLandscape);

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(5));
      for (final label in const <String>[
        'Home',
        'Charging',
        'Planning',
        'Feedback',
        'Profile',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('the current tab stays selected in the rail', (tester) async {
      await _pumpShell(
        tester,
        size: phoneLandscape,
        currentTab: 'Profile',
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 4);
    });

    testWidgets('Feedback stays selected on the Feedback screens',
        (tester) async {
      await _pumpShell(
        tester,
        size: phoneLandscape,
        currentTab: 'Feedback',
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 3);
    });

    testWidgets('every canonical tab maps to a rail destination',
        (tester) async {
      const tabs = <String, int>{
        'Home': 0,
        'Charging': 1,
        'Planning': 2,
        'Feedback': 3,
        'Profile': 4,
      };
      for (final entry in tabs.entries) {
        await _pumpShell(
          tester,
          size: phoneLandscape,
          currentTab: entry.key,
        );
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.selectedIndex, entry.value, reason: entry.key);
      }
    });

    testWidgets('an unknown tab selects nothing rather than throwing',
        (tester) async {
      await _pumpShell(tester, size: phoneLandscape, currentTab: 'Unknown');

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, isNull);
    });

    testWidgets('tapping a rail destination runs the same callback',
        (tester) async {
      var homeTaps = 0;
      await _pumpShell(
        tester,
        size: phoneLandscape,
        onHomeTap: () => homeTaps++,
      );

      await tester.tap(find.text('Home'));
      await tester.pump();

      expect(homeTaps, 1);
    });
  });

  group('content and layout', () {
    testWidgets('screen content is still shown beside the rail',
        (tester) async {
      await _pumpShell(tester, size: phoneLandscape);

      expect(find.text('screen content'), findsOneWidget);
    });

    testWidgets('the rail does not cover the content', (tester) async {
      await _pumpShell(tester, size: phoneLandscape);

      final railRect = tester.getRect(find.byType(NavigationRail));
      final contentRect = tester.getRect(find.text('screen content'));

      expect(contentRect.left, greaterThanOrEqualTo(railRect.right));
    });

    testWidgets('no overflow at 1.5x text scale in every layout',
        (tester) async {
      for (final size in const <Size>[
        phonePortrait,
        phoneLandscape,
        tabletPortrait,
        tabletLandscape,
      ]) {
        await _pumpShell(tester, size: size, textScale: 1.5);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow or layout error at $size with 1.5x text',
        );
      }
    });
  });
}
