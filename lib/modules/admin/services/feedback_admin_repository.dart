import 'package:flutter/foundation.dart';

import '../../../services/supabase_service.dart';
import '../../feedback/models/fault_report.dart';
import '../models/maintenance_record.dart';

class FeedbackAdminRepository {
  FeedbackAdminRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();

  final SupabaseService _supabase;

  String? get currentAdminId => _supabase.authenticatedUserId;

  Future<List<FaultReport>> getAllReports() async {
    final rows = await _supabase.getFaultReports();
    final reports = rows.map(FaultReport.fromSupabase).toList();
    final userIds =
        reports.map((report) => report.userId).whereType<String>().toSet();
    if (userIds.isEmpty) return reports;
    Map<String, String> names;
    try {
      names = await _supabase.getUserNames(userIds);
    } catch (error, stackTrace) {
      // Reporter-name enrichment is cosmetic. A failure here (e.g. a users
      // table RLS/permission hiccup) must not discard the entire report
      // list — fall back to reports without reporter names.
      debugPrint('getAllReports: reporter name lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return reports;
    }
    return [
      for (final report in reports)
        if (report.userId != null && names.containsKey(report.userId))
          report.copyWithReporter(names[report.userId]!)
        else
          report,
    ];
  }

  Future<List<MaintenanceRecord>> getMaintenanceRecords() async {
    final rows = await _supabase.getMaintenanceRecords();
    return rows.map(MaintenanceRecord.fromSupabase).toList();
  }

  /// Subscribes to live fault-report changes (a driver submitting a new
  /// report, another admin acting on one). Returns a disposer.
  VoidCallback subscribeToReports(void Function() onChange) {
    final channel = _supabase.subscribeToFaultReports(onChange);
    return () => _supabase.removeChannel(channel);
  }

  Future<void> verifyReport(FaultReport report) async {
    await _supabase.updateFaultReportStatus(
      report.id,
      'verified',
      adminId: currentAdminId,
    );
  }

  Future<void> resolveReport(FaultReport report) async {
    await _supabase.updateFaultReportStatus(report.id, 'resolved');
  }

  Future<void> updatePriority(FaultReport report, String priority) async {
    await _supabase.updateFaultReportPriority(
      report.id,
      priority.toLowerCase(),
    );
  }

  Future<String> createMaintenanceRecord({
    required String summary,
    required String description,
    required String status,
    required DateTime maintenanceDate,
    String? reportId,
    String? stationId,
    String? technicianName,
    String? etaLabel,
    double? cost,
  }) async {
    final recordId = await _supabase.insertMaintenanceRecord({
      'report_id': reportId,
      'station_id': stationId,
      'performed_by': currentAdminId,
      'technician_name': technicianName,
      'summary': summary,
      'description': description,
      'status': MaintenanceRecord.rawStatus(status),
      'eta_label': etaLabel,
      'maintenance_date': maintenanceDate.toIso8601String(),
      'cost': cost,
    });
    if (reportId != null) {
      await _supabase.updateFaultReportStatus(
        reportId,
        status == 'Completed' ? 'resolved' : 'in_progress',
      );
    }
    return recordId;
  }

  Future<void> updateMaintenanceRecord(
    MaintenanceRecord original, {
    required String summary,
    required String description,
    required String status,
    required DateTime maintenanceDate,
    String? technicianName,
    String? etaLabel,
    double? cost,
  }) async {
    await _supabase.updateMaintenanceRecord(original.id, {
      'summary': summary,
      'description': description,
      'status': MaintenanceRecord.rawStatus(status),
      'technician_name': technicianName,
      'eta_label': etaLabel,
      'maintenance_date': maintenanceDate.toIso8601String(),
      'cost': cost,
    });
    final reportId = original.reportId;
    if (reportId != null &&
        status == 'Completed' &&
        original.status != 'Completed') {
      await _supabase.updateFaultReportStatus(reportId, 'resolved');
    }
  }

  Future<void> deleteMaintenanceRecord(String recordId) async {
    await _supabase.deleteMaintenanceRecord(recordId);
  }
}
