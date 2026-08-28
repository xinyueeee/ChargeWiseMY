import '../../../services/supabase_service.dart';
import '../../feedback/models/fault_report.dart';
import '../models/maintenance_record.dart';

/// Wraps [SupabaseService] for the admin side of Module 3 — mirrors how
/// `FeedbackRepository` wraps it for the driver side and `PlanningRepository`
/// wraps it for proposals. Owns the reporter-name join (`fault_reports` only
/// stores `user_id`) and the status-transition orchestration between fault
/// reports and maintenance records (see MODULE3_ADMIN_IMPLEMENTATION_PLAN.md
/// §6.4/§6.6).
class FeedbackAdminRepository {
  FeedbackAdminRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();

  final SupabaseService _supabase;

  String? get currentAdminId => _supabase.authenticatedUserId;

  /// Every report, regardless of owner — the `fault_reports_select_all_
  /// authenticated` RLS policy already grants community-wide read access
  /// (needed for the driver's "Nearby Issues" map too), so this is the same
  /// query the driver side uses, just with reporter names attached for the
  /// admin UI.
  Future<List<FaultReport>> getAllReports() async {
    final rows = await _supabase.getFaultReports();
    final reports = rows.map(FaultReport.fromSupabase).toList();
    final userIds = reports
        .map((report) => report.userId)
        .whereType<String>()
        .toSet();
    if (userIds.isEmpty) return reports;
    final names = await _supabase.getUserNames(userIds);
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

  /// Creates a maintenance record and, when it's linked to a report
  /// ([reportId] non-null), transitions that report to 'In Progress' — or
  /// straight to 'Resolved' if the record is logged as already 'Completed'.
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

  /// Updates a maintenance record and, if its status is (re)set to
  /// 'Completed' while it's linked to a report, resolves that report too.
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
    if (reportId != null && status == 'Completed' && original.status != 'Completed') {
      await _supabase.updateFaultReportStatus(reportId, 'resolved');
    }
  }

  Future<void> deleteMaintenanceRecord(String recordId) async {
    await _supabase.deleteMaintenanceRecord(recordId);
  }
}
