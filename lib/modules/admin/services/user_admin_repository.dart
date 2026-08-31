import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user_summary.dart';

class UserAdminRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AdminUserSummary>> getAllUsers() async {
    final rows = await _client
        .from('users')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(AdminUserSummary.fromMap)
        .toList();
  }

  Future<void> setStatus(String userId, String status) async {
    await _client.rpc('set_user_status', params: {
      'target_user_id': userId,
      'new_status': status,
    });
  }
}
