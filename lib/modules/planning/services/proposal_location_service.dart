import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../models/proposal.dart';
import 'state_boundary_service.dart';

class ProposalLocationSelection {
  const ProposalLocationSelection({
    required this.latitude,
    required this.longitude,
    required this.state,
    required this.nearestTown,
    required this.locationLabel,
  });

  final double latitude;
  final double longitude;
  final String state;
  final String nearestTown;
  final String locationLabel;
}

class ProposalLocationSuggestion {
  const ProposalLocationSuggestion({
    required this.name,
    required this.state,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String state;
  final double latitude;
  final double longitude;

  String get label => '$name, $state';
}

class ProposalLocationService {
  ProposalLocationService({StateBoundaryService? stateBoundaries})
      : _stateBoundaries = stateBoundaries ?? StateBoundaryService();

  final StateBoundaryService _stateBoundaries;
  List<_Settlement> _settlements = const [];
  Future<void>? _loading;

  StateBoundaryService get stateBoundaries => _stateBoundaries;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    await _stateBoundaries.load();
    final source = await rootBundle.loadString(
      'assets/data/malaysia_settlements.json',
    );
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    _settlements = List<_Settlement>.unmodifiable(
      (decoded['settlements'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_Settlement.fromJson)
          .whereType<_Settlement>(),
    );
  }

  Future<ProposalLocationSelection?> resolve(
    double latitude,
    double longitude,
  ) async {
    await load();
    final state = _stateBoundaries.stateFor(latitude, longitude);
    if (state == null) return null;

    final stateSettlements = _settlements
        .where((settlement) => settlement.state == state)
        .toList(growable: false);
    final candidates =
        stateSettlements.isEmpty ? _settlements : stateSettlements;
    _Settlement? nearest;
    var nearestDistance = double.infinity;
    for (final settlement in candidates) {
      final distance = _distanceKm(
        latitude,
        longitude,
        settlement.latitude,
        settlement.longitude,
      );
      if (distance < nearestDistance ||
          (distance == nearestDistance &&
              settlement.name.compareTo(nearest?.name ?? '') < 0)) {
        nearest = settlement;
        nearestDistance = distance;
      }
    }

    final town = nearest?.name ?? 'Selected location';
    return ProposalLocationSelection(
      latitude: latitude,
      longitude: longitude,
      state: state,
      nearestTown: town,
      locationLabel:
          nearest == null ? 'Selected location, $state' : '$town, $state',
    );
  }

  Future<List<ProposalLocationSuggestion>> search(
    String query, {
    int limit = 8,
  }) async {
    await load();
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return const [];
    final matches = _settlements.where((settlement) {
      final name = settlement.name.toLowerCase();
      final state = settlement.state.toLowerCase();
      return name.contains(normalized) || state.contains(normalized);
    }).toList()
      ..sort((a, b) {
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();
        final aRank = aName == normalized
            ? 0
            : aName.startsWith(normalized)
                ? 1
                : 2;
        final bRank = bName == normalized
            ? 0
            : bName.startsWith(normalized)
                ? 1
                : 2;
        final rankComparison = aRank.compareTo(bRank);
        if (rankComparison != 0) return rankComparison;
        final stateComparison = a.state.compareTo(b.state);
        return stateComparison != 0
            ? stateComparison
            : a.name.compareTo(b.name);
      });
    return List<ProposalLocationSuggestion>.unmodifiable(
      matches.take(limit).map(
            (settlement) => ProposalLocationSuggestion(
              name: settlement.name,
              state: settlement.state,
              latitude: settlement.latitude,
              longitude: settlement.longitude,
            ),
          ),
    );
  }

  Future<Proposal> enrich(Proposal proposal) async {
    final latitude = proposal.latitude;
    final longitude = proposal.longitude;
    if (latitude == null || longitude == null) return proposal;
    final selection = await resolve(latitude, longitude);
    if (selection == null) return proposal;
    return proposal.copyWithLocation(
      locationLabel: selection.locationLabel,
      state: selection.state,
      nearestTown: selection.nearestTown,
    );
  }

  bool isDuplicate(
    ProposalLocationSelection selection,
    String proposalName,
    Iterable<Proposal> proposals, {
    String? excludedProposalId,
  }) {
    final normalizedName = proposalName.trim().toLowerCase();
    for (final proposal in proposals) {
      if (proposal.id == excludedProposalId) continue;
      final latitude = proposal.latitude;
      final longitude = proposal.longitude;
      if (latitude == null || longitude == null) continue;
      final sameName = proposal.city.trim().toLowerCase() == normalizedName;
      final sameLocation = _distanceKm(
            selection.latitude,
            selection.longitude,
            latitude,
            longitude,
          ) <=
          .025;
      if (sameName && sameLocation) return true;
    }
    return false;
  }

  double _distanceKm(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusKm = 6371.0088;
    final latitudeDelta = _radians(latitudeB - latitudeA);
    final longitudeDelta = _radians(longitudeB - longitudeA);
    final a = math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(latitudeA)) *
            math.cos(_radians(latitudeB)) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}

class _Settlement {
  const _Settlement({
    required this.name,
    required this.state,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String state;
  final double latitude;
  final double longitude;

  static _Settlement? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final state = json['state'] as String?;
    final latitude = CoordinateParser.latitude(json['latitude']);
    final longitude = CoordinateParser.longitude(json['longitude']);
    if (name == null ||
        state == null ||
        latitude == null ||
        longitude == null) {
      return null;
    }
    return _Settlement(
      name: name,
      state: state,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
