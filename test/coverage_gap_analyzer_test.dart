import 'dart:math' as math;

import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/coverage_gap_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates ranked coverage gaps from station coordinates', () async {
    const stations = <ChargingStation>[
      ChargingStation(
        id: 'kl',
        name: 'Kuala Lumpur',
        latitude: 3.139,
        longitude: 101.6869,
        chargerType: 'DC',
      ),
      ChargingStation(
        id: 'johor',
        name: 'Johor Bahru',
        latitude: 1.4927,
        longitude: 103.7414,
        chargerType: 'AC',
      ),
    ];

    final gaps = await const CoverageGapAnalyzer().analyze(stations);

    expect(gaps, isNotEmpty);
    expect(gaps.length, lessThanOrEqualTo(CoverageGapAnalyzer.maximumResults));
    expect(
      gaps.every(
        (gap) =>
            gap.id.startsWith('gap_') &&
            gap.priority == 'High' &&
            gap.distance >=
                CoverageGapAnalyzer.minimumNearestStationKm &&
            gap.reason.contains('nearest station'),
      ),
      isTrue,
    );
    expect(
      gaps.map((gap) => gap.priorityScore).toSet().length,
      greaterThan(1),
    );
    for (var first = 0; first < gaps.length; first++) {
      for (var second = first + 1; second < gaps.length; second++) {
        expect(
          _distanceKm(gaps[first], gaps[second]),
          greaterThanOrEqualTo(
            CoverageGapAnalyzer.minimumSeparationKm - .01,
          ),
        );
      }
    }
  });

  test('returns the same ordered result for any station input order', () async {
    const stations = <ChargingStation>[
      ChargingStation(
        id: 'station_b',
        name: 'Second',
        latitude: 5.4141,
        longitude: 100.3288,
        chargerType: 'AC',
      ),
      ChargingStation(
        id: 'station_a',
        name: 'First',
        latitude: 3.139,
        longitude: 101.6869,
        chargerType: 'DC',
      ),
    ];
    const analyzer = CoverageGapAnalyzer();

    final forward = await analyzer.analyze(stations);
    final reverse = await analyzer.analyze(stations.reversed.toList());

    expect(
      forward.map((area) => area.id).toList(),
      reverse.map((area) => area.id).toList(),
    );
    expect(
      forward.map((area) => area.priorityScore).toList(),
      reverse.map((area) => area.priorityScore).toList(),
    );
  });
}

double _distanceKm(GapArea first, GapArea second) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta =
      (second.latitude! - first.latitude!) * math.pi / 180;
  final longitudeDelta =
      (second.longitude! - first.longitude!) * math.pi / 180;
  final firstLatitude = first.latitude! * math.pi / 180;
  final secondLatitude = second.latitude! * math.pi / 180;
  final value =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
          math.cos(firstLatitude) *
              math.cos(secondLatitude) *
              math.sin(longitudeDelta / 2) *
              math.sin(longitudeDelta / 2);
  return earthRadiusKm *
      2 *
      math.atan2(math.sqrt(value), math.sqrt(1 - value));
}
