import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../../services/supabase_service.dart';
import '../models/proposal.dart';
import 'coverage_gap_analyzer.dart';

class PlanningRepository {
  PlanningRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();
  final SupabaseService _supabase;
  final CoverageGapAnalyzer _gapAnalyzer = const CoverageGapAnalyzer();
  String? _gapCacheKey;
  Future<List<GapArea>>? _gapCache;
  int _analyzerExecutionCount = 0;

  Future<List<Proposal>> getProposals() async {
    await _supabase.ensureMockUser();
    final results = await Future.wait([
      _supabase.getProposalsWithReactions(),
      _supabase.getChargingStations(),
    ]);
    final rows = results[0];
    final stations = List<Map<String, dynamic>>.from(results[1]);
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

  Future<List<GapArea>> getGaps(List<ChargingStation> stations) {
    final sortedStations = List<ChargingStation>.of(stations)
      ..sort(_compareStations);
    final cacheKey = _stationFingerprint(sortedStations);
    if (_gapCacheKey == cacheKey && _gapCache != null) {
      debugPrint(
        'Coverage-gap cache hit: stationCount=${sortedStations.length}, '
        'analyzerExecutionCount=$_analyzerExecutionCount.',
      );
      return _gapCache!;
    }

    _analyzerExecutionCount++;
    debugPrint(
      'Coverage-gap cache miss: stationCount=${sortedStations.length}, '
      'analyzerExecutionCount=$_analyzerExecutionCount.',
    );
    _gapCacheKey = cacheKey;
    _gapCache = _gapAnalyzer.analyze(sortedStations);
    return _gapCache!;
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
    final stopwatch = Stopwatch()..start();
    final rows = await _supabase.getChargingStations();
    stopwatch.stop();
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
    debugPrint(
        'Map diagnostics: Supabase charging-station fetch ${stopwatch.elapsedMilliseconds}ms; ${rows.length} charging-station rows fetched; ${stations.length} valid coordinates; $invalidCoordinates invalid coordinate records.');
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
      'latitude': 3.1390,
      'longitude': 101.6869,
      'charger_type': proposal.charger,
      'expected_demand': proposal.demand == 'High'
          ? 3
          : proposal.demand == 'Low'
              ? 1
              : 2,
      'status': 'pending',
    });
  }

  Future<void> reactToProposal(Proposal proposal, bool like) =>
      _supabase.addReaction(
        proposalId: proposal.id,
        reaction: like ? 'like' : 'dislike',
      );

  Future<void> updateStatus(String id, String status) =>
      _supabase.updateProposalStatus(id, status);

  double _nearestStationKm(
      Map<String, dynamic> proposal, List<Map<String, dynamic>> stations) {
    if (stations.isEmpty) return 0;
    final lat = (proposal['latitude'] as num?)?.toDouble();
    final lng = (proposal['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return 0;
    return stations.map((station) {
      final stationLat = (station['latitude'] as num?)?.toDouble() ?? lat;
      final stationLng = (station['longitude'] as num?)?.toDouble() ?? lng;
      final dx = (lat - stationLat) * 111;
      final dy = (lng - stationLng) * 111;
      return math.sqrt(dx * dx + dy * dy);
    }).reduce((a, b) => a < b ? a : b);
  }
}
