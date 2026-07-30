import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/proposal.dart';

class CoverageGapAnalyzer {
  const CoverageGapAnalyzer();

  static const double gridSpacingDegrees = 0.18;
  static const double nearbyRadiusKm = 25;
  static const double minimumNearestStationKm = 15;
  static const double minimumSeparationKm = 35;
  static const int maximumResults = 20;

  Future<List<GapArea>> analyze(List<ChargingStation> stations) async {
    final sortedStations = List<ChargingStation>.of(stations)
      ..sort((a, b) {
        final idComparison = a.id.compareTo(b.id);
        if (idComparison != 0) return idComparison;
        final latitudeComparison = a.latitude.compareTo(b.latitude);
        if (latitudeComparison != 0) return latitudeComparison;
        return a.longitude.compareTo(b.longitude);
      });
    final stopwatch = Stopwatch()..start();
    final result = await compute(
      _runCoverageGapAnalysis,
      <String, Object>{
        'stations': [
          for (final station in sortedStations)
            <Object>[station.id, station.latitude, station.longitude],
        ],
      },
    );
    stopwatch.stop();

    final areas = (result['areas'] as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map(GapArea.fromAnalysis)
        .toList(growable: false);

    debugPrint(
      'Coverage-gap diagnostics: '
      '${result['stationCount']} station coordinates analyzed; '
      '${result['gridCellCount']} grid cells evaluated; '
      '${result['candidateCount']} candidate gap areas found; '
      '${areas.length} final non-overlapping priority areas returned; '
      '${stopwatch.elapsedMilliseconds}ms analysis duration.',
    );
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
}

Map<String, Object> _runCoverageGapAnalysis(Map<String, Object> payload) {
  final stationCoordinates = (payload['stations'] as List<Object?>)
      .cast<List<Object?>>()
      .map(
        (coordinate) => _Coordinate(
          (coordinate[1] as num).toDouble(),
          (coordinate[2] as num).toDouble(),
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

  if (stationCoordinates.isEmpty) {
    return <String, Object>{
      'stationCount': 0,
      'gridCellCount': 0,
      'candidateCount': 0,
      'areas': <Map<String, Object>>[],
    };
  }

  final candidates = <_GapCandidate>[];
  var gridCellCount = 0;

  for (var latitudeIndex = 0;; latitudeIndex++) {
    final latitude =
        0.9 + latitudeIndex * CoverageGapAnalyzer.gridSpacingDegrees;
    if (latitude > 7.4) break;
    for (var longitudeIndex = 0;; longitudeIndex++) {
      final longitude =
          99.6 + longitudeIndex * CoverageGapAnalyzer.gridSpacingDegrees;
      if (longitude > 119.3) break;
      if (!_isLikelyMalaysianLand(latitude, longitude)) continue;
      gridCellCount++;

      var nearbyStationCount = 0;
      var nearestStationKm = double.infinity;
      for (final station in stationCoordinates) {
        final distance = _distanceKm(
          latitude,
          longitude,
          station.latitude,
          station.longitude,
        );
        if (distance < nearestStationKm) nearestStationKm = distance;
        if (distance <= CoverageGapAnalyzer.nearbyRadiusKm) {
          nearbyStationCount++;
        }
      }

      if (nearbyStationCount > 1 ||
          nearestStationKm <
              CoverageGapAnalyzer.minimumNearestStationKm) {
        continue;
      }

      final rawScore =
          nearestStationKm * 2.4 + (2 - nearbyStationCount) * 15;
      final locality = _nearestLocality(latitude, longitude);
      candidates.add(
        _GapCandidate(
          latitude: latitude,
          longitude: longitude,
          nearbyStationCount: nearbyStationCount,
          nearestStationKm: nearestStationKm,
          rawScore: rawScore,
          locality: locality,
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
          CoverageGapAnalyzer.minimumSeparationKm,
    );
    if (!sufficientlySeparated) continue;
    selected.add(candidate);
    if (selected.length == CoverageGapAnalyzer.maximumResults) break;
  }
  selected.sort(_compareGapCandidates);
  final normalizedScores = _normalizePriorityScores(selected);

  return <String, Object>{
    'stationCount': stationCoordinates.length,
    'gridCellCount': gridCellCount,
    'candidateCount': candidates.length,
    'areas': [
      for (var index = 0; index < selected.length; index++)
        selected[index].toMap(index, normalizedScores[index]),
    ],
  };
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

_Locality _nearestLocality(double latitude, double longitude) {
  var nearest = _localities.first;
  var nearestDistance = double.infinity;
  for (final locality in _localities) {
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

class _GapCandidate {
  const _GapCandidate({
    required this.latitude,
    required this.longitude,
    required this.nearbyStationCount,
    required this.nearestStationKm,
    required this.rawScore,
    required this.locality,
  });

  final double latitude;
  final double longitude;
  final int nearbyStationCount;
  final double nearestStationKm;
  final double rawScore;
  final _Locality locality;

  Map<String, Object> toMap(int rank, double priorityScore) {
    final latitudeKey = (latitude * 1000).round();
    final longitudeKey = (longitude * 1000).round();
    final localityDistance = _distanceKm(
      locality.latitude,
      locality.longitude,
      latitude,
      longitude,
    );
    final displayName = localityDistance <= 20
        ? 'Coverage gap near ${locality.name}'
        : '${_directionFromLocality(locality, latitude, longitude)} '
            'of ${locality.name}';
    return <String, Object>{
      'id': 'gap_${latitudeKey}_$longitudeKey',
      'name': displayName,
      'priority': 'High',
      'latitude': latitude,
      'longitude': longitude,
      'nearbyStationCount': nearbyStationCount,
      'nearestStationKm': nearestStationKm,
      'score': priorityScore,
      'reason':
          'Only $nearbyStationCount charging station${nearbyStationCount == 1 ? '' : 's'} '
              'within ${CoverageGapAnalyzer.nearbyRadiusKm.round()} km; '
              'nearest station is ${nearestStationKm.toStringAsFixed(1)} km away.',
      'rank': rank + 1,
    };
  }
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
  const _Locality(this.name, this.latitude, this.longitude);

  final String name;
  final double latitude;
  final double longitude;
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
  _Locality('Kangar, Perlis', 6.44, 100.20),
  _Locality('Alor Setar, Kedah', 6.12, 100.37),
  _Locality('George Town, Penang', 5.41, 100.33),
  _Locality('Ipoh, Perak', 4.60, 101.09),
  _Locality('Kota Bharu, Kelantan', 6.13, 102.24),
  _Locality('Kuala Terengganu, Terengganu', 5.33, 103.14),
  _Locality('Kuantan, Pahang', 3.81, 103.33),
  _Locality('Shah Alam, Selangor', 3.07, 101.52),
  _Locality('Kuala Lumpur', 3.14, 101.69),
  _Locality('Seremban, Negeri Sembilan', 2.73, 101.94),
  _Locality('Melaka City, Melaka', 2.19, 102.25),
  _Locality('Johor Bahru, Johor', 1.49, 103.74),
  _Locality('Kuching, Sarawak', 1.55, 110.36),
  _Locality('Sibu, Sarawak', 2.29, 111.83),
  _Locality('Bintulu, Sarawak', 3.17, 113.04),
  _Locality('Miri, Sarawak', 4.40, 113.99),
  _Locality('Kota Kinabalu, Sabah', 5.98, 116.07),
  _Locality('Sandakan, Sabah', 5.84, 118.12),
  _Locality('Lahad Datu, Sabah', 5.03, 118.33),
  _Locality('Tawau, Sabah', 4.25, 117.89),
];
