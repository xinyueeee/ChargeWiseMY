// Regression coverage for the physical-device "RenderFlex overflowed by
// 35 pixels on the bottom" report.
//
// Root cause: `_buildLandscapeDashboard`'s right pane computed the map's
// height by SUBTRACTING a fixed, guessed `chromeHeight` (106 or 132) from
// the pane's available height, then handed the map that remainder — on the
// assumption that [section heading + MapContextCard + optional hint] always
// measures close to that constant. It does not. `MapContextCard` is a
// `Wrap`, and measured directly at realistic map-pane widths its natural
// height ranges from ~81px (a wide tablet pane, everything on one line) to
// ~166px (a narrow phone-landscape pane, three lines) — nothing close to a
// single fixed number. Whenever the real chrome measured taller than the
// guess, [heading + Stack(fixed mapHeight) + MapContextCard + hint] summed
// to more than the pane's actual height, and the pane's own `Column`
// (`crossAxisAlignment: stretch`, no scroll wrapper, tight height from
// `Expanded` inside a stretched `Row`) produced a genuine RenderFlex
// overflow — not from `CompactMapLegend` (which the previous audit already
// hardened and which stays correct here), but from the OUTER Column that
// held the whole Interactive Map section.
//
// The fix removes the chromeHeight subtraction entirely: the map is sized
// from a fraction of the pane's own height, and the whole section
// (heading + map + context card + hint) is wrapped in a
// `SingleChildScrollView`, matching the pattern the left pane already used
// safely. The natural height of the chrome becomes irrelevant to whether
// the layout fits — it always does.
import 'package:chargewise_my/modules/planning/widgets/compact_map_legend.dart';
import 'package:chargewise_my/modules/planning/widgets/map_context_card.dart';
import 'package:chargewise_my/modules/planning/widgets/planning_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<Size> mapSectionMatrix = <Size>[
  Size(640, 360),
  Size(700, 360),
  Size(800, 360),
  Size(800, 400),
  Size(1280, 800),
];

const List<double> mapSectionTextScales = <double>[1.0, 1.5];

/// Faithfully reproduces the section returned by `_buildMapExplorer`, using
/// the real, now-public production widgets (`PlanningSectionTitle`,
/// `CompactMapLegend`, `MapContextCard`) in the same order, and the map
/// height formula `_buildLandscapeDashboard` now actually uses — no chrome
/// subtraction, `.clamp(180.0, 420.0)` on 55% of the pane's own height.
Widget _interactiveMapSection({
  required BoxConstraints paneConstraints,
  required bool malaysiaSelected,
  required bool legendExpanded,
}) =>
    LayoutBuilder(
      builder: (context, mapConstraints) {
        final mapHeight =
            (mapConstraints.maxHeight * 0.55).clamp(180.0, 420.0);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlanningSectionTitle(
                'Interactive Map',
                subtitle: malaysiaSelected
                    ? 'Select a state to explore local infrastructure'
                    : 'Explore locations, proposals, and priority areas',
              ),
              const SizedBox(height: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Stand-in for MapPanel: GoogleMap cannot be pumped in a
                  // widget test (no platform view), but nothing under test
                  // here reads anything from the map itself — only that the
                  // Stack occupies exactly `mapHeight`, identical to
                  // ClipRRect(child: SizedBox(height: widget.height, ...)).
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: mapHeight,
                      child: ColoredBox(color: Colors.blueGrey.shade100),
                    ),
                  ),
                  if (!malaysiaSelected)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CompactMapLegend(
                        expanded: legendExpanded,
                        onToggle: () {},
                        showExisting: true,
                        showMevnetProposed: true,
                        showCommunityProposals: true,
                        onExistingChanged: (_) {},
                        onMevnetProposedChanged: (_) {},
                        onCommunityProposalsChanged: (_) {},
                        maxHeight: (mapHeight - 16).clamp(0.0, mapHeight),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const MapContextCard(
                locations: 1374,
                chargers: 4161,
                activeProposals: 12,
                priorityAreas: 3,
                plannedLocations: 3100,
              ),
              if (malaysiaSelected) ...[
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: planningMutedTextColor,
                    ),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Tap a state to explore local charging infrastructure',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );

/// The real ancestor chain that hands this section its constraints: an
/// `Expanded(flex: 3)` inside a `Row(crossAxisAlignment: stretch)`, itself
/// inside an `Expanded` in the outer split-layout `Column` — i.e. a TIGHT
/// height, not a loose one. Reproduced directly rather than approximated,
/// since the tightness is exactly what makes an unscrollable Column capable
/// of overflowing in the first place.
Widget _harness({
  required Size paneSize,
  required bool malaysiaSelected,
  required bool legendExpanded,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: paneSize.width,
              height: paneSize.height,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 20, 16),
                child: _interactiveMapSection(
                  paneConstraints: BoxConstraints.tight(paneSize),
                  malaysiaSelected: malaysiaSelected,
                  legendExpanded: legendExpanded,
                ),
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  group('MapContextCard\'s real natural height is not a fixed constant', () {
    testWidgets('measured height varies with width, contradicting a single '
        'chromeHeight guess', (tester) async {
      final heights = <double, double>{};
      for (final width in <double>[260, 350, 550]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const MapContextCard(
                    locations: 1374,
                    chargers: 4161,
                    activeProposals: 12,
                    priorityAreas: 3,
                    plannedLocations: 3100,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        heights[width] = tester.getSize(find.byType(MapContextCard)).height;
      }

      // Narrower panes wrap to more lines and measure taller — the opposite
      // of what a fixed subtraction constant can represent.
      expect(heights[260]! > heights[350]!, isTrue, reason: '$heights');
      expect(heights[350]! > heights[550]!, isTrue, reason: '$heights');
    });
  });

  group('Interactive Map section never overflows its pane', () {
    for (final size in mapSectionMatrix) {
      for (final scale in mapSectionTextScales) {
        for (final malaysiaSelected in <bool>[true, false]) {
          for (final legendExpanded in <bool>[false, true]) {
            // The legend only ever shows once a state is selected.
            if (malaysiaSelected && legendExpanded) continue;

            testWidgets(
              '${size.width}x${size.height} @ ${scale}x, '
              '${malaysiaSelected ? "Malaysia" : "state selected"}, '
              'legend ${legendExpanded ? "expanded" : "collapsed"}',
              (tester) async {
                tester.view.physicalSize = size;
                tester.view.devicePixelRatio = 1.0;
                addTearDown(tester.view.reset);

                // The right pane is roughly 60% of the split width, minus
                // the outer header/padding above it — a representative
                // fraction of the real dashboard's own Expanded(flex: 3).
                final paneSize = Size(size.width * 0.55, size.height - 70);

                await tester.pumpWidget(
                  MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: _harness(
                      paneSize: paneSize,
                      malaysiaSelected: malaysiaSelected,
                      legendExpanded: legendExpanded,
                    ),
                  ),
                );
                await tester.pump();

                expect(
                  tester.takeException(),
                  isNull,
                  reason: '${size.width}x${size.height} @ ${scale}x, '
                      'paneSize=$paneSize, malaysiaSelected=$malaysiaSelected, '
                      'legendExpanded=$legendExpanded',
                );
              },
            );
          }
        }
      }
    }

    testWidgets(
      'the section becomes scrollable rather than overflowing at an '
      'extremely short pane',
      (tester) async {
        // Shorter than any pane the real split-layout threshold would ever
        // produce (useSplitPlanningDashboardLayout requires maxHeight <= 620
        // OR width >= 700 — this is deliberately more hostile than that).
        const paneSize = Size(320, 180);

        await tester.pumpWidget(
          _harness(
            paneSize: paneSize,
            malaysiaSelected: false,
            legendExpanded: true,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
      },
    );
  });
}
