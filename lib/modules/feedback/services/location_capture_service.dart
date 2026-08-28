import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

import '../../planning/models/proposal.dart';

/// Thrown when GPS auto-capture can't produce a position — the caller
/// should fall back to manual location entry (search / map pin) rather
/// than block the report form.
class LocationCaptureException implements Exception {
  LocationCaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Wraps `Geolocator` for the "GPS Auto Capture" requirement (see
/// MODULE3_USER_IMPLEMENTATION_PLAN.md §3) — nothing else in the app talks
/// to device location directly; the rest of the codebase (proposal
/// locations) is tap-to-pin only.
class LocationCaptureService {
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationCaptureException(
        'Location services are turned off on this device.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationCaptureException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationCaptureException(
        'Location permission is permanently denied. Enable it in system '
        'settings to auto-detect your location.',
      );
    }

    // `best`/`high` accuracy waits for a real GPS fix, which can take a
    // long time — or never resolve at all — indoors or on an emulator
    // without a mock location set. `medium` accuracy (network/coarse) is
    // plenty precise for identifying which charging station a report is
    // about, and a hard time limit means this always gives up rather than
    // hanging the "Detecting your location…" state indefinitely.
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _platformLocationSettings(),
      );
    } on TimeoutException {
      // Fall back to the OS's cached last-known fix (returns immediately)
      // rather than surface a raw timeout to the driver.
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      throw LocationCaptureException(
        'Getting your location is taking too long.',
      );
    }
  }

  LocationSettings _platformLocationSettings() {
    const accuracy = LocationAccuracy.medium;
    const timeLimit = Duration(seconds: 10);
    // On Android, Play Services' fused location client can, on some
    // device/OS combinations, get stuck resolving a "location settings
    // need to be improved" dialog rather than returning or timing out —
    // a known source of ANRs for this plugin. `forceLocationManager`
    // bypasses Play Services and uses the plain Android LocationManager
    // API instead, which is slightly less precise but far more
    // predictable — and the fallback above only needs a coarse fix anyway.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
        forceLocationManager: true,
      );
    }
    return const LocationSettings(accuracy: accuracy, timeLimit: timeLimit);
  }

  /// The nearest [ChargingStation] to (`latitude`, `longitude`) if one is
  /// within [maxDistanceMeters], else `null` — lets a GPS-captured point
  /// resolve to a real, named station (matching the "Shell Recharge, IOI
  /// City Mall"-style mockup) rather than only a generic address label.
  ChargingStation? nearestStation(
    double latitude,
    double longitude,
    List<ChargingStation> stations, {
    double maxDistanceMeters = 300,
  }) {
    ChargingStation? nearest;
    var nearestDistance = double.infinity;
    for (final station in stations) {
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        station.latitude,
        station.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }
    return nearestDistance <= maxDistanceMeters ? nearest : null;
  }
}