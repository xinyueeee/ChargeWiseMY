import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient client = Supabase.instance.client;

  // Temporary identity until Supabase Auth is introduced.
  static const mockUserId = '00000000-0000-4000-8000-000000000001';

  Future<List<dynamic>> getChargingStations() async {
    return client.from('charging_stations').select();
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
    await client.from('users').upsert({
      'id': mockUserId,
      'full_name': 'ChargeWise Demo User',
      'email': 'demo.user@chargewise.my',
      'role': 'driver',
    });
  }

  Future<void> addReaction(
      {required String proposalId, required String reaction}) async {
    await client.from('proposal_reactions').insert({
      'proposal_id': proposalId,
      'user_id': mockUserId,
      'reaction': reaction,
    });
  }

  Future<void> updateProposalStatus(String proposalId, String status) async {
    await client
        .from('proposals')
        .update({'status': status.toLowerCase().replaceAll(' ', '_')}).eq(
            'proposal_id', proposalId);
  }
}
