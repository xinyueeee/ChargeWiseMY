import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient client = Supabase.instance.client;

  // Temporary identity until Supabase Auth is introduced.
  static const mockUserId = '00000000-0000-4000-8000-000000000001';

  Future<List<Map<String, dynamic>>> getChargingStations() async {
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
      final page = await client
          .from('charging_stations')
          .select('station_id, station_name, latitude, longitude, charger_type')
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
        'rows=${rows.length}, duration=${pageStopwatch.elapsedMilliseconds}ms.',
      );
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    totalStopwatch.stop();
    debugPrint(
      'Supabase station pagination complete: pages=$pageNumber, '
      'rows=${stations.length}, sequential=true, '
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
    // Once a real Supabase Auth session exists, requests run as the
    // `authenticated` role and RLS only allows writing your own row, so
    // this hardcoded placeholder upsert would be rejected. Only needed
    // for pre-auth/anonymous testing.
    if (client.auth.currentSession != null) return;
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

  Future<void> updateProposal(
    String proposalId,
    Map<String, dynamic> values,
  ) async {
    await client.from('proposals').update(values).eq(
          'proposal_id',
          proposalId,
        );
  }

  Future<void> deleteProposal(String proposalId) async {
    await client.from('proposals').delete().eq(
          'proposal_id',
          proposalId,
        );
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
