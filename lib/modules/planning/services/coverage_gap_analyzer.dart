import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/proposal.dart';
import 'analysis_profile.dart';
import 'state_boundary_service.dart';

class CoverageGapAnalyzer {
  const CoverageGapAnalyzer();

  static const double stationSiteDeduplicationRadiusMetres = 75;
  static const int stationSiteDeduplicationVersion = 1;
  static const String stationSiteDeduplicationCacheToken =
      'site-dedup-v1-radius75m';

  static Future<List<Map<String, Object?>>>? _landBoundariesCache;

  static const double gridSpacingDegrees = 0.18;
  static const double nearbyRadiusKm = 25;
  static const double minimumNearestStationKm = 15;
  static const double minimumSeparationKm = 35;
  static const int maximumResults = 20;

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
    final result = await compute(
      _runCoverageGapAnalysis,
      <String, Object>{
        'stations': [
          for (final station in sortedStations)
            <double>[station.latitude, station.longitude],
        ],
        'landBoundaries': landBoundaries,
        'selectedState': selectedState,
        'analysisParameters': resolvedProfile.toPayload(),
      },
    );
    stopwatch.stop();

    final areaMaps = (result['areas'] as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final areas = areaMaps.map(GapArea.fromAnalysis).toList(growable: false);
    final bruteForceDistanceChecks =
        (result['stationCount'] as int) * (result['gridCellCount'] as int);
    final indexedDistanceChecks = result['distanceCheckCount'] as int;
    final checkReductionPercent = bruteForceDistanceChecks == 0
        ? 0.0
        : (1 - indexedDistanceChecks / bruteForceDistanceChecks) * 100;

    debugPrint(
      'Analysis profile: state=$selectedState, '
      'profile=${resolvedProfile.definition.displayName}, '
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
    for (final diagnostic
        in (result['landDiagnostics'] as List<Object?>)
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
              (other) =>
                  other.latitude != null && other.longitude != null,
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
}

Map<String, Object> _runCoverageGapAnalysis(Map<String, Object> payload) {
  final selectedState = payload['selectedState'] as String;
  final parameters = _AnalysisParameters.fromPayload(
    payload['analysisParameters'] as Map<Object?, Object?>,
  );
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
      'selectedStateStationRecordCount':
          selectedStateStationCoordinates.length,
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
  final landDiagnostics = <Map<String, Object?>>[];

  const latitudeOrigin = .9;
  const longitudeOrigin = 99.6;
  final gridSpacing = parameters.gridSpacingDegrees;
  final latitudeStart = math.max(
    0,
    ((analysisBounds.south - gridSpacing / 2 - latitudeOrigin) /
            gridSpacing)
        .floor(),
  ).toInt();
  final latitudeEnd = math.min(
    ((7.4 - latitudeOrigin) / gridSpacing).floor(),
    ((analysisBounds.north + gridSpacing / 2 - latitudeOrigin) /
            gridSpacing)
        .ceil(),
  ).toInt();
  final longitudeStart = math.max(
    0,
    ((analysisBounds.west - gridSpacing / 2 - longitudeOrigin) /
            gridSpacing)
        .floor(),
  ).toInt();
  final longitudeEnd = math.min(
    ((119.3 - longitudeOrigin) / gridSpacing).floor(),
    ((analysisBounds.east + gridSpacing / 2 - longitudeOrigin) /
            gridSpacing)
        .ceil(),
  ).toInt();

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

      final validatedCoverage = landValidation.wasMoved
          ? stationIndex.coverageAt(
              landValidation.latitude!,
              landValidation.longitude!,
              nearbyRadiusKm: parameters.nearbyRadiusKm,
            )
          : coverage;
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

      final rawScore =
          validatedCoverage.nearestStationKm * 2.4 +
              (2 - validatedCoverage.nearbyStationCount) * 15;
      final locality = _nearestLocality(
        landValidation.latitude!,
        landValidation.longitude!,
        state: landValidation.state!,
      );
      candidates.add(
        _GapCandidate(
          latitude: landValidation.latitude!,
          longitude: landValidation.longitude!,
          nearbyStationCount: validatedCoverage.nearbyStationCount,
          nearestStationKm: validatedCoverage.nearestStationKm,
          rawScore: rawScore,
          locality: locality,
          state: landValidation.state!,
          originalLatitude: latitude,
          originalLongitude: longitude,
          landValidationResult:
              landValidation.wasMoved ? 'moved-to-land' : 'valid-land',
        ),
      );
    }
  }

  candidates.sort(_compareGapCandidates);
  final selected = <_GapCandidate>[];
  for (final candidate in candidates) {
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
      for (var longitudeOffset = -1;
          longitudeOffset <= 1;
          longitudeOffset++) {
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
    required this.gridSpacingDegrees,
    required this.nearbyRadiusKm,
    required this.minimumNearestStationKm,
    required this.candidateSeparationKm,
    required this.retainedCandidateLimit,
  });

  factory _AnalysisParameters.fromPayload(Map<Object?, Object?> payload) =>
      _AnalysisParameters(
        gridSpacingDegrees:
            (payload['gridSpacingDegrees'] as num).toDouble(),
        nearbyRadiusKm: (payload['nearbyRadiusKm'] as num).toDouble(),
        minimumNearestStationKm:
            (payload['minimumNearestStationKm'] as num).toDouble(),
        candidateSeparationKm:
            (payload['candidateSeparationKm'] as num).toDouble(),
        retainedCandidateLimit: payload['retainedCandidateLimit'] as int,
      );

  final double gridSpacingDegrees;
  final double nearbyRadiusKm;
  final double minimumNearestStationKm;
  final double candidateSeparationKm;
  final int retainedCandidateLimit;
}

class _AnalysisBounds {
  const _AnalysisBounds(this.south, this.west, this.north, this.east);

  final double south;
  final double west;
  final double north;
  final double east;

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
    var score =
        (60 + 40 * (magnitudeRatio * .75 + rankRatio * .25)).round();
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
    final distanceA =
        a.latitude * a.latitude + a.longitude * a.longitude;
    final distanceB =
        b.latitude * b.latitude + b.longitude * b.longitude;
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
  const _LandBoundary({required this.state, required this.polygons});

  factory _LandBoundary.fromFeature(Map<Object?, Object?> feature) {
    final properties = feature['properties'] as Map<Object?, Object?>;
    final geometry = feature['geometry'] as Map<Object?, Object?>;
    final geometryType = geometry['type'] as String;
    final rawCoordinates = geometry['coordinates'] as List<Object?>;
    final rawPolygons = geometryType == 'Polygon'
        ? <Object?>[rawCoordinates]
        : rawCoordinates;
    return _LandBoundary(
      state: _normalizeStateName(properties['NAME_1'] as String),
      polygons: rawPolygons.map((rawPolygon) {
        return (rawPolygon as List<Object?>).map((rawRing) {
          return (rawRing as List<Object?>).map((rawCoordinate) {
            final values = rawCoordinate as List<Object?>;
            return _Coordinate(
              (values[1] as num).toDouble(),
              (values[0] as num).toDouble(),
            );
          }).toList(growable: false);
        }).toList(growable: false);
      }).toList(growable: false),
    );
  }

  final String state;
  final List<List<List<_Coordinate>>> polygons;

  bool contains(double latitude, double longitude) {
    for (final polygon in polygons) {
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

String _normalizeStateName(String state) =>
    state == 'Pulau Pinang' ? 'Penang' : state;

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

_Locality _nearestLocality(
  double latitude,
  double longitude, {
  required String state,
}) {
  final stateLocalities =
      _localities.where((locality) => locality.state == state).toList();
  final candidates = stateLocalities.isEmpty ? _localities : stateLocalities;
  var nearest = candidates.first;
  var nearestDistance = double.infinity;
  for (final locality in candidates) {
    final distance = _distanceKm(
      latitude,
      longitude,
      locality.latitude,
      locality.longitude,
    );
    if (distance < nearestDistance) {
      nearest = locality;
      nearestDistance = distance;
    }
  }
  return nearest;
}

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
          final bucket = _buckets[
              _bucketKey(
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
    final minimumLatitude =
        (latitudeBucket - ring) * _bucketSizeDegrees;
    final maximumLatitude =
        (latitudeBucket + ring + 1) * _bucketSizeDegrees;
    final minimumLongitude =
        (longitudeBucket - ring) * _bucketSizeDegrees;
    final maximumLongitude =
        (longitudeBucket + ring + 1) * _bucketSizeDegrees;
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
      'nearestStationKm': nearestStationKm,
      'score': priorityScore,
      'coverageScore': rawScore,
      'nearbyRadiusKm': nearbyRadiusKm,
      'reason':
          'Only $nearbyStationCount charging station location${nearbyStationCount == 1 ? '' : 's'} '
              'within ${nearbyRadiusKm.toStringAsFixed(1)} km; '
              'nearest station location is '
              '${nearestStationKm.toStringAsFixed(1)} km away.',
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

const _localities = <_Locality>[
  _Locality('Kangar', 'Perlis', 6.44, 100.20),
  _Locality('Alor Setar', 'Kedah', 6.12, 100.37),
  _Locality('George Town', 'Penang', 5.41, 100.33),
  _Locality('Ipoh', 'Perak', 4.60, 101.09),
  _Locality('Kota Bharu', 'Kelantan', 6.13, 102.24),
  _Locality('Kuala Terengganu', 'Terengganu', 5.33, 103.14),
  _Locality('Kuantan', 'Pahang', 3.81, 103.33),
  _Locality('Shah Alam', 'Selangor', 3.07, 101.52),
  _Locality('Kuala Lumpur', 'Kuala Lumpur', 3.14, 101.69),
  _Locality('Putrajaya', 'Putrajaya', 2.93, 101.70),
  _Locality('Seremban', 'Negeri Sembilan', 2.73, 101.94),
  _Locality('Melaka City', 'Melaka', 2.19, 102.25),
  _Locality('Johor Bahru', 'Johor', 1.49, 103.74),
  _Locality('Kuching', 'Sarawak', 1.55, 110.36),
  _Locality('Sibu', 'Sarawak', 2.29, 111.83),
  _Locality('Bintulu', 'Sarawak', 3.17, 113.04),
  _Locality('Miri', 'Sarawak', 4.40, 113.99),
  _Locality('Labuan', 'Labuan', 5.28, 115.23),
  _Locality('Kota Kinabalu', 'Sabah', 5.98, 116.07),
  _Locality('Sandakan', 'Sabah', 5.84, 118.12),
  _Locality('Lahad Datu', 'Sabah', 5.03, 118.33),
  _Locality('Tawau', 'Sabah', 4.25, 117.89),
];
