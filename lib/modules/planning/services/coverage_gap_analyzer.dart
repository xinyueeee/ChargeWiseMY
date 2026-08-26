import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/proposal.dart';
import 'analysis_profile.dart';
import 'state_boundary_service.dart';

class CoverageGapAnalyzer {
  const CoverageGapAnalyzer();

  static const bool _verboseCandidateDiagnostics = bool.fromEnvironment(
    'CHARGEWISE_VERBOSE_GAP_DIAGNOSTICS',
    defaultValue: false,
  );

  static const double stationSiteDeduplicationRadiusMetres = 75;
  static const int stationSiteDeduplicationVersion = 1;
  static const String stationSiteDeduplicationCacheToken =
      'site-dedup-v1-radius75m';

  static Future<List<Map<String, Object?>>>? _landBoundariesCache;
  static Future<List<Map<String, Object?>>>? _settlementsCache;

  static const double gridSpacingDegrees = 0.18;
  static const double nearbyRadiusKm = 25;
  static const double minimumNearestStationKm = 15;
  static const double minimumSeparationKm = 35;
  static const int maximumResults = 20;

  @visibleForTesting
  static bool denseUrbanCellQualifies({
    required int localStationLocationCount,
    required double localScarcity,
    required double neighbourhoodScarcity,
  }) =>
      localStationLocationCount <= 1 &&
      (localScarcity >= .30 || neighbourhoodScarcity >= .30);

  Future<List<GapArea>> analyze(
    List<ChargingStation> stations, {
    String selectedState = malaysiaSelection,
    Map<String, int> stationCountsByState = const {},
  }) async {
    final sortedStations = List<ChargingStation>.of(stations)
      ..sort((a, b) {
        final idComparison = a.id.compareTo(b.id);
        if (idComparison != 0) return idComparison;
        final latitudeComparison = a.latitude.compareTo(b.latitude);
        if (latitudeComparison != 0) return latitudeComparison;
        return a.longitude.compareTo(b.longitude);
      });
    final stopwatch = Stopwatch()..start();
    final resolvedProfile = AnalysisProfileConfig.resolve(
      selectedState,
      stationCountsByState,
    );
    final landBoundaries = await _loadLandBoundaries();
    final settlements = await _loadSettlements();
    final result = await compute(
      _runCoverageGapAnalysis,
      <String, Object>{
        'stations': [
          for (final station in sortedStations)
            <double>[station.latitude, station.longitude],
        ],
        'landBoundaries': landBoundaries,
        'settlements': settlements,
        'selectedState': selectedState,
        'analysisParameters': resolvedProfile.toPayload(),
      },
    );
    stopwatch.stop();

    final areaMaps =
        (result['areas'] as List<Object?>).cast<Map<Object?, Object?>>();
    final areas = areaMaps.map(GapArea.fromAnalysis).toList(growable: false);
    final roadValidatedCandidates =
        areas.where((area) => area.roadAccessibilityValidated).length;
    final adjustedTowardRoad =
        areas.where((area) => area.coordinateAdjusted).length;
    final highPriorityCount =
        areas.where((area) => area.priority == 'High').length;
    final mediumPriorityCount =
        areas.where((area) => area.priority == 'Medium').length;
    final lowPriorityCount =
        areas.where((area) => area.priority == 'Low').length;
    final bruteForceDistanceChecks =
        (result['stationCount'] as int) * (result['gridCellCount'] as int);
    final indexedDistanceChecks = result['distanceCheckCount'] as int;
    final checkReductionPercent = bruteForceDistanceChecks == 0
        ? 0.0
        : (1 - indexedDistanceChecks / bruteForceDistanceChecks) * 100;

    debugPrint(
      'Analysis profile: state=$selectedState, '
      'profile=${resolvedProfile.definition.displayName}, '
      'landBoundaryDataset=$malaysiaStateBoundaryDatasetVersion, '
      'stationRecordCount=${result['selectedStateStationRecordCount']}, '
      'uniqueCoordinates=${result['selectedStateUniqueCoordinateCount']}, '
      'distinctSites50m=${result['selectedStateSiteCount50m']}, '
      'distinctSites75m=${result['selectedStateSiteCount75m']}, '
      'distinctSites100m=${result['selectedStateSiteCount100m']}, '
      'profileAverage='
      '${resolvedProfile.profileAverageStationCount.toStringAsFixed(1)}, '
      'refinementFactor=${resolvedProfile.refinementFactor.toStringAsFixed(2)}, '
      'gridSpacingKm=${resolvedProfile.gridSpacingKm.toStringAsFixed(2)}, '
      'candidateSeparationKm='
      '${resolvedProfile.candidateSeparationKm.toStringAsFixed(2)}, '
      'GeneratedCandidates=${result['candidateCount']}, '
      'GeneratedCandidateCells=${result['gridCellCount']}, '
      'LandValidCandidateCells=${result['landValidGridCellCount']}, '
      'CoverageQualifiedLandValidated=${result['landValidatedCount']}, '
      'Retained=${areas.length}, '
      'RejectedNearbyLocationsTooHigh='
      '${result['rejectedByNearbyLocationCount']}, '
      'RejectedNearestDistanceTooLow='
      '${result['rejectedByMinimumDistanceCount']}, '
      'RejectedBySeparation=${result['rejectedBySeparationCount']}.',
    );
    debugPrint(
      'Coverage-gap diagnostics: '
      '${result['stationRecordCount']} station records preserved; '
      '${result['stationCount']} deduplicated station locations analyzed '
      '(radius=${stationSiteDeduplicationRadiusMetres.toStringAsFixed(0)}m, '
      'version=$stationSiteDeduplicationVersion); '
      'state=$selectedState; '
      '${result['gridCellCount']} grid cells evaluated; '
      '$indexedDistanceChecks station-distance checks '
      '(brute-force baseline=$bruteForceDistanceChecks, '
      'reduction=${checkReductionPercent.toStringAsFixed(1)}%); '
      '${result['candidateCount']} candidate gap areas found; '
      '${result['correctedOffshoreCount']} offshore candidates corrected; '
      '${result['rejectedOffshoreCount']} offshore candidates rejected; '
      '${areas.length} final non-overlapping priority areas returned; '
      '${stopwatch.elapsedMilliseconds}ms analysis duration.',
    );
    debugPrint(
      'Road-access diagnostics: '
      'dataset=${AnalysisProfileConfig.roadDatasetVersion}, '
      'coverageQualifiedCandidates=${result['candidateCount']}, '
      'roadValidatedCandidates=$roadValidatedCandidates, '
      'adjustedTowardRoad=$adjustedTowardRoad, '
      'rejectedRoadTooFar=0, rejectedRoadOutsideState=0, '
      'rejectedNoValidRoadReplacement=0, finalRetained=${areas.length}.',
    );
    debugPrint(
      'Settlement-eligibility diagnostics: '
      'dataset=${AnalysisProfileConfig.settlementDatasetVersion}, '
      'generatedCandidates=${result['candidateCount']}, '
      'landValidCandidates=${result['landValidatedCount']}, '
      'rejectedTooFarFromSettlement='
      '${result['rejectedTooFarFromSettlement'] ?? 0}, '
      'replacementCandidatesEvaluated='
      '${result['replacementCandidatesEvaluated'] ?? 0}, '
      'replacementCandidatesAccepted='
      '${result['replacementCandidatesAccepted'] ?? 0}, '
      'rejectedNoSettlementRelevantPoint='
      '${result['rejectedNoSettlementRelevantPoint'] ?? 0}, '
      'retainedAfterCoverage=${result['retainedAfterCoverage'] ?? 0}, '
      'retainedAfterSeparation='
      '${result['retainedAfterSeparation'] ?? areas.length}, '
      'finalRetained=${areas.length}, '
      'groupedBySettlement=${result['settlementRetainedCounts'] ?? {}}.',
    );
    debugPrint(
      'State gap-quality audit: state=$selectedState, '
      'stationRecords=${result['selectedStateStationRecordCount']}, '
      'distinctStationLocations75m=${result['selectedStateSiteCount75m']}, '
      'generatedCandidatesOrCells=${result['gridCellCount']}, '
      'landValidCandidates=${result['landValidatedCount']}, '
      'settlementEligibleCandidates='
      '${result['settlementEligibleCandidates'] ?? 0}, '
      'rejectedByCoverage=${result['rejectedByCoverageCount']}, '
      'rejectedBySettlementDistance='
      '${result['rejectedTooFarFromSettlement'] ?? 0}, '
      'rejectedBySeparation=${result['rejectedBySeparationCount']}, '
      'retainedGaps=${areas.length}, high=$highPriorityCount, '
      'medium=$mediumPriorityCount, low=$lowPriorityCount.',
    );
    if (resolvedProfile.definition.profile == AnalysisProfile.denseUrban) {
      debugPrint(
        'Dense Urban diagnostics: '
        'stationRecordCount=${result['selectedStateStationRecordCount']}, '
        'distinctStationSiteCount=${result['selectedStateSiteCount75m']}, '
        'generatedNeighbourhoodCells=${result['gridCellCount']}, '
        'landValidCells=${result['landValidGridCellCount']}, '
        'cellsWithZeroSites=${result['cellsWithZeroSites']}, '
        'cellsWithOneSite=${result['cellsWithOneSite']}, '
        'cellsWithTwoOrMoreSites=${result['cellsWithTwoOrMoreSites']}, '
        'localSiteCountDistribution='
        '${result['localSiteCountDistribution']}, '
        'neighbourhoodSiteCountDistribution='
        '${result['neighbourhoodSiteCountDistribution']}, '
        'cellsRejectedAsWellCovered='
        '${result['cellsRejectedAsWellCovered']}, '
        'cellsRejectedAsTinyBoundaryFragments='
        '${result['cellsRejectedAsTinyBoundaryFragments']}, '
        'cellsMergedWithAdjacentCandidates='
        '${result['cellsMergedWithAdjacentCandidates']}, '
        'candidatesBeforeSeparation=${result['candidateCount']}, '
        'finalRetainedCandidates=${areas.length}, '
        'analysisDuration=${stopwatch.elapsedMilliseconds}ms.',
      );
    }
    if (_verboseCandidateDiagnostics) {
      for (final diagnostic in (result['landDiagnostics'] as List<Object?>)
          .cast<Map<Object?, Object?>>()) {
        debugPrint(
          'Coverage-gap land validation: '
          'original=(${diagnostic['originalLatitude']}, '
          '${diagnostic['originalLongitude']}), '
          'result=${diagnostic['result']}, '
          'corrected=(${diagnostic['correctedLatitude'] ?? 'n/a'}, '
          '${diagnostic['correctedLongitude'] ?? 'n/a'}), '
          'state=${diagnostic['state'] ?? 'n/a'}.',
        );
      }
      for (var index = 0; index < areas.length; index++) {
        final area = areas[index];
        double? closestSelectedAreaKm;
        if (index > 0 && area.latitude != null && area.longitude != null) {
          closestSelectedAreaKm = areas
              .take(index)
              .where(
                (other) => other.latitude != null && other.longitude != null,
              )
              .map(
                (other) => _distanceKm(
                  area.latitude!,
                  area.longitude!,
                  other.latitude!,
                  other.longitude!,
                ),
              )
              .reduce(math.min);
        }
        debugPrint(
          'Coverage-gap selected #${index + 1}: '
          'original=(${areaMaps[index]['originalLatitude']}, '
          '${areaMaps[index]['originalLongitude']}), '
          'landValidation=${areaMaps[index]['landValidationResult']}, '
          'lat=${area.latitude?.toStringAsFixed(4)}, '
          'lng=${area.longitude?.toStringAsFixed(4)}, '
          'label="${area.name}", '
          'nearestStation=${area.distance.toStringAsFixed(1)}km, '
          'closestPreviouslySelected='
          '${closestSelectedAreaKm?.toStringAsFixed(1) ?? 'n/a'}km, '
          'score=${area.priorityScore.toStringAsFixed(0)}.',
        );
        debugPrint(
          'Road-access retained #${index + 1}: '
          'originalCoordinate='
          '(${area.originalAnalyticalLatitude?.toStringAsFixed(5)}, '
          '${area.originalAnalyticalLongitude?.toStringAsFixed(5)}), '
          'adjustedCoordinate=(${area.latitude?.toStringAsFixed(5)}, '
          '${area.longitude?.toStringAsFixed(5)}), '
          'nearestRoadDistanceMeters='
          '${area.nearestRoadDistanceMeters?.toStringAsFixed(1) ?? 'unavailable'}, '
          'adjustmentDistanceMeters='
          '${area.adjustmentDistanceMeters.toStringAsFixed(1)}, '
          'profile=${area.analysisProfileId}, '
          'validated=${area.roadAccessibilityValidated}, '
          'priorityScore=${area.priorityScore.toStringAsFixed(0)}.',
        );
        debugPrint(
          'Settlement retained #${index + 1}: '
          'coordinate=(${area.latitude?.toStringAsFixed(5)}, '
          '${area.longitude?.toStringAsFixed(5)}), '
          'nearestSettlement=${area.nearestSettlementName ?? 'unavailable'}, '
          'settlementCategory='
          '${area.nearestSettlementCategory ?? 'unavailable'}, '
          'distanceToSettlementKm='
          '${area.distanceToSettlementKm?.toStringAsFixed(1) ?? 'unavailable'}, '
          'nearestStationDistanceKm=${area.distance.toStringAsFixed(1)}, '
          'nearbyStationLocations=${area.nearbyStationCount}, '
          'priorityScore=${area.priorityScore.toStringAsFixed(0)}.',
        );
        if (area.analysisProfileId == AnalysisProfile.denseUrban.name) {
          debugPrint(
            'Dense Urban selected #${index + 1}: '
            'coordinate=(${area.latitude?.toStringAsFixed(5)}, '
            '${area.longitude?.toStringAsFixed(5)}), '
            'localSites=${area.localStationLocationCount}, '
            'nearbySites=${area.nearbyStationCount}, '
            'nearestSite=${area.distance.toStringAsFixed(2)}km, '
            'neighbouringCellAverage='
            '${area.neighbouringCellAverage.toStringAsFixed(2)}, '
            'rawSeverity=${area.coverageScore.toStringAsFixed(2)}, '
            'normalizedScore=${area.priorityScore.toStringAsFixed(0)}, '
            'priority=${area.priority}.',
          );
        }
      }
    }
    return areas;
  }

  static Future<List<Map<String, Object?>>> _loadLandBoundaries() {
    return _landBoundariesCache ??= rootBundle
        .loadString('assets/data/malaysia_states.geojson')
        .then((source) {
      final collection = jsonDecode(source) as Map<String, Object?>;
      return (collection['features'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList(growable: false);
    });
  }

  static Future<List<Map<String, Object?>>> _loadSettlements() {
    return _settlementsCache ??= rootBundle
        .loadString('assets/data/malaysia_settlements.json')
        .then((source) {
      final document = jsonDecode(source) as Map<String, Object?>;
      return (document['settlements'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList(growable: false);
    });
  }
}

Map<String, Object> _runCoverageGapAnalysis(Map<String, Object> payload) {
  final selectedState = payload['selectedState'] as String;
  final parameters = _AnalysisParameters.fromPayload(
    payload['analysisParameters'] as Map<Object?, Object?>,
  );
  final settlementsByState = <String, List<_Settlement>>{};
  for (final settlementData in (payload['settlements'] as List<Object?>)
      .cast<Map<Object?, Object?>>()) {
    final settlement = _Settlement.fromMap(settlementData);
    (settlementsByState[settlement.state] ??= <_Settlement>[]).add(settlement);
  }
  for (final settlements in settlementsByState.values) {
    settlements.sort((a, b) => a.id.compareTo(b.id));
  }
  final stationCoordinates = (payload['stations'] as List<Object?>)
      .cast<List<Object?>>()
      .map(
        (coordinate) => _Coordinate(
          (coordinate[0] as num).toDouble(),
          (coordinate[1] as num).toDouble(),
        ),
      )
      .where(
        (coordinate) =>
            coordinate.latitude >= 0.5 &&
            coordinate.latitude <= 7.8 &&
            coordinate.longitude >= 99 &&
            coordinate.longitude <= 120,
      )
      .toList(growable: false);
  final allLandBoundaries = (payload['landBoundaries'] as List<Object?>)
      .cast<Map<Object?, Object?>>()
      .map(_LandBoundary.fromFeature)
      .toList(growable: false);
  final landBoundaries = selectedState == malaysiaSelection
      ? allLandBoundaries
      : allLandBoundaries
          .where((boundary) => boundary.state == selectedState)
          .toList(growable: false);

  final selectedStateStationCoordinates = selectedState == malaysiaSelection
      ? stationCoordinates
      : stationCoordinates
          .where(
            (coordinate) => landBoundaries.any(
              (boundary) => boundary.contains(
                coordinate.latitude,
                coordinate.longitude,
              ),
            ),
          )
          .toList(growable: false);
  final selectedStateUniqueCoordinateCount = selectedStateStationCoordinates
      .map(
        (coordinate) => '${coordinate.latitude.toStringAsFixed(8)}|'
            '${coordinate.longitude.toStringAsFixed(8)}',
      )
      .toSet()
      .length;
  final selectedStateSiteCount50m =
      _groupStationSites(selectedStateStationCoordinates, 50).length;
  final selectedStateSiteCount75m =
      _groupStationSites(selectedStateStationCoordinates, 75).length;
  final selectedStateSiteCount100m =
      _groupStationSites(selectedStateStationCoordinates, 100).length;
  final stationSites = _groupStationSites(
    stationCoordinates,
    CoverageGapAnalyzer.stationSiteDeduplicationRadiusMetres,
  );

  if (stationCoordinates.isEmpty) {
    return <String, Object>{
      'stationRecordCount': 0,
      'stationCount': 0,
      'selectedStateStationRecordCount': 0,
      'selectedStateUniqueCoordinateCount': 0,
      'selectedStateSiteCount50m': 0,
      'selectedStateSiteCount75m': 0,
      'selectedStateSiteCount100m': 0,
      'gridCellCount': 0,
      'landValidGridCellCount': 0,
      'distanceCheckCount': 0,
      'candidateCount': 0,
      'landValidatedCount': 0,
      'rejectedByCoverageCount': 0,
      'rejectedByNearbyLocationCount': 0,
      'rejectedByMinimumDistanceCount': 0,
      'rejectedBySeparationCount': 0,
      'correctedOffshoreCount': 0,
      'rejectedOffshoreCount': 0,
      'landDiagnostics': <Map<String, Object?>>[],
      'areas': <Map<String, Object>>[],
    };
  }
  if (landBoundaries.isEmpty) {
    return <String, Object>{
      'stationRecordCount': stationCoordinates.length,
      'stationCount': stationSites.length,
      'selectedStateStationRecordCount': selectedStateStationCoordinates.length,
      'selectedStateUniqueCoordinateCount': selectedStateUniqueCoordinateCount,
      'selectedStateSiteCount50m': selectedStateSiteCount50m,
      'selectedStateSiteCount75m': selectedStateSiteCount75m,
      'selectedStateSiteCount100m': selectedStateSiteCount100m,
      'gridCellCount': 0,
      'landValidGridCellCount': 0,
      'distanceCheckCount': 0,
      'candidateCount': 0,
      'landValidatedCount': 0,
      'rejectedByCoverageCount': 0,
      'rejectedByNearbyLocationCount': 0,
      'rejectedByMinimumDistanceCount': 0,
      'rejectedBySeparationCount': 0,
      'correctedOffshoreCount': 0,
      'rejectedOffshoreCount': 0,
      'landDiagnostics': <Map<String, Object?>>[],
      'areas': <Map<String, Object>>[],
    };
  }

  if (parameters.profileId == AnalysisProfile.denseUrban.name ||
      parameters.profileId == AnalysisProfile.urban.name) {
    return _runDistributionCoverageAnalysis(
      stationRecords: stationCoordinates,
      stationSites: stationSites,
      selectedStateStationCoordinates: selectedStateStationCoordinates,
      selectedStateUniqueCoordinateCount: selectedStateUniqueCoordinateCount,
      selectedStateSiteCount50m: selectedStateSiteCount50m,
      selectedStateSiteCount75m: selectedStateSiteCount75m,
      selectedStateSiteCount100m: selectedStateSiteCount100m,
      landBoundaries: landBoundaries,
      parameters: parameters,
      settlementsByState: settlementsByState,
    );
  }

  final candidates = <_GapCandidate>[];
  final stationIndex = _StationSpatialIndex(stationSites);
  final analysisBounds = _boundsForLandBoundaries(landBoundaries);
  var gridCellCount = 0;
  var landValidGridCellCount = 0;
  var correctedOffshoreCount = 0;
  var rejectedOffshoreCount = 0;
  var landValidatedCount = 0;
  var rejectedByCoverageCount = 0;
  var rejectedByNearbyLocationCount = 0;
  var rejectedByMinimumDistanceCount = 0;
  var rejectedBySeparationCount = 0;
  var rejectedTooFarFromSettlement = 0;
  var replacementCandidatesEvaluated = 0;
  var replacementCandidatesAccepted = 0;
  var rejectedNoSettlementRelevantPoint = 0;
  var settlementEligibleCandidates = 0;
  final landDiagnostics = <Map<String, Object?>>[];

  const latitudeOrigin = .9;
  const longitudeOrigin = 99.6;
  final gridSpacing = parameters.gridSpacingDegrees;
  final latitudeStart = math
      .max(
        0,
        ((analysisBounds.south - gridSpacing / 2 - latitudeOrigin) /
                gridSpacing)
            .floor(),
      )
      .toInt();
  final latitudeEnd = math
      .min(
        ((7.4 - latitudeOrigin) / gridSpacing).floor(),
        ((analysisBounds.north + gridSpacing / 2 - latitudeOrigin) /
                gridSpacing)
            .ceil(),
      )
      .toInt();
  final longitudeStart = math
      .max(
        0,
        ((analysisBounds.west - gridSpacing / 2 - longitudeOrigin) /
                gridSpacing)
            .floor(),
      )
      .toInt();
  final longitudeEnd = math
      .min(
        ((119.3 - longitudeOrigin) / gridSpacing).floor(),
        ((analysisBounds.east + gridSpacing / 2 - longitudeOrigin) /
                gridSpacing)
            .ceil(),
      )
      .toInt();

  for (var latitudeIndex = latitudeStart;
      latitudeIndex <= latitudeEnd;
      latitudeIndex++) {
    final latitude = latitudeOrigin + latitudeIndex * gridSpacing;
    for (var longitudeIndex = longitudeStart;
        longitudeIndex <= longitudeEnd;
        longitudeIndex++) {
      final longitude = longitudeOrigin + longitudeIndex * gridSpacing;
      if (!analysisBounds.includesGridCell(
        latitude,
        longitude,
        gridSpacing,
      )) {
        continue;
      }
      if (!_isLikelyMalaysianLand(latitude, longitude)) continue;
      gridCellCount++;
      if (_boundaryContaining(latitude, longitude, landBoundaries) != null) {
        landValidGridCellCount++;
      }

      final coverage = stationIndex.coverageAt(
        latitude,
        longitude,
        nearbyRadiusKm: parameters.nearbyRadiusKm,
      );
      final nearbyStationCount = coverage.nearbyStationCount;
      final nearestStationKm = coverage.nearestStationKm;

      if (nearbyStationCount > 1) {
        rejectedByNearbyLocationCount++;
        rejectedByCoverageCount++;
        continue;
      }
      if (nearestStationKm < parameters.minimumNearestStationKm) {
        rejectedByMinimumDistanceCount++;
        rejectedByCoverageCount++;
        continue;
      }

      final landValidation = _validateLandCandidate(
        latitude,
        longitude,
        landBoundaries,
        gridSpacingDegrees: gridSpacing,
      );
      if (!landValidation.isValid) {
        rejectedOffshoreCount++;
        landDiagnostics.add(
          landValidation.toDiagnostic(latitude, longitude, 'rejected-offshore'),
        );
        continue;
      }
      landValidatedCount++;

      if (landValidation.wasMoved) {
        correctedOffshoreCount++;
        landDiagnostics.add(
          landValidation.toDiagnostic(latitude, longitude, 'moved-to-land'),
        );
      }

      final settlementResult = _settlementRelevantPoint(
        latitude: landValidation.latitude!,
        longitude: landValidation.longitude!,
        state: landValidation.state!,
        settlements: settlementsByState[landValidation.state!] ?? const [],
        landBoundaries: landBoundaries,
        gridSpacingDegrees: gridSpacing,
        maximumDistanceKm: parameters.maximumSettlementDistanceKm,
      );
      replacementCandidatesEvaluated += settlementResult.evaluatedAlternatives;
      if (!settlementResult.isValid) {
        rejectedTooFarFromSettlement++;
        rejectedNoSettlementRelevantPoint++;
        continue;
      }
      settlementEligibleCandidates++;
      final validatedCoverage = stationIndex.coverageAt(
        settlementResult.latitude!,
        settlementResult.longitude!,
        nearbyRadiusKm: parameters.nearbyRadiusKm,
      );
      if (validatedCoverage.nearbyStationCount > 1) {
        rejectedByNearbyLocationCount++;
        rejectedByCoverageCount++;
        continue;
      }
      if (validatedCoverage.nearestStationKm <
          parameters.minimumNearestStationKm) {
        rejectedByMinimumDistanceCount++;
        rejectedByCoverageCount++;
        continue;
      }
      if (settlementResult.wasAdjusted) replacementCandidatesAccepted++;

      final rawScore = validatedCoverage.nearestStationKm * 2.4 +
          (2 - validatedCoverage.nearbyStationCount) * 15;
      final locality = settlementResult.settlement!.asLocality;
      candidates.add(
        _GapCandidate(
          latitude: settlementResult.latitude!,
          longitude: settlementResult.longitude!,
          nearbyStationCount: validatedCoverage.nearbyStationCount,
          nearestStationKm: validatedCoverage.nearestStationKm,
          rawScore: rawScore,
          locality: locality,
          state: landValidation.state!,
          originalLatitude: latitude,
          originalLongitude: longitude,
          landValidationResult: settlementResult.wasAdjusted
              ? 'adjusted-for-settlement-relevance'
              : landValidation.wasMoved
                  ? 'moved-to-land'
                  : 'valid-land',
          nearestSettlementId: settlementResult.settlement!.id,
          nearestSettlementName: settlementResult.settlement!.name,
          nearestSettlementCategory: settlementResult.settlement!.category,
          distanceToSettlementKm: settlementResult.distanceKm!,
          settlementEligibilityValidated: true,
          settlementCoordinateAdjusted: settlementResult.wasAdjusted,
          settlementAdjustmentDistanceKm: settlementResult.adjustmentDistanceKm,
        ),
      );
    }
  }

  candidates.sort(_compareGapCandidates);
  final selected = <_GapCandidate>[];
  final retainedPerSettlement = <String, int>{};
  for (final candidate in candidates) {
    final settlementCount =
        retainedPerSettlement[candidate.nearestSettlementId] ?? 0;
    if (settlementCount >= parameters.maximumResultsPerSettlement) {
      rejectedBySeparationCount++;
      continue;
    }
    final sufficientlySeparated = selected.every(
      (existing) =>
          _distanceKm(
            candidate.latitude,
            candidate.longitude,
            existing.latitude,
            existing.longitude,
          ) >=
          parameters.candidateSeparationKm,
    );
    if (!sufficientlySeparated) {
      rejectedBySeparationCount++;
      continue;
    }
    selected.add(candidate);
    retainedPerSettlement[candidate.nearestSettlementId] = settlementCount + 1;
    if (selected.length == parameters.retainedCandidateLimit) break;
  }
  selected.sort(_compareGapCandidates);
  final normalizedScores = _normalizePriorityScores(selected);

  return <String, Object>{
    'stationRecordCount': stationCoordinates.length,
    'stationCount': stationSites.length,
    'selectedStateStationRecordCount': selectedStateStationCoordinates.length,
    'selectedStateUniqueCoordinateCount': selectedStateUniqueCoordinateCount,
    'selectedStateSiteCount50m': selectedStateSiteCount50m,
    'selectedStateSiteCount75m': selectedStateSiteCount75m,
    'selectedStateSiteCount100m': selectedStateSiteCount100m,
    'gridCellCount': gridCellCount,
    'landValidGridCellCount': landValidGridCellCount,
    'distanceCheckCount': stationIndex.distanceCheckCount,
    'candidateCount': candidates.length,
    'landValidatedCount': landValidatedCount,
    'rejectedByCoverageCount': rejectedByCoverageCount,
    'rejectedByNearbyLocationCount': rejectedByNearbyLocationCount,
    'rejectedByMinimumDistanceCount': rejectedByMinimumDistanceCount,
    'rejectedBySeparationCount': rejectedBySeparationCount,
    'rejectedTooFarFromSettlement': rejectedTooFarFromSettlement,
    'replacementCandidatesEvaluated': replacementCandidatesEvaluated,
    'replacementCandidatesAccepted': replacementCandidatesAccepted,
    'rejectedNoSettlementRelevantPoint': rejectedNoSettlementRelevantPoint,
    'retainedAfterCoverage': candidates.length,
    'retainedAfterSeparation': selected.length,
    'settlementRetainedCounts': _settlementCounts(selected),
    'settlementEligibleCandidates': settlementEligibleCandidates,
    'correctedOffshoreCount': correctedOffshoreCount,
    'rejectedOffshoreCount': rejectedOffshoreCount,
    'landDiagnostics': landDiagnostics,
    'areas': [
      for (var index = 0; index < selected.length; index++)
        selected[index].toMap(
          index,
          normalizedScores[index],
          nearbyRadiusKm: parameters.nearbyRadiusKm,
        ),
    ],
  };
}

/// Groups records that represent the same physical charging location.
///
/// Input order is stable (station ID order in [analyze]). A record joins the
/// nearest existing anchor only when it is within [radiusMetres] of that fixed
/// anchor. Keeping the anchor fixed prevents transitive chains from merging
/// two legitimately separate sites that are farther apart than the radius.
Map<String, Object> _runDistributionCoverageAnalysis({
  required List<_Coordinate> stationRecords,
  required List<_Coordinate> stationSites,
  required List<_Coordinate> selectedStateStationCoordinates,
  required int selectedStateUniqueCoordinateCount,
  required int selectedStateSiteCount50m,
  required int selectedStateSiteCount75m,
  required int selectedStateSiteCount100m,
  required List<_LandBoundary> landBoundaries,
  required _AnalysisParameters parameters,
  required Map<String, List<_Settlement>> settlementsByState,
}) {
  const latitudeOrigin = .9;
  const longitudeOrigin = 99.6;
  final denseUrban = parameters.profileId == AnalysisProfile.denseUrban.name;
  final gridSpacing = parameters.gridSpacingDegrees;
  final stationIndex = _StationSpatialIndex(stationSites);
  final analysisBounds = _boundsForLandBoundaries(landBoundaries);
  final siteCountsByCell = <String, int>{};
  for (final site in stationSites) {
    final latitudeIndex =
        ((site.latitude - latitudeOrigin) / gridSpacing).round();
    final longitudeIndex =
        ((site.longitude - longitudeOrigin) / gridSpacing).round();
    final key = '$latitudeIndex|$longitudeIndex';
    siteCountsByCell[key] = (siteCountsByCell[key] ?? 0) + 1;
  }

  final latitudeStart = math
      .max(
        0,
        ((analysisBounds.south - gridSpacing / 2 - latitudeOrigin) /
                gridSpacing)
            .floor(),
      )
      .toInt();
  final latitudeEnd = math
      .min(
        ((7.4 - latitudeOrigin) / gridSpacing).floor(),
        ((analysisBounds.north + gridSpacing / 2 - latitudeOrigin) /
                gridSpacing)
            .ceil(),
      )
      .toInt();
  final longitudeStart = math
      .max(
        0,
        ((analysisBounds.west - gridSpacing / 2 - longitudeOrigin) /
                gridSpacing)
            .floor(),
      )
      .toInt();
  final longitudeEnd = math
      .min(
        ((119.3 - longitudeOrigin) / gridSpacing).floor(),
        ((analysisBounds.east + gridSpacing / 2 - longitudeOrigin) /
                gridSpacing)
            .ceil(),
      )
      .toInt();

  final cells = <_DistributionCell>[];
  var generatedCells = 0;
  var tinyBoundaryFragments = 0;
  var rejectedOffshore = 0;
  var rejectedTooFarFromSettlement = 0;
  var replacementCandidatesEvaluated = 0;
  var replacementCandidatesAccepted = 0;
  var rejectedNoSettlementRelevantPoint = 0;
  var settlementEligibleCandidates = 0;
  var correctedOffshore = 0;
  final landDiagnostics = <Map<String, Object?>>[];
  for (var latitudeIndex = latitudeStart;
      latitudeIndex <= latitudeEnd;
      latitudeIndex++) {
    final latitude = latitudeOrigin + latitudeIndex * gridSpacing;
    for (var longitudeIndex = longitudeStart;
        longitudeIndex <= longitudeEnd;
        longitudeIndex++) {
      final longitude = longitudeOrigin + longitudeIndex * gridSpacing;
      if (!analysisBounds.includesGridCell(latitude, longitude, gridSpacing) ||
          !_isLikelyMalaysianLand(latitude, longitude)) {
        continue;
      }
      generatedCells++;
      final landSampleRatio = _landSampleRatio(
        latitude,
        longitude,
        gridSpacing,
        landBoundaries,
      );
      if (landSampleRatio < .55) {
        tinyBoundaryFragments++;
        continue;
      }
      final validation = _validateLandCandidate(
        latitude,
        longitude,
        landBoundaries,
        gridSpacingDegrees: gridSpacing,
      );
      if (!validation.isValid) {
        rejectedOffshore++;
        continue;
      }
      if (validation.wasMoved) {
        correctedOffshore++;
        landDiagnostics.add(
          validation.toDiagnostic(latitude, longitude, 'moved-to-land'),
        );
      }
      final settlementResult = _settlementRelevantPoint(
        latitude: validation.latitude!,
        longitude: validation.longitude!,
        state: validation.state!,
        settlements: settlementsByState[validation.state!] ?? const [],
        landBoundaries: landBoundaries,
        gridSpacingDegrees: gridSpacing,
        maximumDistanceKm: parameters.maximumSettlementDistanceKm,
      );
      replacementCandidatesEvaluated += settlementResult.evaluatedAlternatives;
      if (!settlementResult.isValid) {
        rejectedTooFarFromSettlement++;
        rejectedNoSettlementRelevantPoint++;
        continue;
      }
      settlementEligibleCandidates++;
      final coverage = stationIndex.coverageAt(
        settlementResult.latitude!,
        settlementResult.longitude!,
        nearbyRadiusKm: parameters.nearbyRadiusKm,
      );
      final key = '$latitudeIndex|$longitudeIndex';
      cells.add(
        _DistributionCell(
          latitudeIndex: latitudeIndex,
          longitudeIndex: longitudeIndex,
          latitude: settlementResult.latitude!,
          longitude: settlementResult.longitude!,
          originalLatitude: latitude,
          originalLongitude: longitude,
          state: validation.state!,
          landValidationResult: settlementResult.wasAdjusted
              ? 'adjusted-for-settlement-relevance'
              : validation.wasMoved
                  ? 'moved-to-land'
                  : 'valid-land',
          localSiteCount: siteCountsByCell[key] ?? 0,
          nearbySiteCount: coverage.nearbyStationCount,
          nearestSiteKm: coverage.nearestStationKm,
          settlement: settlementResult.settlement!,
          distanceToSettlementKm: settlementResult.distanceKm!,
          settlementAdjusted: settlementResult.wasAdjusted,
          settlementAdjustmentDistanceKm: settlementResult.adjustmentDistanceKm,
        ),
      );
    }
  }

  final nearbyCounts = cells.map((cell) => cell.nearbySiteCount).toList()
    ..sort();
  final medianNearbyCount = nearbyCounts.isEmpty
      ? 0.0
      : nearbyCounts.length.isOdd
          ? nearbyCounts[nearbyCounts.length ~/ 2].toDouble()
          : (nearbyCounts[nearbyCounts.length ~/ 2 - 1] +
                  nearbyCounts[nearbyCounts.length ~/ 2]) /
              2;
  final candidates = <_GapCandidate>[];
  var rejectedWellCovered = 0;
  for (final cell in cells) {
    final neighbourCounts = <int>[];
    for (var latitudeOffset = -1; latitudeOffset <= 1; latitudeOffset++) {
      for (var longitudeOffset = -1; longitudeOffset <= 1; longitudeOffset++) {
        if (latitudeOffset == 0 && longitudeOffset == 0) continue;
        neighbourCounts.add(
          siteCountsByCell['${cell.latitudeIndex + latitudeOffset}|'
                  '${cell.longitudeIndex + longitudeOffset}'] ??
              0,
        );
      }
    }
    final neighbourAverage = neighbourCounts.isEmpty
        ? 0.0
        : neighbourCounts.reduce((a, b) => a + b) / neighbourCounts.length;
    final localBaseline = math.max(1.0, neighbourAverage).toDouble();
    final localScarcity =
        (1 - cell.localSiteCount / localBaseline).clamp(0.0, 1.0).toDouble();
    final neighbourhoodBaseline = math.max(1.0, medianNearbyCount).toDouble();
    final neighbourhoodScarcity =
        (1 - cell.nearbySiteCount / neighbourhoodBaseline)
            .clamp(0.0, 1.0)
            .toDouble();
    final distanceComponent =
        (cell.nearestSiteKm / math.max(1.0, parameters.nearbyRadiusKm))
            .clamp(0.0, 1.0)
            .toDouble();
    final denseQualifies = CoverageGapAnalyzer.denseUrbanCellQualifies(
      localStationLocationCount: cell.localSiteCount,
      localScarcity: localScarcity,
      neighbourhoodScarcity: neighbourhoodScarcity,
    );
    final accessibilityQualifies = cell.nearbySiteCount <= 1 &&
        cell.nearestSiteKm >= parameters.minimumNearestStationKm;
    final urbanDensityQualifies = cell.localSiteCount <= 1 &&
        localScarcity >= .35 &&
        neighbourhoodScarcity >= .20;
    final qualifies = denseUrban
        ? denseQualifies
        : accessibilityQualifies || urbanDensityQualifies;
    if (!qualifies) {
      rejectedWellCovered++;
      continue;
    }
    if (cell.settlementAdjusted) replacementCandidatesAccepted++;
    final distributionSeverity = 100 *
        (.55 * localScarcity +
            .30 * neighbourhoodScarcity +
            .15 * distanceComponent);
    final accessibilitySeverity = (cell.nearestSiteKm * 2.4 +
            (2 - math.min(2, cell.nearbySiteCount)) * 15)
        .toDouble();
    final rawScore = denseUrban
        ? distributionSeverity
        : math.max(distributionSeverity, accessibilitySeverity).toDouble();
    candidates.add(
      _GapCandidate(
        latitude: cell.latitude,
        longitude: cell.longitude,
        nearbyStationCount: cell.nearbySiteCount,
        nearestStationKm: cell.nearestSiteKm,
        rawScore: rawScore,
        locality: cell.settlement.asLocality,
        state: cell.state,
        originalLatitude: cell.originalLatitude,
        originalLongitude: cell.originalLongitude,
        landValidationResult: cell.landValidationResult,
        localStationLocationCount: cell.localSiteCount,
        neighbouringCellAverage: neighbourAverage,
        analysisProfileId: parameters.profileId,
        nearestSettlementId: cell.settlement.id,
        nearestSettlementName: cell.settlement.name,
        nearestSettlementCategory: cell.settlement.category,
        distanceToSettlementKm: cell.distanceToSettlementKm,
        settlementEligibilityValidated: true,
        settlementCoordinateAdjusted: cell.settlementAdjusted,
        settlementAdjustmentDistanceKm: cell.settlementAdjustmentDistanceKm,
      ),
    );
  }

  candidates.sort(_compareGapCandidates);
  final selected = <_GapCandidate>[];
  var mergedWithAdjacentCandidates = 0;
  final retainedPerSettlement = <String, int>{};
  for (final candidate in candidates) {
    final settlementCount =
        retainedPerSettlement[candidate.nearestSettlementId] ?? 0;
    if (settlementCount >= parameters.maximumResultsPerSettlement) {
      mergedWithAdjacentCandidates++;
      continue;
    }
    if (selected.any(
      (existing) =>
          _distanceKm(
            candidate.latitude,
            candidate.longitude,
            existing.latitude,
            existing.longitude,
          ) <
          parameters.candidateSeparationKm,
    )) {
      mergedWithAdjacentCandidates++;
      continue;
    }
    selected.add(candidate);
    retainedPerSettlement[candidate.nearestSettlementId] = settlementCount + 1;
    if (selected.length == parameters.retainedCandidateLimit) break;
  }
  final normalizedScores = _normalizePriorityScores(selected);
  final localDistribution = _countDistribution(
    cells.map((cell) => cell.localSiteCount),
  );
  final neighbourhoodDistribution = _countDistribution(
    cells.map((cell) => cell.nearbySiteCount),
  );
  return <String, Object>{
    'stationRecordCount': stationRecords.length,
    'stationCount': stationSites.length,
    'selectedStateStationRecordCount': selectedStateStationCoordinates.length,
    'selectedStateUniqueCoordinateCount': selectedStateUniqueCoordinateCount,
    'selectedStateSiteCount50m': selectedStateSiteCount50m,
    'selectedStateSiteCount75m': selectedStateSiteCount75m,
    'selectedStateSiteCount100m': selectedStateSiteCount100m,
    'gridCellCount': generatedCells,
    'landValidGridCellCount': cells.length,
    'distanceCheckCount': stationIndex.distanceCheckCount,
    'candidateCount': candidates.length,
    'landValidatedCount': cells.length,
    'rejectedByCoverageCount': rejectedWellCovered,
    'rejectedByNearbyLocationCount': 0,
    'rejectedByMinimumDistanceCount': 0,
    'rejectedBySeparationCount': mergedWithAdjacentCandidates,
    'rejectedTooFarFromSettlement': rejectedTooFarFromSettlement,
    'replacementCandidatesEvaluated': replacementCandidatesEvaluated,
    'replacementCandidatesAccepted': replacementCandidatesAccepted,
    'rejectedNoSettlementRelevantPoint': rejectedNoSettlementRelevantPoint,
    'retainedAfterCoverage': candidates.length,
    'retainedAfterSeparation': selected.length,
    'settlementRetainedCounts': _settlementCounts(selected),
    'settlementEligibleCandidates': settlementEligibleCandidates,
    'correctedOffshoreCount': correctedOffshore,
    'rejectedOffshoreCount': rejectedOffshore,
    'cellsWithZeroSites':
        cells.where((cell) => cell.localSiteCount == 0).length,
    'cellsWithOneSite': cells.where((cell) => cell.localSiteCount == 1).length,
    'cellsWithTwoOrMoreSites':
        cells.where((cell) => cell.localSiteCount >= 2).length,
    'localSiteCountDistribution': localDistribution,
    'neighbourhoodSiteCountDistribution': neighbourhoodDistribution,
    'cellsRejectedAsWellCovered': rejectedWellCovered,
    'cellsRejectedAsTinyBoundaryFragments': tinyBoundaryFragments,
    'cellsMergedWithAdjacentCandidates': mergedWithAdjacentCandidates,
    'landDiagnostics': landDiagnostics,
    'areas': [
      for (var index = 0; index < selected.length; index++)
        selected[index].toMap(
          index,
          normalizedScores[index],
          nearbyRadiusKm: parameters.nearbyRadiusKm,
        ),
    ],
  };
}

double _landSampleRatio(
  double latitude,
  double longitude,
  double gridSpacing,
  List<_LandBoundary> boundaries,
) {
  var landSamples = 0;
  for (final latitudeFactor in const <double>[-.4, 0, .4]) {
    for (final longitudeFactor in const <double>[-.4, 0, .4]) {
      if (_boundaryContaining(
            latitude + latitudeFactor * gridSpacing,
            longitude + longitudeFactor * gridSpacing,
            boundaries,
          ) !=
          null) {
        landSamples++;
      }
    }
  }
  return landSamples / 9;
}

Map<int, int> _countDistribution(Iterable<int> counts) {
  final distribution = <int, int>{};
  for (final count in counts) {
    distribution[count] = (distribution[count] ?? 0) + 1;
  }
  return Map<int, int>.fromEntries(
    distribution.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

_SettlementRelevantPoint _settlementRelevantPoint({
  required double latitude,
  required double longitude,
  required String state,
  required List<_Settlement> settlements,
  required List<_LandBoundary> landBoundaries,
  required double gridSpacingDegrees,
  required double maximumDistanceKm,
}) {
  if (settlements.isEmpty) return const _SettlementRelevantPoint.invalid();
  final direct = _nearestSettlement(latitude, longitude, settlements);
  if (direct.distanceKm <= maximumDistanceKm) {
    return _SettlementRelevantPoint.valid(
      latitude: latitude,
      longitude: longitude,
      settlement: direct.settlement,
      distanceKm: direct.distanceKm,
      adjustmentDistanceKm: 0,
    );
  }

  final offsets = <_Coordinate>[];
  const sampleSteps = 4;
  final halfCell = gridSpacingDegrees / 2;
  for (var latitudeStep = -sampleSteps;
      latitudeStep <= sampleSteps;
      latitudeStep++) {
    for (var longitudeStep = -sampleSteps;
        longitudeStep <= sampleSteps;
        longitudeStep++) {
      if (latitudeStep == 0 && longitudeStep == 0) continue;
      offsets.add(
        _Coordinate(
          latitudeStep * halfCell / sampleSteps,
          longitudeStep * halfCell / sampleSteps,
        ),
      );
    }
  }
  offsets.sort((a, b) {
    final distanceA = a.latitude * a.latitude + a.longitude * a.longitude;
    final distanceB = b.latitude * b.latitude + b.longitude * b.longitude;
    final distanceComparison = distanceA.compareTo(distanceB);
    if (distanceComparison != 0) return distanceComparison;
    final latitudeComparison = a.latitude.compareTo(b.latitude);
    return latitudeComparison != 0
        ? latitudeComparison
        : a.longitude.compareTo(b.longitude);
  });

  var evaluated = 0;
  for (final offset in offsets) {
    evaluated++;
    final replacementLatitude = latitude + offset.latitude;
    final replacementLongitude = longitude + offset.longitude;
    final boundary = _boundaryContaining(
      replacementLatitude,
      replacementLongitude,
      landBoundaries,
    );
    if (boundary == null || boundary.state != state) continue;
    final nearest = _nearestSettlement(
      replacementLatitude,
      replacementLongitude,
      settlements,
    );
    if (nearest.distanceKm > maximumDistanceKm) continue;
    return _SettlementRelevantPoint.valid(
      latitude: replacementLatitude,
      longitude: replacementLongitude,
      settlement: nearest.settlement,
      distanceKm: nearest.distanceKm,
      adjustmentDistanceKm: _distanceKm(
        latitude,
        longitude,
        replacementLatitude,
        replacementLongitude,
      ),
      wasAdjusted: true,
      evaluatedAlternatives: evaluated,
    );
  }
  return _SettlementRelevantPoint.invalid(
    evaluatedAlternatives: evaluated,
  );
}

_NearestSettlement _nearestSettlement(
  double latitude,
  double longitude,
  List<_Settlement> settlements,
) {
  var nearest = settlements.first;
  var nearestDistance = _distanceKm(
    latitude,
    longitude,
    nearest.latitude,
    nearest.longitude,
  );
  for (final settlement in settlements.skip(1)) {
    final distance = _distanceKm(
      latitude,
      longitude,
      settlement.latitude,
      settlement.longitude,
    );
    if (distance < nearestDistance ||
        (distance == nearestDistance &&
            settlement.id.compareTo(nearest.id) < 0)) {
      nearest = settlement;
      nearestDistance = distance;
    }
  }
  return _NearestSettlement(nearest, nearestDistance);
}

Map<String, int> _settlementCounts(List<_GapCandidate> candidates) {
  final counts = <String, int>{};
  for (final candidate in candidates) {
    counts[candidate.nearestSettlementName] =
        (counts[candidate.nearestSettlementName] ?? 0) + 1;
  }
  return Map<String, int>.fromEntries(
    counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

class _SettlementRelevantPoint {
  const _SettlementRelevantPoint.valid({
    required this.latitude,
    required this.longitude,
    required this.settlement,
    required this.distanceKm,
    required this.adjustmentDistanceKm,
    this.wasAdjusted = false,
    this.evaluatedAlternatives = 0,
  }) : isValid = true;

  const _SettlementRelevantPoint.invalid({this.evaluatedAlternatives = 0})
      : latitude = null,
        longitude = null,
        settlement = null,
        distanceKm = null,
        adjustmentDistanceKm = 0,
        wasAdjusted = false,
        isValid = false;

  final double? latitude;
  final double? longitude;
  final _Settlement? settlement;
  final double? distanceKm;
  final double adjustmentDistanceKm;
  final bool wasAdjusted;
  final bool isValid;
  final int evaluatedAlternatives;
}

class _NearestSettlement {
  const _NearestSettlement(this.settlement, this.distanceKm);
  final _Settlement settlement;
  final double distanceKm;
}

class _Settlement {
  const _Settlement({
    required this.id,
    required this.name,
    required this.state,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  factory _Settlement.fromMap(Map<Object?, Object?> data) => _Settlement(
        id: data['id']! as String,
        name: data['name']! as String,
        state: data['state']! as String,
        latitude: (data['latitude']! as num).toDouble(),
        longitude: (data['longitude']! as num).toDouble(),
        category: data['category']! as String,
      );

  final String id;
  final String name;
  final String state;
  final double latitude;
  final double longitude;
  final String category;

  _Locality get asLocality => _Locality(name, state, latitude, longitude);
}

class _DistributionCell {
  const _DistributionCell({
    required this.latitudeIndex,
    required this.longitudeIndex,
    required this.latitude,
    required this.longitude,
    required this.originalLatitude,
    required this.originalLongitude,
    required this.state,
    required this.landValidationResult,
    required this.localSiteCount,
    required this.nearbySiteCount,
    required this.nearestSiteKm,
    required this.settlement,
    required this.distanceToSettlementKm,
    required this.settlementAdjusted,
    required this.settlementAdjustmentDistanceKm,
  });

  final int latitudeIndex;
  final int longitudeIndex;
  final double latitude;
  final double longitude;
  final double originalLatitude;
  final double originalLongitude;
  final String state;
  final String landValidationResult;
  final int localSiteCount;
  final int nearbySiteCount;
  final double nearestSiteKm;
  final _Settlement settlement;
  final double distanceToSettlementKm;
  final bool settlementAdjusted;
  final double settlementAdjustmentDistanceKm;
}

List<_Coordinate> _groupStationSites(
  List<_Coordinate> coordinates,
  double radiusMetres,
) {
  if (coordinates.isEmpty) return const <_Coordinate>[];
  const kilometresPerLatitudeDegree = 111.32;
  final bucketDegrees = radiusMetres / 1000 / kilometresPerLatitudeDegree;
  final buckets = <String, List<int>>{};
  final sites = <_StationSiteAccumulator>[];

  for (final coordinate in coordinates) {
    final latitudeBucket = (coordinate.latitude / bucketDegrees).floor();
    final longitudeBucket = (coordinate.longitude / bucketDegrees).floor();
    var nearestSiteIndex = -1;
    var nearestDistanceMetres = double.infinity;

    for (var latitudeOffset = -1; latitudeOffset <= 1; latitudeOffset++) {
      for (var longitudeOffset = -1; longitudeOffset <= 1; longitudeOffset++) {
        final key = '${latitudeBucket + latitudeOffset}|'
            '${longitudeBucket + longitudeOffset}';
        for (final siteIndex in buckets[key] ?? const <int>[]) {
          final anchor = sites[siteIndex].anchor;
          final distanceMetres = _distanceKm(
                coordinate.latitude,
                coordinate.longitude,
                anchor.latitude,
                anchor.longitude,
              ) *
              1000;
          if (distanceMetres <= radiusMetres &&
              (distanceMetres < nearestDistanceMetres ||
                  (distanceMetres == nearestDistanceMetres &&
                      siteIndex < nearestSiteIndex))) {
            nearestSiteIndex = siteIndex;
            nearestDistanceMetres = distanceMetres;
          }
        }
      }
    }

    if (nearestSiteIndex >= 0) {
      sites[nearestSiteIndex].add(coordinate);
      continue;
    }
    final siteIndex = sites.length;
    sites.add(_StationSiteAccumulator(coordinate));
    final key = '$latitudeBucket|$longitudeBucket';
    (buckets[key] ??= <int>[]).add(siteIndex);
  }

  return sites.map((site) => site.centre).toList(growable: false);
}

class _StationSiteAccumulator {
  _StationSiteAccumulator(this.anchor)
      : _latitudeSum = anchor.latitude,
        _longitudeSum = anchor.longitude;

  final _Coordinate anchor;
  var _recordCount = 1;
  double _latitudeSum;
  double _longitudeSum;

  void add(_Coordinate coordinate) {
    _recordCount++;
    _latitudeSum += coordinate.latitude;
    _longitudeSum += coordinate.longitude;
  }

  _Coordinate get centre => _Coordinate(
        _latitudeSum / _recordCount,
        _longitudeSum / _recordCount,
      );
}

_AnalysisBounds _boundsForLandBoundaries(
  List<_LandBoundary> boundaries,
) {
  var south = double.infinity;
  var west = double.infinity;
  var north = -double.infinity;
  var east = -double.infinity;
  for (final boundary in boundaries) {
    for (final coordinate in boundary.polygons
        .expand((polygon) => polygon.expand((ring) => ring))) {
      south = math.min(south, coordinate.latitude);
      west = math.min(west, coordinate.longitude);
      north = math.max(north, coordinate.latitude);
      east = math.max(east, coordinate.longitude);
    }
  }
  return _AnalysisBounds(south, west, north, east);
}

class _AnalysisParameters {
  const _AnalysisParameters({
    required this.profileId,
    required this.gridSpacingDegrees,
    required this.nearbyRadiusKm,
    required this.minimumNearestStationKm,
    required this.candidateSeparationKm,
    required this.retainedCandidateLimit,
    required this.maximumSettlementDistanceKm,
    required this.maximumResultsPerSettlement,
  });

  factory _AnalysisParameters.fromPayload(Map<Object?, Object?> payload) =>
      _AnalysisParameters(
        profileId: payload['profileId'] as String,
        gridSpacingDegrees: (payload['gridSpacingDegrees'] as num).toDouble(),
        nearbyRadiusKm: (payload['nearbyRadiusKm'] as num).toDouble(),
        minimumNearestStationKm:
            (payload['minimumNearestStationKm'] as num).toDouble(),
        candidateSeparationKm:
            (payload['candidateSeparationKm'] as num).toDouble(),
        retainedCandidateLimit: payload['retainedCandidateLimit'] as int,
        maximumSettlementDistanceKm:
            (payload['maximumSettlementDistanceKm'] as num).toDouble(),
        maximumResultsPerSettlement:
            payload['maximumResultsPerSettlement'] as int,
      );

  final String profileId;
  final double gridSpacingDegrees;
  final double nearbyRadiusKm;
  final double minimumNearestStationKm;
  final double candidateSeparationKm;
  final int retainedCandidateLimit;
  final double maximumSettlementDistanceKm;
  final int maximumResultsPerSettlement;
}

class _AnalysisBounds {
  const _AnalysisBounds(this.south, this.west, this.north, this.east);

  final double south;
  final double west;
  final double north;
  final double east;

  bool containsPoint(double latitude, double longitude) =>
      latitude >= south &&
      latitude <= north &&
      longitude >= west &&
      longitude <= east;

  bool includesGridCell(
    double latitude,
    double longitude,
    double gridSpacingDegrees,
  ) {
    final margin = gridSpacingDegrees / 2;
    return latitude >= south - margin &&
        latitude <= north + margin &&
        longitude >= west - margin &&
        longitude <= east + margin;
  }
}

int _compareGapCandidates(_GapCandidate a, _GapCandidate b) {
  final scoreComparison = b.rawScore.compareTo(a.rawScore);
  if (scoreComparison != 0) return scoreComparison;
  final latitudeComparison = a.latitude.compareTo(b.latitude);
  if (latitudeComparison != 0) return latitudeComparison;
  return a.longitude.compareTo(b.longitude);
}

List<double> _normalizePriorityScores(List<_GapCandidate> selected) {
  if (selected.isEmpty) return const [];
  if (selected.length == 1) return const [100];

  final maximumRawScore = selected.first.rawScore;
  final minimumRawScore = selected.last.rawScore;
  final rawRange = maximumRawScore - minimumRawScore;
  final scores = <double>[];
  var previousScore = 101;

  for (var index = 0; index < selected.length; index++) {
    final rankRatio = 1 - index / (selected.length - 1);
    final magnitudeRatio = rawRange == 0
        ? rankRatio
        : (selected[index].rawScore - minimumRawScore) / rawRange;
    var score = (60 + 40 * (magnitudeRatio * .75 + rankRatio * .25)).round();
    if (score >= previousScore) score = previousScore - 1;
    score = score.clamp(60, 100).toInt();
    scores.add(score.toDouble());
    previousScore = score;
  }
  return scores;
}

bool _isLikelyMalaysianLand(double latitude, double longitude) {
  return _pointInPolygon(latitude, longitude, _peninsularMalaysia) ||
      _pointInPolygon(latitude, longitude, _sarawak) ||
      _pointInPolygon(latitude, longitude, _sabah);
}

bool _pointInPolygon(
  double latitude,
  double longitude,
  List<_Coordinate> polygon,
) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final current = polygon[i];
    final previous = polygon[j];
    if (_coordinateOnSegment(
      latitude,
      longitude,
      previous,
      current,
    )) {
      return true;
    }
    final crossesLatitude =
        (current.latitude > latitude) != (previous.latitude > latitude);
    if (!crossesLatitude) continue;
    final longitudeAtLatitude = (previous.longitude - current.longitude) *
            (latitude - current.latitude) /
            (previous.latitude - current.latitude) +
        current.longitude;
    if (longitude < longitudeAtLatitude) inside = !inside;
  }
  return inside;
}

bool _coordinateOnSegment(
  double latitude,
  double longitude,
  _Coordinate start,
  _Coordinate end,
) {
  const epsilon = 1e-10;
  final cross =
      (longitude - start.longitude) * (end.latitude - start.latitude) -
          (latitude - start.latitude) * (end.longitude - start.longitude);
  if (cross.abs() > epsilon) return false;
  return longitude >= math.min(start.longitude, end.longitude) - epsilon &&
      longitude <= math.max(start.longitude, end.longitude) + epsilon &&
      latitude >= math.min(start.latitude, end.latitude) - epsilon &&
      latitude <= math.max(start.latitude, end.latitude) + epsilon;
}

_LandValidation _validateLandCandidate(
  double latitude,
  double longitude,
  List<_LandBoundary> boundaries, {
  required double gridSpacingDegrees,
}) {
  final directBoundary = _boundaryContaining(
    latitude,
    longitude,
    boundaries,
  );
  if (directBoundary != null) {
    return _LandValidation.valid(
      latitude: latitude,
      longitude: longitude,
      state: directBoundary.state,
    );
  }

  final searchOffsets = <_Coordinate>[];
  const searchSteps = 6;
  final halfCell = gridSpacingDegrees / 2;
  for (var latitudeStep = -searchSteps;
      latitudeStep <= searchSteps;
      latitudeStep++) {
    for (var longitudeStep = -searchSteps;
        longitudeStep <= searchSteps;
        longitudeStep++) {
      if (latitudeStep == 0 && longitudeStep == 0) continue;
      searchOffsets.add(
        _Coordinate(
          latitudeStep * halfCell / searchSteps,
          longitudeStep * halfCell / searchSteps,
        ),
      );
    }
  }
  searchOffsets.sort((a, b) {
    final distanceA = a.latitude * a.latitude + a.longitude * a.longitude;
    final distanceB = b.latitude * b.latitude + b.longitude * b.longitude;
    final distanceComparison = distanceA.compareTo(distanceB);
    if (distanceComparison != 0) return distanceComparison;
    final latitudeComparison = a.latitude.compareTo(b.latitude);
    if (latitudeComparison != 0) return latitudeComparison;
    return a.longitude.compareTo(b.longitude);
  });

  for (final offset in searchOffsets) {
    final correctedLatitude = latitude + offset.latitude;
    final correctedLongitude = longitude + offset.longitude;
    final boundary = _boundaryContaining(
      correctedLatitude,
      correctedLongitude,
      boundaries,
    );
    if (boundary == null) continue;
    return _LandValidation.valid(
      latitude: correctedLatitude,
      longitude: correctedLongitude,
      state: boundary.state,
      wasMoved: true,
    );
  }
  return const _LandValidation.invalid();
}

_LandBoundary? _boundaryContaining(
  double latitude,
  double longitude,
  List<_LandBoundary> boundaries,
) {
  for (final boundary in boundaries) {
    if (boundary.contains(latitude, longitude)) return boundary;
  }
  return null;
}

class _LandValidation {
  const _LandValidation.valid({
    required this.latitude,
    required this.longitude,
    required this.state,
    this.wasMoved = false,
  }) : isValid = true;

  const _LandValidation.invalid()
      : latitude = null,
        longitude = null,
        state = null,
        wasMoved = false,
        isValid = false;

  final double? latitude;
  final double? longitude;
  final String? state;
  final bool wasMoved;
  final bool isValid;

  Map<String, Object?> toDiagnostic(
    double originalLatitude,
    double originalLongitude,
    String result,
  ) =>
      <String, Object?>{
        'originalLatitude': originalLatitude.toStringAsFixed(5),
        'originalLongitude': originalLongitude.toStringAsFixed(5),
        'result': result,
        'correctedLatitude': latitude?.toStringAsFixed(5),
        'correctedLongitude': longitude?.toStringAsFixed(5),
        'state': state,
      };
}

class _LandBoundary {
  const _LandBoundary({
    required this.state,
    required this.polygons,
    required this.polygonBounds,
  });

  factory _LandBoundary.fromFeature(Map<Object?, Object?> feature) {
    final properties = feature['properties'] as Map<Object?, Object?>;
    final geometry = feature['geometry'] as Map<Object?, Object?>;
    final geometryType = geometry['type'] as String;
    final rawCoordinates = geometry['coordinates'] as List<Object?>;
    final rawPolygons =
        geometryType == 'Polygon' ? <Object?>[rawCoordinates] : rawCoordinates;
    final polygons = rawPolygons.map((rawPolygon) {
      return (rawPolygon as List<Object?>).map((rawRing) {
        return (rawRing as List<Object?>).map((rawCoordinate) {
          final values = rawCoordinate as List<Object?>;
          return _Coordinate(
            (values[1] as num).toDouble(),
            (values[0] as num).toDouble(),
          );
        }).toList(growable: false);
      }).toList(growable: false);
    }).toList(growable: false);
    return _LandBoundary(
      state: _normalizeStateName(properties['NAME_1'] as String),
      polygons: polygons,
      polygonBounds:
          polygons.map(_coordinateBoundsForPolygon).toList(growable: false),
    );
  }

  final String state;
  final List<List<List<_Coordinate>>> polygons;
  final List<_AnalysisBounds> polygonBounds;

  bool contains(double latitude, double longitude) {
    for (var index = 0; index < polygons.length; index++) {
      final polygon = polygons[index];
      if (!polygonBounds[index].containsPoint(latitude, longitude)) continue;
      if (polygon.isEmpty ||
          !_pointInPolygon(latitude, longitude, polygon.first)) {
        continue;
      }
      final insideHole = polygon.skip(1).any(
            (hole) => _pointInPolygon(latitude, longitude, hole),
          );
      if (!insideHole) return true;
    }
    return false;
  }
}

_AnalysisBounds _coordinateBoundsForPolygon(
  List<List<_Coordinate>> polygon,
) {
  var south = double.infinity;
  var west = double.infinity;
  var north = -double.infinity;
  var east = -double.infinity;
  for (final coordinate in polygon.expand((ring) => ring)) {
    south = math.min(south, coordinate.latitude);
    west = math.min(west, coordinate.longitude);
    north = math.max(north, coordinate.latitude);
    east = math.max(east, coordinate.longitude);
  }
  return _AnalysisBounds(south, west, north, east);
}

String _normalizeStateName(String state) => switch (state) {
      'Pulau Pinang' => 'Penang',
      'Malacca' => 'Melaka',
      _ => state,
    };

double _distanceKm(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta = _radians(latitudeB - latitudeA);
  final longitudeDelta = _radians(longitudeB - longitudeA);
  final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(_radians(latitudeA)) *
          math.cos(_radians(latitudeB)) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180;

class _Coordinate {
  const _Coordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class _StationCoverage {
  const _StationCoverage({
    required this.nearbyStationCount,
    required this.nearestStationKm,
  });

  final int nearbyStationCount;
  final double nearestStationKm;
}

class _StationSpatialIndex {
  _StationSpatialIndex(List<_Coordinate> stations) {
    for (final station in stations) {
      final latitudeBucket = _bucketIndex(station.latitude);
      final longitudeBucket = _bucketIndex(station.longitude);
      _buckets
          .putIfAbsent(
            _bucketKey(latitudeBucket, longitudeBucket),
            () => <_Coordinate>[],
          )
          .add(station);
    }
  }

  static const double _bucketSizeDegrees = .25;
  static const double _conservativeKmPerDegree = 100;
  static const int _maximumSearchRing = 100;

  final Map<int, List<_Coordinate>> _buckets = {};
  int distanceCheckCount = 0;

  _StationCoverage coverageAt(
    double latitude,
    double longitude, {
    required double nearbyRadiusKm,
  }) {
    final latitudeBucket = _bucketIndex(latitude);
    final longitudeBucket = _bucketIndex(longitude);
    var nearestStationKm = double.infinity;
    var nearbyStationCount = 0;

    for (var ring = 0; ring <= _maximumSearchRing; ring++) {
      for (var latitudeOffset = -ring;
          latitudeOffset <= ring;
          latitudeOffset++) {
        for (var longitudeOffset = -ring;
            longitudeOffset <= ring;
            longitudeOffset++) {
          if (ring > 0 &&
              latitudeOffset.abs() != ring &&
              longitudeOffset.abs() != ring) {
            continue;
          }
          final bucket = _buckets[_bucketKey(
            latitudeBucket + latitudeOffset,
            longitudeBucket + longitudeOffset,
          )];
          if (bucket == null) continue;
          for (final station in bucket) {
            distanceCheckCount++;
            final distance = _distanceKm(
              latitude,
              longitude,
              station.latitude,
              station.longitude,
            );
            if (distance < nearestStationKm) nearestStationKm = distance;
            if (distance <= nearbyRadiusKm) {
              nearbyStationCount++;
            }
          }
        }
      }

      final minimumOutsideDistanceKm = _minimumDistanceOutsideSearchSquare(
        latitude,
        longitude,
        latitudeBucket,
        longitudeBucket,
        ring,
      );
      final requiredSearchDistance = math.max(
        nearbyRadiusKm,
        nearestStationKm,
      );
      if (nearestStationKm.isFinite &&
          minimumOutsideDistanceKm >= requiredSearchDistance) {
        break;
      }
    }

    return _StationCoverage(
      nearbyStationCount: nearbyStationCount,
      nearestStationKm: nearestStationKm,
    );
  }

  double _minimumDistanceOutsideSearchSquare(
    double latitude,
    double longitude,
    int latitudeBucket,
    int longitudeBucket,
    int ring,
  ) {
    final minimumLatitude = (latitudeBucket - ring) * _bucketSizeDegrees;
    final maximumLatitude = (latitudeBucket + ring + 1) * _bucketSizeDegrees;
    final minimumLongitude = (longitudeBucket - ring) * _bucketSizeDegrees;
    final maximumLongitude = (longitudeBucket + ring + 1) * _bucketSizeDegrees;
    final latitudeDistance = math.min(
      latitude - minimumLatitude,
      maximumLatitude - latitude,
    );
    final longitudeDistance = math.min(
      longitude - minimumLongitude,
      maximumLongitude - longitude,
    );
    return math.min(latitudeDistance, longitudeDistance) *
        _conservativeKmPerDegree;
  }

  static int _bucketIndex(double coordinate) =>
      (coordinate / _bucketSizeDegrees).floor();

  static int _bucketKey(int latitudeBucket, int longitudeBucket) =>
      (latitudeBucket << 16) ^ longitudeBucket;
}

class _GapCandidate {
  const _GapCandidate({
    required this.latitude,
    required this.longitude,
    required this.nearbyStationCount,
    required this.nearestStationKm,
    required this.rawScore,
    required this.locality,
    required this.state,
    required this.originalLatitude,
    required this.originalLongitude,
    required this.landValidationResult,
    this.localStationLocationCount = 0,
    this.neighbouringCellAverage = 0,
    this.analysisProfileId = 'regional',
    required this.nearestSettlementId,
    required this.nearestSettlementName,
    required this.nearestSettlementCategory,
    required this.distanceToSettlementKm,
    required this.settlementEligibilityValidated,
    required this.settlementCoordinateAdjusted,
    required this.settlementAdjustmentDistanceKm,
  });

  final double latitude;
  final double longitude;
  final int nearbyStationCount;
  final double nearestStationKm;
  final double rawScore;
  final _Locality locality;
  final String state;
  final double originalLatitude;
  final double originalLongitude;
  final String landValidationResult;
  final int localStationLocationCount;
  final double neighbouringCellAverage;
  final String analysisProfileId;
  final String nearestSettlementId;
  final String nearestSettlementName;
  final String nearestSettlementCategory;
  final double distanceToSettlementKm;
  final bool settlementEligibilityValidated;
  final bool settlementCoordinateAdjusted;
  final double settlementAdjustmentDistanceKm;

  Map<String, Object> toMap(
    int rank,
    double priorityScore, {
    required double nearbyRadiusKm,
  }) {
    final latitudeKey = (latitude * 1000).round();
    final longitudeKey = (longitude * 1000).round();
    final localityDistance = _distanceKm(
      locality.latitude,
      locality.longitude,
      latitude,
      longitude,
    );
    final displayName = localityDistance <= 20
        ? 'Coverage gap near ${locality.displayName}'
        : '${_directionFromLocality(locality, latitude, longitude)} '
            'of ${locality.displayName}';
    final distributionBased =
        analysisProfileId == AnalysisProfile.denseUrban.name ||
            analysisProfileId == AnalysisProfile.urban.name;
    final settlementContext =
        ' It is ${distanceToSettlementKm.toStringAsFixed(1)} km from '
        '$nearestSettlementName, within the configured '
        '$analysisProfileId planning area.';
    final explanation = distributionBased
        ? 'This neighbourhood cell contains $localStationLocationCount '
            'charging location${localStationLocationCount == 1 ? '' : 's'} '
            'and has lower infrastructure coverage than nearby cells. '
            'The nearest charging location is '
            '${nearestStationKm.toStringAsFixed(1)} km away.'
            '$settlementContext'
        : 'Only $nearbyStationCount charging station location'
            '${nearbyStationCount == 1 ? '' : 's'} within '
            '${nearbyRadiusKm.toStringAsFixed(1)} km; nearest station '
            'location is ${nearestStationKm.toStringAsFixed(1)} km away.'
            '$settlementContext';
    return <String, Object>{
      'id': 'gap_${latitudeKey}_$longitudeKey',
      'originalLatitude': originalLatitude.toStringAsFixed(5),
      'originalLongitude': originalLongitude.toStringAsFixed(5),
      'landValidationResult': landValidationResult,
      'name': displayName,
      'state': state,
      'priority': _priorityLevel(priorityScore),
      'latitude': latitude,
      'longitude': longitude,
      'nearbyStationCount': nearbyStationCount,
      'localStationLocationCount': localStationLocationCount,
      'neighbouringCellAverage': neighbouringCellAverage,
      'analysisProfileId': analysisProfileId,
      'nearestSettlementId': nearestSettlementId,
      'nearestSettlementName': nearestSettlementName,
      'nearestSettlementCategory': nearestSettlementCategory,
      'distanceToSettlementKm': distanceToSettlementKm,
      'settlementEligibilityValidated': settlementEligibilityValidated,
      'settlementCoordinateAdjusted': settlementCoordinateAdjusted,
      'settlementAdjustmentDistanceKm': settlementAdjustmentDistanceKm,
      'originalAnalyticalLatitude': originalLatitude,
      'originalAnalyticalLongitude': originalLongitude,
      'roadAccessibilityValidated': false,
      'coordinateAdjusted': false,
      'adjustmentDistanceMeters': 0.0,
      'suitabilityNote':
          'Within the configured $analysisProfileId settlement planning area; '
              'road-access validation remains unavailable.',
      'nearestStationKm': nearestStationKm,
      'score': priorityScore,
      'coverageScore': rawScore,
      'nearbyRadiusKm': nearbyRadiusKm,
      'reason': explanation,
      'rank': rank + 1,
    };
  }
}

String _priorityLevel(double priorityScore) {
  if (priorityScore >= 85) return 'High';
  if (priorityScore >= 70) return 'Medium';
  return 'Low';
}

String _directionFromLocality(
  _Locality locality,
  double latitude,
  double longitude,
) {
  final latitudeDelta = latitude - locality.latitude;
  final longitudeDelta = longitude - locality.longitude;
  final angle = math.atan2(longitudeDelta, latitudeDelta);
  final normalizedDegrees = (angle * 180 / math.pi + 360) % 360;
  const directions = <String>[
    'North',
    'Northeast',
    'East',
    'Southeast',
    'South',
    'Southwest',
    'West',
    'Northwest',
  ];
  final index = ((normalizedDegrees + 22.5) ~/ 45) % directions.length;
  return directions[index];
}

class _Locality {
  const _Locality(
    this.name,
    this.state,
    this.latitude,
    this.longitude,
  );

  final String name;
  final String state;
  final double latitude;
  final double longitude;

  String get displayName => name == state ? name : '$name, $state';
}

const _peninsularMalaysia = <_Coordinate>[
  _Coordinate(1.15, 103.50),
  _Coordinate(1.35, 104.05),
  _Coordinate(2.80, 103.85),
  _Coordinate(4.70, 103.55),
  _Coordinate(6.45, 102.20),
  _Coordinate(6.70, 100.15),
  _Coordinate(5.20, 100.15),
  _Coordinate(3.05, 100.95),
];

const _sarawak = <_Coordinate>[
  _Coordinate(0.85, 109.60),
  _Coordinate(1.10, 110.80),
  _Coordinate(1.55, 111.60),
  _Coordinate(2.00, 112.70),
  _Coordinate(2.30, 114.10),
  _Coordinate(3.15, 115.45),
  _Coordinate(4.65, 115.00),
  _Coordinate(4.20, 113.00),
  _Coordinate(3.40, 111.20),
  _Coordinate(2.00, 109.55),
];

const _sabah = <_Coordinate>[
  _Coordinate(4.00, 115.00),
  _Coordinate(4.10, 117.55),
  _Coordinate(5.10, 119.30),
  _Coordinate(6.10, 118.45),
  _Coordinate(7.30, 117.00),
  _Coordinate(6.60, 115.50),
  _Coordinate(5.20, 115.00),
];
