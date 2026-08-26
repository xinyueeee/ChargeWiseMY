import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  /// Placeholder id used only as a defensive fallback when a feedback screen
  /// somehow renders without a signed-in session (every such screen sits
  /// behind `AuthGate`, so this should never actually be hit).
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

  // --- Module 3: fault reports (driver-facing) ---------------------------

  Future<List<Map<String, dynamic>>> getFaultReports() async {
    final response = await client
        .from('fault_reports')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Inserts a report and returns its generated `report_id` — needed by
  /// [FeedbackRepository] to upload the photo under the right storage path
  /// once the row exists (see `uploadFaultReportPhoto`).
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

  /// Uploads one photo of a report (up to `kFaultReportMaxPhotos` total,
  /// distinguished by [index]) and returns its public URL.
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
}
