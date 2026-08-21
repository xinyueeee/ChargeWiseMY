import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

const malaysiaSelection = 'Malaysia';
const malaysiaStateBoundaryDatasetVersion =
    'geoboundaries-gbopen-mys-adm1-15666254-simplified-v1';

class GeoCoordinate {
  const GeoCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  GeoCoordinate get centre => GeoCoordinate(
        (south + north) / 2,
        (west + east) / 2,
      );

  @override
  bool operator ==(Object other) =>
      other is GeoBounds &&
      south == other.south &&
      west == other.west &&
      north == other.north &&
      east == other.east;

  @override
  int get hashCode => Object.hash(south, west, north, east);
}

class StateRegion {
  const StateRegion({
    required this.name,
    required this.polygons,
    required this.polygonBounds,
    required this.displayPolygons,
    required this.bounds,
    required this.labelPoint,
  });

  final String name;
  final List<List<List<GeoCoordinate>>> polygons;
  final List<GeoBounds> polygonBounds;
  final List<List<List<GeoCoordinate>>> displayPolygons;
  final GeoBounds bounds;
  final GeoCoordinate labelPoint;

  bool contains(double latitude, double longitude) {
    if (latitude < bounds.south ||
        latitude > bounds.north ||
        longitude < bounds.west ||
        longitude > bounds.east) {
      return false;
    }
    for (var index = 0; index < polygons.length; index++) {
      final polygon = polygons[index];
      final polygonBounds = this.polygonBounds[index];
      if (latitude < polygonBounds.south ||
          latitude > polygonBounds.north ||
          longitude < polygonBounds.west ||
          longitude > polygonBounds.east) {
        continue;
      }
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

class StateOverviewSummary {
  const StateOverviewSummary({
    required this.name,
    required this.labelPoint,
    required this.existingStationCount,
    required this.installedChargerCount,
    required this.acChargerCount,
    required this.dcChargerCount,
    required this.proposedStationCount,
    required this.priorityAreaCount,
  });

  final String name;
  final GeoCoordinate labelPoint;
  final int existingStationCount;
  final int installedChargerCount;
  final int acChargerCount;
  final int dcChargerCount;
  final int proposedStationCount;
  final int? priorityAreaCount;
}

class StateBoundaryProximity {
  const StateBoundaryProximity({
    required this.state,
    required this.distanceKm,
  });

  final String state;
  final double distanceKm;

  bool get nearBoundary => distanceKm <= 5;
}

class StateBoundaryService {
  static Future<List<StateRegion>>? _regionCache;

  List<StateRegion> _regions = const [];

  List<StateRegion> get regions => _regions;

  List<String> get stateOptions {
    final states = _regions.map((region) => region.name).toList()..sort();
    return List<String>.unmodifiable([malaysiaSelection, ...states]);
  }

  GeoBounds? get malaysiaBounds {
    if (_regions.isEmpty) return null;
    return _combinedBounds(_regions.map((region) => region.bounds));
  }

  StateRegion? regionFor(String state) {
    if (state == malaysiaSelection) return null;
    for (final region in _regions) {
      if (region.name == state) return region;
    }
    return null;
  }

  String? stateFor(double latitude, double longitude) {
    for (final region in _regions) {
      if (region.contains(latitude, longitude)) return region.name;
    }
    return null;
  }

  StateBoundaryProximity? nearestStateBoundary(
    double latitude,
    double longitude,
  ) {
    StateBoundaryProximity? nearest;
    for (final region in _regions) {
      for (final ring in region.polygons.expand((polygon) => polygon)) {
        if (ring.length < 2) continue;
        for (var index = 0; index < ring.length; index++) {
          final start = ring[index];
          final end = ring[(index + 1) % ring.length];
          final distance = _pointToSegmentKm(
            latitude,
            longitude,
            start,
            end,
          );
          if (nearest == null || distance < nearest.distanceKm) {
            nearest = StateBoundaryProximity(
              state: region.name,
              distanceKm: distance,
            );
          }
        }
      }
    }
    return nearest;
  }

  Future<List<StateRegion>> load() async {
    _regions = await (_regionCache ??= _loadRegions());
    return _regions;
  }

  static Future<List<StateRegion>> _loadRegions() async {
    final sources = await Future.wait([
      rootBundle.loadString('assets/data/malaysia_states.geojson'),
      rootBundle.loadString('assets/data/malaysia_states_display.geojson'),
    ]);
    final collection = jsonDecode(sources[0]) as Map<String, Object?>;
    final displayCollection = jsonDecode(sources[1]) as Map<String, Object?>;
    final detailedRegions = (collection['features'] as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map(_parseRegion)
        .toList(growable: false);
    final displayByState = <String, List<List<List<GeoCoordinate>>>>{
      for (final region in (displayCollection['features'] as List<Object?>)
          .cast<Map<Object?, Object?>>()
          .map(_parseRegion))
        region.name: region.polygons,
    };
    final regions = detailedRegions
        .map(
          (region) => StateRegion(
            name: region.name,
            polygons: region.polygons,
            polygonBounds: region.polygonBounds,
            displayPolygons:
                displayByState[region.name] ?? region.polygons,
            bounds: region.bounds,
            labelPoint: region.labelPoint,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    return List<StateRegion>.unmodifiable(regions);
  }

  static StateRegion _parseRegion(Map<Object?, Object?> feature) {
    final properties = feature['properties'] as Map<Object?, Object?>;
    final geometry = feature['geometry'] as Map<Object?, Object?>;
    final geometryType = geometry['type'] as String;
    final rawCoordinates = geometry['coordinates'] as List<Object?>;
    final rawPolygons = geometryType == 'Polygon'
        ? <Object?>[rawCoordinates]
        : rawCoordinates;
    final polygons = rawPolygons.map((rawPolygon) {
      return (rawPolygon as List<Object?>).map((rawRing) {
        return (rawRing as List<Object?>).map((rawCoordinate) {
          final values = rawCoordinate as List<Object?>;
          return GeoCoordinate(
            (values[1] as num).toDouble(),
            (values[0] as num).toDouble(),
          );
        }).toList(growable: false);
      }).toList(growable: false);
    }).toList(growable: false);
    final points = polygons.expand((polygon) => polygon.expand((ring) => ring));
    final name = _normalizeStateName(properties['NAME_1'] as String);
    final bounds = _boundsFor(points);
    final polygonBounds = polygons
        .map(
          (polygon) => _boundsFor(
            polygon.expand((ring) => ring),
          ),
        )
        .toList(growable: false);
    return StateRegion(
      name: name,
      polygons: polygons,
      polygonBounds: polygonBounds,
      displayPolygons: polygons,
      bounds: bounds,
      labelPoint: _labelPointFor(name, polygons, bounds),
    );
  }
}

double _pointToSegmentKm(
  double latitude,
  double longitude,
  GeoCoordinate start,
  GeoCoordinate end,
) {
  final longitudeScale = math.cos(latitude * math.pi / 180) * 111.32;
  const latitudeScale = 110.57;
  final pointX = longitude * longitudeScale;
  final pointY = latitude * latitudeScale;
  final startX = start.longitude * longitudeScale;
  final startY = start.latitude * latitudeScale;
  final endX = end.longitude * longitudeScale;
  final endY = end.latitude * latitudeScale;
  final deltaX = endX - startX;
  final deltaY = endY - startY;
  final segmentLengthSquared = deltaX * deltaX + deltaY * deltaY;
  final projection = segmentLengthSquared == 0
      ? 0.0
      : (((pointX - startX) * deltaX + (pointY - startY) * deltaY) /
              segmentLengthSquared)
          .clamp(0.0, 1.0)
          .toDouble();
  final nearestX = startX + projection * deltaX;
  final nearestY = startY + projection * deltaY;
  return math.sqrt(
    math.pow(pointX - nearestX, 2) + math.pow(pointY - nearestY, 2),
  );
}

const _labelPointOverrides = <String, GeoCoordinate>{
  'Kuala Lumpur': GeoCoordinate(3.1390, 101.6869),
  'Putrajaya': GeoCoordinate(2.9264, 101.6964),
  'Penang': GeoCoordinate(5.4141, 100.3288),
  'Labuan': GeoCoordinate(5.2831, 115.2308),
};

GeoCoordinate _labelPointFor(
  String state,
  List<List<List<GeoCoordinate>>> polygons,
  GeoBounds bounds,
) {
  final override = _labelPointOverrides[state];
  if (override != null &&
      _containsPolygons(polygons, override.latitude, override.longitude)) {
    return override;
  }

  final polygonCandidates = <({double area, GeoCoordinate point})>[];
  for (final polygon in polygons) {
    if (polygon.isEmpty) continue;
    final centroid = _polygonCentroid(polygon.first);
    polygonCandidates.add((
      area: _signedPolygonArea(polygon.first).abs(),
      point: centroid,
    ));
  }
  polygonCandidates.sort((a, b) => b.area.compareTo(a.area));
  for (final candidate in polygonCandidates) {
    if (_containsPolygons(
      polygons,
      candidate.point.latitude,
      candidate.point.longitude,
    )) {
      return candidate.point;
    }
  }

  GeoCoordinate? bestInteriorPoint;
  var bestClearance = -1.0;
  const sampleSteps = 32;
  final boundaryPoints = polygons
      .expand((polygon) => polygon.expand((ring) => ring))
      .toList(growable: false);
  for (var latitudeStep = 1; latitudeStep < sampleSteps; latitudeStep++) {
    final latitude = bounds.south +
        (bounds.north - bounds.south) * latitudeStep / sampleSteps;
    for (var longitudeStep = 1;
        longitudeStep < sampleSteps;
        longitudeStep++) {
      final longitude = bounds.west +
          (bounds.east - bounds.west) * longitudeStep / sampleSteps;
      if (!_containsPolygons(polygons, latitude, longitude)) continue;
      var nearestVertexDistance = double.infinity;
      for (final point in boundaryPoints) {
        final latitudeDelta = latitude - point.latitude;
        final longitudeDelta = longitude - point.longitude;
        final distance = latitudeDelta * latitudeDelta +
            longitudeDelta * longitudeDelta;
        if (distance < nearestVertexDistance) {
          nearestVertexDistance = distance;
        }
      }
      if (nearestVertexDistance > bestClearance) {
        bestClearance = nearestVertexDistance;
        bestInteriorPoint = GeoCoordinate(latitude, longitude);
      }
    }
  }
  if (bestInteriorPoint != null) return bestInteriorPoint;

  for (final polygon in polygons) {
    if (polygon.isEmpty || polygon.first.isEmpty) continue;
    final first = polygon.first.first;
    final nudged = GeoCoordinate(
      first.latitude + (bounds.centre.latitude - first.latitude) * .01,
      first.longitude + (bounds.centre.longitude - first.longitude) * .01,
    );
    if (_containsPolygons(polygons, nudged.latitude, nudged.longitude)) {
      return nudged;
    }
  }
  return bounds.centre;
}

double _signedPolygonArea(List<GeoCoordinate> ring) {
  var twiceArea = 0.0;
  for (var index = 0; index < ring.length; index++) {
    final current = ring[index];
    final next = ring[(index + 1) % ring.length];
    twiceArea += current.longitude * next.latitude -
        next.longitude * current.latitude;
  }
  return twiceArea / 2;
}

GeoCoordinate _polygonCentroid(List<GeoCoordinate> ring) {
  var latitudeSum = 0.0;
  var longitudeSum = 0.0;
  var crossSum = 0.0;
  for (var index = 0; index < ring.length; index++) {
    final current = ring[index];
    final next = ring[(index + 1) % ring.length];
    final cross = current.longitude * next.latitude -
        next.longitude * current.latitude;
    longitudeSum += (current.longitude + next.longitude) * cross;
    latitudeSum += (current.latitude + next.latitude) * cross;
    crossSum += cross;
  }
  if (crossSum.abs() < 1e-12) {
    final latitude =
        ring.fold<double>(0, (sum, point) => sum + point.latitude) /
            ring.length;
    final longitude =
        ring.fold<double>(0, (sum, point) => sum + point.longitude) /
            ring.length;
    return GeoCoordinate(latitude, longitude);
  }
  return GeoCoordinate(
    latitudeSum / (3 * crossSum),
    longitudeSum / (3 * crossSum),
  );
}

bool _containsPolygons(
  List<List<List<GeoCoordinate>>> polygons,
  double latitude,
  double longitude,
) {
  for (final polygon in polygons) {
    if (polygon.isEmpty ||
        !_pointInPolygon(latitude, longitude, polygon.first)) {
      continue;
    }
    if (!polygon.skip(1).any(
          (hole) => _pointInPolygon(latitude, longitude, hole),
        )) {
      return true;
    }
  }
  return false;
}

GeoBounds _boundsFor(Iterable<GeoCoordinate> points) {
  var south = double.infinity;
  var west = double.infinity;
  var north = -double.infinity;
  var east = -double.infinity;
  for (final point in points) {
    if (point.latitude < south) south = point.latitude;
    if (point.longitude < west) west = point.longitude;
    if (point.latitude > north) north = point.latitude;
    if (point.longitude > east) east = point.longitude;
  }
  return GeoBounds(south: south, west: west, north: north, east: east);
}

GeoBounds _combinedBounds(Iterable<GeoBounds> bounds) {
  var south = double.infinity;
  var west = double.infinity;
  var north = -double.infinity;
  var east = -double.infinity;
  for (final item in bounds) {
    if (item.south < south) south = item.south;
    if (item.west < west) west = item.west;
    if (item.north > north) north = item.north;
    if (item.east > east) east = item.east;
  }
  return GeoBounds(south: south, west: west, north: north, east: east);
}

bool _pointInPolygon(
  double latitude,
  double longitude,
  List<GeoCoordinate> polygon,
) {
  var inside = false;
  for (var currentIndex = 0, previousIndex = polygon.length - 1;
      currentIndex < polygon.length;
      previousIndex = currentIndex++) {
    final current = polygon[currentIndex];
    final previous = polygon[previousIndex];
    if (_pointOnSegment(
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
    final longitudeAtLatitude =
        (previous.longitude - current.longitude) *
                (latitude - current.latitude) /
                (previous.latitude - current.latitude) +
            current.longitude;
    if (longitude < longitudeAtLatitude) inside = !inside;
  }
  return inside;
}

bool _pointOnSegment(
  double latitude,
  double longitude,
  GeoCoordinate start,
  GeoCoordinate end,
) {
  const epsilon = 1e-10;
  final cross = (longitude - start.longitude) *
          (end.latitude - start.latitude) -
      (latitude - start.latitude) * (end.longitude - start.longitude);
  if (cross.abs() > epsilon) return false;
  return longitude >= math.min(start.longitude, end.longitude) - epsilon &&
      longitude <= math.max(start.longitude, end.longitude) + epsilon &&
      latitude >= math.min(start.latitude, end.latitude) - epsilon &&
      latitude <= math.max(start.latitude, end.latitude) + epsilon;
}

String _normalizeStateName(String state) => switch (state) {
      'Pulau Pinang' => 'Penang',
      'Malacca' => 'Melaka',
      _ => state,
    };
