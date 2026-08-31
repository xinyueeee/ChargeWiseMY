import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const mockUserId = '00000000-0000-4000-8000-000000000001';

  final SupabaseClient client = Supabase.instance.client;

  String? get authenticatedUserId => client.auth.currentUser?.id;

  Stream<String?> get authenticatedUserChanges => client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct();

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

  Future<String> ensureActingUser() async {
    final userId = authenticatedUserId;
    if (userId == null) {
      throw const AuthException(
        'Authentication is required for proposal operations.',
      );
    }
    return userId;
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
    final updated = await client
        .from('proposals')
        .update(values)
        .eq('proposal_id', proposalId)
        .eq('user_id', userId)
        .select('proposal_id')
        .maybeSingle();
    if (updated == null) {
      throw StateError('Proposal was not updated by its owner.');
    }
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

  Future<List<Map<String, dynamic>>> getFaultReports() async {
    final response = await client
        .from('fault_reports')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> insertFaultReport(Map<String, dynamic> values) async {
    final row = await client
        .from('fault_reports')
        .insert(values)
        .select('report_id')
        .single();
    return row['report_id'] as String;
  }

  Future<void> updateFaultReport(
    String reportId,
    Map<String, dynamic> values,
  ) async {
    await client.from('fault_reports').update(values).eq(
          'report_id',
          reportId,
        );
  }

  Future<void> deleteFaultReport(String reportId) async {
    await client.from('fault_reports').delete().eq(
          'report_id',
          reportId,
        );
  }

  Future<String> uploadFaultReportPhoto(
    String reportId,
    XFile file, {
    required int index,
  }) async {
    final userId = client.auth.currentUser?.id ?? mockUserId;
    final bytes = await file.readAsBytes();
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    final path = '$userId/$reportId/$index.$extension';
    await client.storage.from('fault_report_photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: file.mimeType),
        );
    return client.storage.from('fault_report_photos').getPublicUrl(path);
  }

  Future<Map<String, String>> getUserNames(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await client
        .from('users')
        .select('id, full_name, role')
        .inFilter('id', ids);
    return {
      for (final row in List<Map<String, dynamic>>.from(rows))
        row['id'] as String: _reporterDisplayName(row),
    };
  }

  String _reporterDisplayName(Map<String, dynamic> row) {
    final name = (row['full_name'] as String?)?.trim().isNotEmpty == true
        ? row['full_name'] as String
        : 'Unknown driver';
    return row['role'] == 'admin' ? '$name (Admin)' : name;
  }

  Future<void> updateFaultReportStatus(
    String reportId,
    String status, {
    String? adminId,
  }) async {
    await client.from('fault_reports').update({
      'status': status,
      if (status == 'verified') 'verified_at': DateTime.now().toIso8601String(),
      if (status == 'verified') 'verified_by': adminId,
      if (status == 'in_progress')
        'in_progress_at': DateTime.now().toIso8601String(),
      if (status == 'resolved') 'resolved_at': DateTime.now().toIso8601String(),
    }).eq('report_id', reportId);
  }

  Future<void> updateFaultReportPriority(
      String reportId, String priority) async {
    await client
        .from('fault_reports')
        .update({'priority': priority}).eq('report_id', reportId);
  }

  Future<List<Map<String, dynamic>>> getMaintenanceRecords() async {
    final response = await client
        .from('maintenance_records')
        .select()
        .order('maintenance_date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> insertMaintenanceRecord(Map<String, dynamic> values) async {
    final row = await client
        .from('maintenance_records')
        .insert(values)
        .select('record_id')
        .single();
    return row['record_id'] as String;
  }

  Future<void> updateMaintenanceRecord(
    String recordId,
    Map<String, dynamic> values,
  ) async {
    await client
        .from('maintenance_records')
        .update(values)
        .eq('record_id', recordId);
  }

  Future<void> deleteMaintenanceRecord(String recordId) async {
    await client.from('maintenance_records').delete().eq('record_id', recordId);
  }
}
