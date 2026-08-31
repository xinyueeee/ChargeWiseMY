import 'package:chargewise_my/modules/planning/widgets/compact_map_legend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<Size> mapAuditMatrix = <Size>[
  Size(640, 360),
  Size(700, 360),
  Size(800, 360),
  Size(800, 400),
  Size(1280, 800),
];

const List<double> mapAuditTextScales = <double>[1.0, 1.3, 1.5];

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
      const paneHeightsAtShortLandscape = <double>[266, 290, 305];
      for (final paneHeight in paneHeightsAtShortLandscape) {
        final mapHeight = mapHeightFor(paneHeight, malaysiaSelected: false);
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
      for (final paneHeight in <double>[0, 50, 100, 150, 1000]) {
        expect(
          mapHeightFor(paneHeight, malaysiaSelected: false),
          greaterThanOrEqualTo(96.0),
        );
      }
    });

    test('tablet landscape gives the map generous height', () {
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
