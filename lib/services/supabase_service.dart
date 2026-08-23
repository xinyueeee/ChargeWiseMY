import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient client = Supabase.instance.client;

  static const mockUserId = '00000000-0000-4000-8000-000000000001';

  String get actingUserId => client.auth.currentUser?.id ?? mockUserId;

  Future<List<Map<String, dynamic>>> getChargingStations(
      {String? status}) async {
    const pageSize = 1000;
    final stations = <Map<String, dynamic>>[];
    var offset = 0;
    var pageNumber = 0;
    final seenStationIds = <String>{};
    var duplicateRows = 0;
    final totalStopwatch = Stopwatch()..start();

    while (true) {
      pageNumber++;
      final pageStopwatch = Stopwatch()..start();
      final query = client.from('charging_stations').select(
            'station_id, station_name, latitude, longitude, charger_type, '
            'address, charger_count, ac_charger_count, dc_charger_count, '
            'proposed_charger_count, state, pbt, category, status, '
            'indoor_outdoor, mevnet_object_id, source, source_url, data_date, '
            'imported_at',
          );
      final filteredQuery = status == null ? query : query.eq('status', status);
      final page = await filteredQuery
          .order('station_id', ascending: true)
          .range(offset, offset + pageSize - 1);
      pageStopwatch.stop();
      final rows = List<Map<String, dynamic>>.from(page);
      for (final row in rows) {
        final stationId = row['station_id']?.toString();
        if (stationId != null && !seenStationIds.add(stationId)) {
          duplicateRows++;
        }
      }
      stations.addAll(rows);
      debugPrint(
        'Supabase station pagination: page=$pageNumber, '
        'status=${status ?? 'all'}, rows=${rows.length}, '
        'duration=${pageStopwatch.elapsedMilliseconds}ms.',
      );
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    totalStopwatch.stop();
    debugPrint(
      'Supabase station pagination complete: pages=$pageNumber, '
      'rows=${stations.length}, status=${status ?? 'all'}, sequential=true, '
      'uniqueStationIds=${seenStationIds.length}, '
      'duplicatePageRows=$duplicateRows, '
      'duration=${totalStopwatch.elapsedMilliseconds}ms.',
    );
    return stations;
  }

  Future<int> getChargingStationCount() {
    return client.from('charging_stations').count(CountOption.exact);
  }

  Future<List<Map<String, dynamic>>> getProposalsWithReactions() async {
    final response = await client
        .from('proposals')
        .select(
          '*, proposal_reactions(reaction, user_id)',
        )
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> ensureMockUser() async {
    if (client.auth.currentSession != null) return;
    await client.from('users').upsert({
      'id': mockUserId,
      'full_name': 'ChargeWise Demo User',
      'email': 'demo.user@chargewise.my',
      'role': 'driver',
    });
  }

  Future<String> ensureActingUser() async {
    await ensureMockUser();
    return actingUserId;
  }

  Future<void> setProposalReaction({
    required String proposalId,
    required String? reaction,
  }) async {
    final userId = await ensureActingUser();
    if (reaction == null) {
      final deleted = await client
          .from('proposal_reactions')
          .delete()
          .eq('proposal_id', proposalId)
          .eq('user_id', userId)
          .select('reaction')
          .maybeSingle();
      if (deleted == null) {
        throw StateError('Proposal reaction was not removed.');
      }
      return;
    }
    final updated = await client
        .from('proposal_reactions')
        .upsert(
          {
            'proposal_id': proposalId,
            'user_id': userId,
            'reaction': reaction,
          },
          onConflict: 'proposal_id,user_id',
        )
        .select('reaction')
        .maybeSingle();
    if (updated == null) {
      throw StateError('Proposal reaction was not saved.');
    }
  }

  Future<void> updateProposalStatus(String proposalId, String status) async {
    final updated = await client
        .from('proposals')
        .update({'status': status})
        .eq('proposal_id', proposalId)
        .select('proposal_id')
        .maybeSingle();
    if (updated == null) {
      throw StateError(
        'Proposal status was not updated by the authenticated administrator.',
      );
    }
  }

  Future<void> updateProposal(
    String proposalId,
    Map<String, dynamic> values,
  ) async {
    final userId = await ensureActingUser();
    await client
        .from('proposals')
        .update(values)
        .eq('proposal_id', proposalId)
        .eq('user_id', userId);
  }

  Future<void> deleteProposal(String proposalId) async {
    final userId = await ensureActingUser();
    final deleted = await client
        .from('proposals')
        .delete()
        .eq('proposal_id', proposalId)
        .eq('user_id', userId)
        .select('proposal_id')
        .maybeSingle();
    if (deleted == null) {
      throw StateError('Proposal was not deleted by its owner.');
    }
  }
}
