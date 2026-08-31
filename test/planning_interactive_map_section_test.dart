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

Widget _interactiveMapSection({
  required BoxConstraints paneConstraints,
  required bool malaysiaSelected,
  required bool legendExpanded,
}) =>
    LayoutBuilder(
      builder: (context, mapConstraints) {
        final mapHeight = (mapConstraints.maxHeight * 0.55).clamp(180.0, 420.0);
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
    testWidgets(
        'measured height varies with width, contradicting a single '
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

      expect(heights[260]! > heights[350]!, isTrue, reason: '$heights');
      expect(heights[350]! > heights[550]!, isTrue, reason: '$heights');
    });
  });

  group('Interactive Map section never overflows its pane', () {
    for (final size in mapSectionMatrix) {
      for (final scale in mapSectionTextScales) {
        for (final malaysiaSelected in <bool>[true, false]) {
          for (final legendExpanded in <bool>[false, true]) {
            if (malaysiaSelected && legendExpanded) continue;

            testWidgets(
              '${size.width}x${size.height} @ ${scale}x, '
              '${malaysiaSelected ? "Malaysia" : "state selected"}, '
              'legend ${legendExpanded ? "expanded" : "collapsed"}',
              (tester) async {
                tester.view.physicalSize = size;
                tester.view.devicePixelRatio = 1.0;
                addTearDown(tester.view.reset);

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
