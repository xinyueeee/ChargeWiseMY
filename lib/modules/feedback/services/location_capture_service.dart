import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

import '../../planning/models/proposal.dart';

class LocationCaptureException implements Exception {
  LocationCaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _platformLocationSettings(),
      );
    } on TimeoutException {
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

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
        forceLocationManager: true,
      );
    }
    return const LocationSettings(accuracy: accuracy, timeLimit: timeLimit);
  }

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
