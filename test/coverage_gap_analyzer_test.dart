import 'dart:math' as math;

import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/coverage_gap_analyzer.dart';
import 'package:chargewise_my/modules/planning/services/state_boundary_service.dart';
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
            gap.state.isNotEmpty &&
            const {'High', 'Medium', 'Low'}.contains(gap.priority) &&
            gap.coverageScore > 0 &&
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
    for (final gap in gaps) {
      final distances = stations
          .map((station) => _stationDistanceKm(gap, station))
          .toList();
      expect(gap.distance, closeTo(distances.reduce(math.min), .000001));
      expect(
        gap.nearbyStationCount,
        distances
            .where(
              (distance) =>
                  distance <= CoverageGapAnalyzer.nearbyRadiusKm,
            )
            .length,
      );
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

  test('state analysis ranks candidates inside the selected polygon', () async {
    const stations = <ChargingStation>[
      ChargingStation(
        id: 'west',
        name: 'West Malaysia',
        latitude: 3.139,
        longitude: 101.6869,
        chargerType: 'DC',
      ),
      ChargingStation(
        id: 'east',
        name: 'East Malaysia',
        latitude: 5.9804,
        longitude: 116.0735,
        chargerType: 'DC',
      ),
    ];
    final analyzer = _CountingCoverageGapAnalyzer();
    final selangorAreas = await analyzer.analyze(
      stations,
      selectedState: 'Selangor',
    );
    final sarawakAreas = await analyzer.analyze(
      stations,
      selectedState: 'Sarawak',
    );

    expect(selangorAreas, isNotEmpty);
    expect(selangorAreas.every((area) => area.state == 'Selangor'), isTrue);
    expect(sarawakAreas, isNotEmpty);
    expect(sarawakAreas.every((area) => area.state == 'Sarawak'), isTrue);
    expect(analyzer.executionCount, 2);
  });

  test('GeoJSON supplies the complete Malaysian state selector', () async {
    final boundaries = StateBoundaryService();
    await boundaries.load();
    expect(
      boundaries.stateOptions,
      const <String>[
        'Malaysia',
        'Johor',
        'Kedah',
        'Kelantan',
        'Kuala Lumpur',
        'Labuan',
        'Melaka',
        'Negeri Sembilan',
        'Pahang',
        'Penang',
        'Perak',
        'Perlis',
        'Putrajaya',
        'Sabah',
        'Sarawak',
        'Selangor',
        'Terengganu',
      ],
    );
    expect(boundaries.regions, hasLength(16));
    expect(
      boundaries.regions.every(
        (region) => region.contains(
          region.labelPoint.latitude,
          region.labelPoint.longitude,
        ),
      ),
      isTrue,
      reason: 'Every national count badge must be positioned on state land.',
    );
  });
}

class _CountingCoverageGapAnalyzer extends CoverageGapAnalyzer {
  int executionCount = 0;

  @override
  Future<List<GapArea>> analyze(
    List<ChargingStation> stations, {
    String selectedState = malaysiaSelection,
  }) {
    executionCount++;
    return super.analyze(stations, selectedState: selectedState);
  }
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

double _stationDistanceKm(GapArea area, ChargingStation station) {
  final stationArea = GapArea(
    id: station.id,
    name: station.name,
    state: 'Test',
    priority: 'Test',
    distance: 0,
    nearbyStationCount: 0,
    priorityScore: 0,
    reason: '',
    latitude: station.latitude,
    longitude: station.longitude,
  );
  return _distanceKm(area, stationArea);
}
