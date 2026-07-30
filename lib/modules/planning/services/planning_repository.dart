import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../services/supabase_service.dart';
import '../models/proposal.dart';

class PlanningRepository {
  PlanningRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();
  final SupabaseService _supabase;

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

  Future<List<GapArea>> getGaps() async {
    final raw = await rootBundle.loadString('assets/data/priority_areas.json');
    final gaps =
        (jsonDecode(raw) as List).map((e) => GapArea.fromJson(e)).toList();
    debugPrint(
        'Map diagnostics: ${gaps.length} priority-area records loaded; ${gaps.where((gap) => gap.latitude != null && gap.longitude != null).length} have valid coordinates.');
    return gaps;
  }

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
