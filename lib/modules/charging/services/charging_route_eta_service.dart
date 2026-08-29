import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One candidate station to rank by real drive time - sent alongside the
/// driver's own location.
class RouteEtaCandidate {
  const RouteEtaCandidate({
    required this.id,
    required this.lat,
    required this.lng,
  });

  final String id;
  final double lat;
  final double lng;

  Map<String, Object?> toJson() => {'id': id, 'lat': lat, 'lng': lng};
}

class RouteEtaContext {
  const RouteEtaContext({
    required this.originLat,
    required this.originLng,
    required this.candidates,
  });

  final double originLat;
  final double originLng;
  final List<RouteEtaCandidate> candidates;

  Map<String, Object?> toJson() => {
        'originLat': originLat,
        'originLng': originLng,
        'candidates': candidates.map((c) => c.toJson()).toList(),
      };
}

/// Real driving distance/duration for one candidate. Either field can be
/// null when OpenRouteService couldn't route to that point (e.g. no road
/// access) - that's reported honestly rather than falling back to a made-up
/// number.
class RouteEtaResult {
  const RouteEtaResult({
    required this.id,
    required this.distanceKm,
    required this.durationMinutes,
  });

  final String id;
  final double? distanceKm;
  final double? durationMinutes;

  factory RouteEtaResult.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Invalid route ETA result.');
    }
    return RouteEtaResult(
      id: id,
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      durationMinutes: (json['durationMinutes'] as num?)?.toDouble(),
    );
  }
}

enum RouteEtaFailureReason { rateLimited, timeout, authentication, unavailable }

class RouteEtaUnavailableException implements Exception {
  const RouteEtaUnavailableException(
    this.message, {
    this.reason = RouteEtaFailureReason.unavailable,
  });

  final String message;
  final RouteEtaFailureReason reason;

  @override
  String toString() => message;
}

abstract interface class ChargingRouteEtaService {
  Future<List<RouteEtaResult>> generate(RouteEtaContext context);
}

class SupabaseChargingRouteEtaService implements ChargingRouteEtaService {
  const SupabaseChargingRouteEtaService();

  @override
  Future<List<RouteEtaResult>> generate(RouteEtaContext context) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw const RouteEtaUnavailableException(
        'Sign in is required to calculate a real ETA.',
        reason: RouteEtaFailureReason.authentication,
      );
    }
    try {
      final response = await client.functions.invoke(
        'charging-route-eta',
        body: context.toJson(),
      );
      final data = response.data;
      if (data is! Map || data['results'] is! List) {
        throw const FormatException('Unexpected route ETA response.');
      }
      return (data['results'] as List)
          .map((row) =>
              RouteEtaResult.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on FunctionException catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Route ETA function failure: status=${error.status}, '
          'details=${_safeFunctionDetails(error.details)}',
        );
      }
      final reason = switch (error.status) {
        429 => RouteEtaFailureReason.rateLimited,
        504 => RouteEtaFailureReason.timeout,
        401 || 403 => RouteEtaFailureReason.authentication,
        _ => RouteEtaFailureReason.unavailable,
      };
      throw RouteEtaUnavailableException(
        'Route ETA function failed (${error.status}).',
        reason: reason,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw RouteEtaUnavailableException('Route ETA request failed: $error');
    }
  }

  String _safeFunctionDetails(dynamic details) {
    if (details is! Map) return 'unavailable';
    final error = details['error'];
    final field = details['field'];
    return 'error=${error is String ? error : 'unknown'}, '
        'field=${field is String ? field : 'none'}';
  }
}
