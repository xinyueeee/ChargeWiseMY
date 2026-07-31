import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../../services/supabase_service.dart';
import '../models/proposal.dart';
import 'coverage_gap_analyzer.dart';
import 'state_boundary_service.dart';

class PlanningRepository {
  PlanningRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();
  final SupabaseService _supabase;
  final CoverageGapAnalyzer _gapAnalyzer = const CoverageGapAnalyzer();
  final Map<String, Future<List<GapArea>>> _gapCache = {};
  int _analyzerExecutionCount = 0;

  Future<List<Proposal>> getProposals(
    List<ChargingStation> stations,
  ) async {
    await _supabase.ensureMockUser();
    final rows = await _supabase.getProposalsWithReactions();
    return rows.map((row) {
      final reactions = List<Map<String, dynamic>>.from(
          row['proposal_reactions'] as List? ?? []);
      final likes =
          reactions.where((item) => item['reaction'] == 'like').length;
      final myReactions = reactions
          .where((item) => item['user_id'] == SupabaseService.mockUserId)
          .toList();
      final mine = myReactions.isEmpty ? null : myReactions.first;
      final reaction = mine == null
          ? 0
          : mine['reaction'] == 'like'
              ? 1
              : -1;
      return Proposal.fromSupabase(
        row,
        nearestStationKm: _nearestStationKm(row, stations),
        supportCount: likes,
        reaction: reaction,
      );
    }).toList();
  }

  Future<List<GapArea>> getGaps(
    List<ChargingStation> stations, {
    String selectedState = malaysiaSelection,
  }) {
    final sortedStations = List<ChargingStation>.of(stations)
      ..sort(_compareStations);
    final cacheKey = '$selectedState|${_stationFingerprint(sortedStations)}';
    final cached = _gapCache[cacheKey];
    if (cached != null) {
      debugPrint(
        'Coverage-gap cache hit: state=$selectedState, '
        'stationCount=${sortedStations.length}, '
        'analyzerExecutionCount=$_analyzerExecutionCount.',
      );
      return cached;
    }

    _analyzerExecutionCount++;
    debugPrint(
      'Coverage-gap cache miss: state=$selectedState, '
      'stationCount=${sortedStations.length}, '
      'analyzerExecutionCount=$_analyzerExecutionCount.',
    );
    final analysis = _gapAnalyzer
        .analyze(sortedStations, selectedState: selectedState)
        .then((areas) => List<GapArea>.unmodifiable(areas));
    _gapCache[cacheKey] = analysis;
    return analysis;
  }

  int _compareStations(ChargingStation a, ChargingStation b) {
    final idComparison = a.id.compareTo(b.id);
    if (idComparison != 0) return idComparison;
    final latitudeComparison = a.latitude.compareTo(b.latitude);
    if (latitudeComparison != 0) return latitudeComparison;
    return a.longitude.compareTo(b.longitude);
  }

  String _stationFingerprint(List<ChargingStation> stations) => stations
      .map(
        (station) =>
            '${station.id}|${station.latitude.toStringAsFixed(7)}|'
            '${station.longitude.toStringAsFixed(7)}',
      )
      .join(';');

  Future<List<ChargingStation>> getStations() async {
    final fetchStopwatch = Stopwatch()..start();
    final rows = await _supabase.getChargingStations();
    fetchStopwatch.stop();
    final parsingStopwatch = Stopwatch()..start();
    final stations = <ChargingStation>[];
    var invalidCoordinates = 0;
    for (final row in rows) {
      final station = ChargingStation.fromSupabase(row);
      if (station == null) {
        invalidCoordinates++;
      } else {
        stations.add(station);
      }
    }
    parsingStopwatch.stop();
    debugPrint(
      'Station loading diagnostics: fetch=${fetchStopwatch.elapsedMilliseconds}ms, '
      'parsing=${parsingStopwatch.elapsedMilliseconds}ms, '
      'rows=${rows.length}, valid=${stations.length}, '
      'invalid=$invalidCoordinates.',
    );
    return stations;
  }

  Future<int> getStationCount() async {
    return _supabase.getChargingStationCount();
  }

  Future<void> submitProposal(Proposal proposal) async {
    await _supabase.ensureMockUser();
    await _supabase.client.from('proposals').insert({
      'user_id': SupabaseService.mockUserId,
      'title': proposal.city,
      'description': proposal.description,
      'address': proposal.city,
      'latitude': proposal.latitude,
      'longitude': proposal.longitude,
      'charger_type': proposal.charger,
      'expected_demand': proposal.demand == 'High'
          ? 3
          : proposal.demand == 'Low'
              ? 1
              : 2,
      'status': 'pending',
    });
  }

  Future<void> updateProposal(Proposal proposal) async {
    await _supabase.updateProposal(proposal.id, {
      'title': proposal.city,
      'description': proposal.description,
      'address': proposal.city,
      'latitude': proposal.latitude,
      'longitude': proposal.longitude,
      'charger_type': proposal.charger,
      'expected_demand': proposal.demand == 'High'
          ? 3
          : proposal.demand == 'Low'
              ? 1
              : 2,
    });
  }

  Future<void> deleteProposal(String proposalId) =>
      _supabase.deleteProposal(proposalId);

  Future<void> reactToProposal(Proposal proposal, bool like) =>
      _supabase.addReaction(
        proposalId: proposal.id,
        reaction: like ? 'like' : 'dislike',
      );

  Future<void> updateStatus(String id, String status) =>
      _supabase.updateProposalStatus(id, status);

  double _nearestStationKm(
    Map<String, dynamic> proposal,
    List<ChargingStation> stations,
  ) {
    if (stations.isEmpty) return 0;
    final lat = (proposal['latitude'] as num?)?.toDouble();
    final lng = (proposal['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return 0;
    return stations.map((station) {
      final dx = (lat - station.latitude) * 111;
      final dy = (lng - station.longitude) * 111;
      return math.sqrt(dx * dx + dy * dy);
    }).reduce((a, b) => a < b ? a : b);
  }
}
