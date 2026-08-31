import 'dart:io';

import 'package:chargewise_my/modules/admin/widgets/admin_feedback_widgets.dart';
import 'package:chargewise_my/modules/planning/screens/planning_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<Size> responsiveMatrix = <Size>[
  Size(360, 800),
  Size(640, 360),
  Size(800, 360),
  Size(800, 400),
  Size(800, 1280),
  Size(1280, 800),
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

    test('splits for short, wide landscape below the 700 width threshold', () {
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

    test(
        'does not split landscape once height grows past the short-height '
        'allowance', () {
      expect(
        useSplitPlanningDashboardLayout(
          const BoxConstraints(maxWidth: 640, maxHeight: 700),
        ),
        isFalse,
        reason: 'height 700 > 620 and width 640 < 700',
      );
    });

    test(
        'every size in the audit matrix produces a decision without '
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
    test('the split pane is not sized with a raw MediaQuery-derived width', () {
      final source = File(
        'lib/modules/planning/screens/planning_dashboard_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(source.contains('OrientationBuilder'), isFalse);
      expect(source.contains('MediaQuery.sizeOf(context).width'), isFalse);
      expect(
        RegExp(r'SizedBox\(\s*width:\s*size\.width').hasMatch(source),
        isFalse,
      );

      expect(
        RegExp(r'Expanded\(\s*flex:\s*2,').hasMatch(source),
        isTrue,
        reason: 'the left split pane must be flex-sized, not fixed-width',
      );
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
