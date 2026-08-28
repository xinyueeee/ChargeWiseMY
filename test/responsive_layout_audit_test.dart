// Regression coverage for the responsive-layout/overflow audit.
//
// Two real, empirically-proven bugs came out of that audit:
//
// 1. Planning Dashboard decided its split-vs-single-column layout, and sized
//    its left pane, from `MediaQuery.sizeOf(context).width` — the full
//    device width. Once the screen sits inside `DriverNavigationShell`'s
//    `Expanded` content pane (>=700 logical px, NavigationRail showing),
//    `MediaQuery` still reports the full device width, not what the rail
//    left behind, and a `SizedBox(width: ...)` sized from that inflated
//    number could demand more width than the pane actually had.
//    `useSplitPlanningDashboardLayout` is the extracted, pure decision
//    function; these tests exercise it directly, and separately assert the
//    fixed-width `SizedBox` pattern is gone from the source.
//
// 2. AdminStatTile sat inside a `GridView.count(childAspectRatio: 1.05)`.
//    A fixed aspect ratio cannot fit the tile's icon + value + two-line
//    label at once text grows past 1.0x or the grid grows to 4 narrower
//    columns — proven to overflow by 18px at 1.5x/2-columns and even by
//    4.8px at 1.0x/4-columns. The fix replaced the fixed-ratio grid with a
//    `Wrap` of fixed-width, natural-height tiles.
import 'dart:io';

import 'package:chargewise_my/modules/admin/widgets/admin_feedback_widgets.dart';
import 'package:chargewise_my/modules/planning/screens/planning_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The full stress matrix the audit was asked to cover.
const List<Size> responsiveMatrix = <Size>[
  Size(360, 800), // phone portrait
  Size(640, 360), // small phone landscape
  Size(800, 360), // normal phone landscape
  Size(800, 400), // normal phone landscape (taller)
  Size(800, 1280), // tablet portrait
  Size(1280, 800), // tablet landscape
];

const List<double> responsiveTextScales = <double>[1.0, 1.3, 1.5];

void main() {
  group('useSplitPlanningDashboardLayout', () {
    test('single-column below the split thresholds', () {
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 360, maxHeight: 800),
        ),
        isFalse,
        reason: 'phone portrait',
      );
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 500, maxHeight: 900),
        ),
        isFalse,
      );
    });

    test('splits once width alone reaches 700, any height', () {
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 700, maxHeight: 2000),
        ),
        isTrue,
      );
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 1280, maxHeight: 800),
        ),
        isTrue,
        reason: 'tablet landscape',
      );
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 800, maxHeight: 1280),
        ),
        isTrue,
        reason: 'tablet portrait',
      );
    });

    test('splits for short, wide landscape below the 700 width threshold',
        () {
      // Small phone landscape from the audit matrix: 640x360.
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 640, maxHeight: 360),
        ),
        isTrue,
      );
    });

    test('does not split a narrow, tall layout even if height is short', () {
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 500, maxHeight: 600),
        ),
        isFalse,
        reason: 'width never reaches the 540 landscape floor',
      );
    });

    test('does not split landscape once height grows past the short-height '
        'allowance', () {
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 640, maxHeight: 700),
        ),
        isFalse,
        reason: 'height 700 > 620 and width 640 < 700',
      );
    });

    test('every size in the audit matrix produces a decision without '
        'throwing', () {
      for (final size in responsiveMatrix) {
        expect(
          () => useSplitPlanningDashboardLayout(
            BoxConstraints(maxWidth: size.width, maxHeight: size.height),
          ),
          returnsNormally,
          reason: '$size',
        );
      }
    });
  });

  group('Planning Dashboard source no longer sizes from MediaQuery', () {
    test('the split pane is not sized with a raw MediaQuery-derived width',
        () {
      final source = File(
        'lib/modules/planning/screens/planning_dashboard_screen.dart',
      ).readAsStringSync();

      // The historical bug: SizedBox(width: size.width * .39) where `size`
      // came from MediaQuery.sizeOf(context). Both the OrientationBuilder
      // (which supplied that `size`) and the fixed-width pane must be gone.
      expect(source.contains('OrientationBuilder'), isFalse);
      expect(source.contains('MediaQuery.sizeOf(context).width'), isFalse);
      expect(
        RegExp(r'SizedBox\(\s*width:\s*size\.width').hasMatch(source),
        isFalse,
      );
      // Expanded(flex: ...) is what replaced it — safe by construction,
      // since Expanded can never demand more width than its Row has.
      expect(source.contains('Expanded(\n                flex: 2,'), isTrue);
    });
  });

  group('AdminStatTile grid regression (Wrap, not fixed-aspect GridView)', () {
    Widget grid(BuildContext outerContext) => LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final columns = constraints.maxWidth >= 420 ? 4 : 2;
            final tileWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: const AdminStatTile(
                    icon: Icons.assignment_late_outlined,
                    value: '128',
                    label: 'New Reports',
                    color: Colors.red,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: const AdminStatTile(
                    icon: Icons.autorenew,
                    value: '34',
                    label: 'In Progress',
                    color: Colors.blue,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  // Deliberately the longest label in the real dashboard —
                  // the exact tile that overflowed under the old grid.
                  child: const AdminStatTile(
                    icon: Icons.build_outlined,
                    value: '5',
                    label: 'Maintenance Ongoing',
                    color: Colors.purple,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: const AdminStatTile(
                    icon: Icons.check_circle_outline,
                    value: '900',
                    label: 'Resolved',
                    color: Colors.green,
                  ),
                ),
              ],
            );
          },
        );

    for (final size in responsiveMatrix) {
      for (final scale in responsiveTextScales) {
        testWidgets('no overflow at ${size.width}x${size.height} @ ${scale}x',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(child: Builder(builder: grid)),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: '${size.width}x${size.height} @ ${scale}x',
          );
        });
      }
    }
  });
}
