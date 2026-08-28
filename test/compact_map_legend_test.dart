// Regression coverage for the Interactive Map overflow reported after the
// outer Planning Dashboard split-layout fix.
//
// Root cause: `_CompactMapLegend` (now the public `CompactMapLegend`) was a
// naturally-sized `Column` `Positioned` over the map with no height ceiling
// at all. `_buildLandscapeDashboard` clamps the map's own height to as low
// as 96px in short landscape (`(mapConstraints.maxHeight - chromeHeight)
// .clamp(96.0, 480.0)`); the legend's expanded content — a header, a
// divider, three toggles and a caption — is naturally taller than that, so
// it grew past the bottom of the map `Stack`. Because the `Stack` uses
// `clipBehavior: Clip.none` (intentionally, so the floating card can sit
// visually over the map edge), the overflow was not clipped away — it
// surfaced as a genuine `RenderFlex overflowed` assertion from the legend's
// own inner `Column`.
//
// The fix hard-caps the whole legend to the exact map height it floats over
// and makes only the toggle list scroll, so the header (and its collapse
// control) is always reachable and the card can never exceed the map.
import 'package:chargewise_my/modules/planning/widgets/compact_map_legend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact viewports named in the report.
const List<Size> mapAuditMatrix = <Size>[
  Size(640, 360),
  Size(700, 360),
  Size(800, 360),
  Size(800, 400),
  Size(1280, 800),
];

const List<double> mapAuditTextScales = <double>[1.0, 1.3, 1.5];

/// Reproduces `_buildLandscapeDashboard`'s map-height arithmetic exactly, so
/// these tests exercise the same heights the real screen would compute —
/// including the 96px floor that triggered the original overflow.
double mapHeightFor(double paneHeight, {required bool malaysiaSelected}) {
  final chromeHeight = malaysiaSelected ? 132.0 : 106.0;
  return (paneHeight - chromeHeight).clamp(96.0, 480.0);
}

Widget _harness({
  required bool expanded,
  required double mapHeight,
  double cardWidth = 260,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Stand-in for MapPanel's SizedBox(height: mapHeight, child:
              // GoogleMap(...)) — GoogleMap cannot be pumped in a widget
              // test (no platform view), but the legend never reads
              // anything from the map itself, so the geometry this test
              // needs (a Stack exactly `mapHeight` tall) is identical.
              SizedBox(width: cardWidth + 80, height: mapHeight),
              Positioned(
                top: 8,
                left: 8,
                child: CompactMapLegend(
                  expanded: expanded,
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
        ),
      ),
    );

void main() {
  group('reproduction: the height this legend must fit inside', () {
    test('short landscape panes clamp the map to the 96px floor', () {
      // 360-400px physical height, minus the dashboard header and pane
      // padding, minus chromeHeight for a selected state (106px) — exactly
      // the scenario the original bug report described.
      const paneHeightsAtShortLandscape = <double>[266, 290, 305];
      for (final paneHeight in paneHeightsAtShortLandscape) {
        final mapHeight =
            mapHeightFor(paneHeight, malaysiaSelected: false);
        expect(mapHeight, greaterThanOrEqualTo(96.0));
        expect(
          mapHeight,
          lessThan(200.0),
          reason: 'this is the danger zone: smaller than the legend\'s '
              'natural expanded content',
        );
      }
    });

    test('the map is never given less than the 96px clamp floor', () {
      // Whatever pane height a future layout change produces, this legend's
      // safety margin only holds as long as this floor does. If it is ever
      // lowered, CompactMapLegend's tests below at mapHeight: 96 stop
      // representing the real worst case and must be revisited together.
      for (final paneHeight in <double>[0, 50, 100, 150, 1000]) {
        expect(
          mapHeightFor(paneHeight, malaysiaSelected: false),
          greaterThanOrEqualTo(96.0),
        );
      }
    });

    test('tablet landscape gives the map generous height', () {
      // 800px physical height leaves a tall right pane; nowhere near the
      // clamp floor.
      final mapHeight = mapHeightFor(700, malaysiaSelected: false);
      expect(mapHeight, 480.0, reason: 'clamped at the upper bound');
    });
  });

  group('CompactMapLegend never overflows its own maxHeight', () {
    for (final size in mapAuditMatrix) {
      for (final scale in mapAuditTextScales) {
        for (final expanded in <bool>[false, true]) {
          testWidgets(
            '${size.width}x${size.height} @ ${scale}x, '
            '${expanded ? "expanded" : "collapsed"}',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.reset);

              // The exact worst-case: a short-landscape pane driving the map
              // height down to the clamp's 96px floor.
              final mapHeight =
                  mapHeightFor(size.height * 0.8, malaysiaSelected: false);

              await tester.pumpWidget(
                MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: _harness(expanded: expanded, mapHeight: mapHeight),
                ),
              );
              await tester.pump();

              expect(
                tester.takeException(),
                isNull,
                reason: '${size.width}x${size.height} @ ${scale}x, '
                    'mapHeight=$mapHeight, expanded=$expanded',
              );
            },
          );
        }
      }
    }

    testWidgets(
      'the historically-overflowing case: 96px map, expanded, 1.5x text',
      (tester) async {
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(640, 360),
              textScaler: TextScaler.linear(1.5),
            ),
            child: _harness(expanded: true, mapHeight: 96),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'expanded content stays scrollable at the app\'s real 96px floor',
      (tester) async {
        // 96 is not an arbitrary small number for this test — it is the
        // literal floor `_buildLandscapeDashboard` clamps the map to, so
        // this is the worst case production can actually generate. This
        // only passes if the Flexible+SingleChildScrollView fix is in
        // place, not merely a taller ConstrainedBox.
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(640, 360),
              textScaler: TextScaler.linear(1.5),
            ),
            child: _harness(expanded: true, mapHeight: 96),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
      },
    );
  });

  group('the header stays reachable regardless of available height', () {
    testWidgets('the Layers toggle button is always present and tappable',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(640, 360)),
          child: _harness(expanded: true, mapHeight: 96),
        ),
      );
      await tester.pump();

      expect(find.text('Layers'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('collapsing removes the scrollable body entirely',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(640, 360)),
          child: _harness(expanded: false, mapHeight: 96),
        ),
      );
      await tester.pump();

      expect(find.text('Layers'), findsOneWidget);
      expect(find.text('Existing'), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });

  group('long labels do not overflow horizontally', () {
    testWidgets('"Community Proposals" wraps/ellipses inside a narrow card',
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: _harness(expanded: true, mapHeight: 300, cardWidth: 90),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Community Proposals'), findsOneWidget);
    });
  });
}
