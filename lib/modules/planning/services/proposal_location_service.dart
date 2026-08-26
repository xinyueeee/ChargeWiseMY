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
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String state;
  final String category;
  final double latitude;
  final double longitude;

  String get label => '$name, $state';

  String get contextLabel {
    final type = switch (category) {
      'majorCity' => 'Major city',
      'city' => 'City',
      'districtCentre' => 'District centre',
      'town' => 'Town',
      _ => 'Malaysian place',
    };
    return '$state · $type';
  }
}

class ProposalLocationService {
  ProposalLocationService({StateBoundaryService? stateBoundaries})
      : _stateBoundaries = stateBoundaries ?? StateBoundaryService();

  final StateBoundaryService _stateBoundaries;
  List<_Settlement> _settlements = const [];
  List<_SettlementSearchEntry> _searchIndex = const [];
  Future<void>? _loading;

  static const Map<String, String> _searchAliases = {
    'kl': 'kuala lumpur',
    'k l': 'kuala lumpur',
    'wilayah persekutuan kuala lumpur': 'kuala lumpur',
  };

  static const Set<String> _optionalPlacePrefixes = {
    'bandar',
    'kampung',
    'kg',
    'pekan',
    'taman',
  };

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
    _searchIndex = List<_SettlementSearchEntry>.unmodifiable(
      _settlements.map(_SettlementSearchEntry.new),
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
    final normalized = _normalizeSearchText(query);
    if (normalized.length < 2) return const [];

    final variants = <_SearchVariant>[
      _SearchVariant(normalized, penalty: 0),
    ];
    final alias = _searchAliases[normalized];
    if (alias != null && alias != normalized) {
      variants.add(_SearchVariant(alias, penalty: 50));
    }
    final words = normalized.split(' ');
    if (words.length > 1 && _optionalPlacePrefixes.contains(words.first)) {
      final broader = words.skip(1).join(' ');
      if (broader.length >= 2 && broader != alias) {
        variants.add(_SearchVariant(broader, penalty: 40));
      }
    }

    final matches = <_RankedSettlement>[];
    for (final entry in _searchIndex) {
      _RankedSettlement? best;
      for (final variant in variants) {
        final rank = entry.rankFor(variant.query);
        if (rank == null) continue;
        final candidate = _RankedSettlement(
          entry.settlement,
          rank: rank + variant.penalty,
        );
        if (best == null || candidate.rank < best.rank) best = candidate;
      }
      if (best != null) matches.add(best);
    }
    matches.sort((a, b) {
      final rankComparison = a.rank.compareTo(b.rank);
      if (rankComparison != 0) return rankComparison;
      final stateComparison = a.settlement.state.compareTo(b.settlement.state);
      return stateComparison != 0
          ? stateComparison
          : a.settlement.name.compareTo(b.settlement.name);
    });

    return List<ProposalLocationSuggestion>.unmodifiable(
      matches.take(limit).map(
            (match) => ProposalLocationSuggestion(
              name: match.settlement.name,
              state: match.settlement.state,
              category: match.settlement.category,
              latitude: match.settlement.latitude,
              longitude: match.settlement.longitude,
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
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String state;
  final String category;
  final double latitude;
  final double longitude;

  static _Settlement? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final state = json['state'] as String?;
    final category = json['category'] as String? ?? '';
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
      category: category,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class _SettlementSearchEntry {
  _SettlementSearchEntry(this.settlement)
      : normalizedName = _normalizeSearchText(settlement.name),
        normalizedState = _normalizeSearchText(settlement.state),
        normalizedCategory = _normalizeSearchText(settlement.category);

  final _Settlement settlement;
  final String normalizedName;
  final String normalizedState;
  final String normalizedCategory;

  int? rankFor(String query) {
    if (normalizedName == query) return 0;
    if (normalizedName.startsWith(query)) return 10;

    final queryWords = query.split(' ').where((word) => word.isNotEmpty);
    final searchable = '$normalizedName $normalizedState $normalizedCategory';
    if (queryWords.every(searchable.contains)) return 20;
    if (normalizedName.contains(query)) return 30;
    if (searchable.contains(query)) return 40;
    return null;
  }
}

class _SearchVariant {
  const _SearchVariant(this.query, {required this.penalty});

  final String query;
  final int penalty;
}

class _RankedSettlement {
  const _RankedSettlement(this.settlement, {required this.rank});

  final _Settlement settlement;
  final int rank;
}

String _normalizeSearchText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
