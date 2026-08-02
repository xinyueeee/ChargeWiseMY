import 'dart:math' as math;

import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/analysis_profile.dart';
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

  test('analysis profiles are geographic and refinement stays modest', () {
    expect(
      AnalysisProfileConfig.definitionFor('Kuala Lumpur').profile,
      AnalysisProfile.denseUrban,
    );
    expect(
      AnalysisProfileConfig.definitionFor('Johor').profile,
      AnalysisProfile.urban,
    );
    expect(
      AnalysisProfileConfig.definitionFor('Sabah').profile,
      AnalysisProfile.regional,
    );

    final johor = AnalysisProfileConfig.resolve(
      'Johor',
      const {
        'Johor': 540,
        'Selangor': 300,
        'Penang': 180,
        'Melaka': 120,
        'Negeri Sembilan': 160,
      },
    );
    expect(johor.definition.profile, AnalysisProfile.urban);
    expect(
      johor.refinementFactor,
      inInclusiveRange(
        AnalysisProfileConfig.minimumRefinementFactor,
        AnalysisProfileConfig.maximumRefinementFactor,
      ),
    );
    expect(johor.refinementFactor, lessThan(1));
  });

  test('Dense Urban uses versioned neighbourhood strategy', () {
    final profile = AnalysisProfileConfig.resolve(
      'Kuala Lumpur',
      const {'Kuala Lumpur': 623, 'Putrajaya': 40},
    );
    expect(profile.definition.profile, AnalysisProfile.denseUrban);
    expect(profile.nearbyRadiusKm, 3);
    expect(profile.retainedCandidateLimit, 16);
    expect(
      profile.cacheToken,
      contains(
        'dense-strategy-'
        '${AnalysisProfileConfig.denseUrbanStrategyVersion}',
      ),
    );
  });

  test('Dense Urban qualifies relative scarcity without a distance gate', () {
    expect(
      CoverageGapAnalyzer.denseUrbanCellQualifies(
        localStationLocationCount: 0,
        localScarcity: .8,
        neighbourhoodScarcity: .4,
      ),
      isTrue,
    );
    expect(
      CoverageGapAnalyzer.denseUrbanCellQualifies(
        localStationLocationCount: 3,
        localScarcity: 0,
        neighbourhoodScarcity: .05,
      ),
      isFalse,
      reason: 'A well-covered cell must not be manufactured into a gap.',
    );
  });

  test('raw duplicates do not change Dense Urban neighbourhood results',
      () async {
    const unique = <ChargingStation>[
      ChargingStation(
        id: 'a',
        name: 'A',
        latitude: 3.132,
        longitude: 101.688,
        chargerType: 'DC',
      ),
      ChargingStation(
        id: 'b',
        name: 'B',
        latitude: 3.150,
        longitude: 101.706,
        chargerType: 'AC',
      ),
    ];
    const duplicates = <ChargingStation>[
      ...unique,
      ChargingStation(
        id: 'a-copy-1',
        name: 'A duplicate',
        latitude: 3.132,
        longitude: 101.688,
        chargerType: 'DC',
      ),
      ChargingStation(
        id: 'a-copy-2',
        name: 'A near duplicate',
        latitude: 3.1321,
        longitude: 101.6881,
        chargerType: 'DC',
      ),
    ];
    const analyzer = CoverageGapAnalyzer();
    final uniqueResult = await analyzer.analyze(
      unique,
      selectedState: 'Kuala Lumpur',
      stationCountsByState: const {'Kuala Lumpur': 4, 'Putrajaya': 4},
    );
    final duplicateResult = await analyzer.analyze(
      duplicates,
      selectedState: 'Kuala Lumpur',
      stationCountsByState: const {'Kuala Lumpur': 4, 'Putrajaya': 4},
    );
    expect(
      duplicateResult.map((area) => area.id).toList(),
      uniqueResult.map((area) => area.id).toList(),
    );
    expect(
      duplicateResult.map((area) => area.nearbyStationCount).toList(),
      uniqueResult.map((area) => area.nearbyStationCount).toList(),
    );
  });

  test('Dense Urban can retain scarcity below old distance gate', () async {
    const stations = <ChargingStation>[
      ChargingStation(
        id: 'north',
        name: 'North',
        latitude: 3.150,
        longitude: 101.688,
        chargerType: 'AC',
      ),
      ChargingStation(
        id: 'south',
        name: 'South',
        latitude: 3.114,
        longitude: 101.688,
        chargerType: 'AC',
      ),
      ChargingStation(
        id: 'east',
        name: 'East',
        latitude: 3.132,
        longitude: 101.706,
        chargerType: 'DC',
      ),
      ChargingStation(
        id: 'west',
        name: 'West',
        latitude: 3.132,
        longitude: 101.670,
        chargerType: 'DC',
      ),
    ];
    final gaps = await const CoverageGapAnalyzer().analyze(
      stations,
      selectedState: 'Kuala Lumpur',
      stationCountsByState: const {'Kuala Lumpur': 4, 'Putrajaya': 4},
    );
    expect(gaps, isNotEmpty);
    expect(
      gaps.any(
        (area) =>
            area.analysisProfileId == AnalysisProfile.denseUrban.name &&
            area.distance < 2.5,
      ),
      isTrue,
    );
  });

  test('Dense Urban results are separated and deterministic', () async {
    const stations = <ChargingStation>[
      ChargingStation(
        id: 'one',
        name: 'One',
        latitude: 3.139,
        longitude: 101.6869,
        chargerType: 'DC',
      ),
    ];
    const analyzer = CoverageGapAnalyzer();
    final first = await analyzer.analyze(
      stations,
      selectedState: 'Kuala Lumpur',
    );
    final second = await analyzer.analyze(
      stations,
      selectedState: 'Kuala Lumpur',
    );
    expect(
      first.map((area) => area.id).toList(),
      second.map((area) => area.id).toList(),
    );
    final separation = AnalysisProfileConfig.resolve(
      'Kuala Lumpur',
      const {},
    ).candidateSeparationKm;
    for (var a = 0; a < first.length; a++) {
      for (var b = a + 1; b < first.length; b++) {
        expect(_distanceKm(first[a], first[b]), greaterThanOrEqualTo(separation));
      }
    }
  });
}

class _CountingCoverageGapAnalyzer extends CoverageGapAnalyzer {
  int executionCount = 0;

  @override
  Future<List<GapArea>> analyze(
    List<ChargingStation> stations, {
    String selectedState = malaysiaSelection,
    Map<String, int> stationCountsByState = const {},
  }) {
    executionCount++;
    return super.analyze(
      stations,
      selectedState: selectedState,
      stationCountsByState: stationCountsByState,
    );
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
