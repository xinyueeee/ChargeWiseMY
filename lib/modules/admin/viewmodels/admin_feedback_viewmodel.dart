import 'package:flutter/foundation.dart';

import '../../feedback/models/fault_report.dart';
import '../models/maintenance_record.dart';
import '../services/feedback_admin_repository.dart';

/// Mirrors `PlanningViewModel`'s / `FeedbackViewModel`'s shape: a single
/// `ChangeNotifier` the admin feedback screens read via
/// `Consumer`/`context.watch`, backed by [FeedbackAdminRepository]. Scoped
/// to the "Feedback" tab's subtree in `AdminShell` — never provided
/// globally, so a driver session never constructs one or issues
/// admin-scoped queries RLS would reject anyway (see
/// MODULE3_ADMIN_IMPLEMENTATION_PLAN.md §7).
class AdminFeedbackViewModel extends ChangeNotifier {
  AdminFeedbackViewModel(this._repository);
  final FeedbackAdminRepository _repository;

  List<FaultReport> reports = const [];
  List<MaintenanceRecord> maintenanceRecords = const [];
  bool loading = true;
  String? errorMessage;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      reports = await _repository.getAllReports();
      maintenanceRecords = await _repository.getMaintenanceRecords();
    } catch (error, stackTrace) {
      debugPrint('AdminFeedbackViewModel.load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage = 'Unable to load feedback data. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  int get submittedCount => reports.where((r) => r.status == 'Submitted').length;
  int get verifiedCount => reports.where((r) => r.status == 'Verified').length;
  int get inProgressCount =>
      reports.where((r) => r.status == 'In Progress').length;
  int get resolvedCount => reports.where((r) => r.status == 'Resolved').length;
  int get totalReports => reports.length;

  int get openMaintenanceCount =>
      maintenanceRecords.where((r) => r.isOngoing).length;

  /// Reports still awaiting an admin's first decision — what "Verify
  /// Reports" lists.
  List<FaultReport> get reportsToVerify =>
      reports.where((r) => r.status == 'Submitted').toList();

  List<FaultReport> get recentReports {
    final sorted = List<FaultReport>.of(reports)
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime(0);
        final bDate = b.createdAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
    return sorted;
  }

  Future<void> verifyReport(FaultReport report) async {
    await _repository.verifyReport(report);
    await load();
  }

  Future<void> resolveReport(FaultReport report) async {
    await _repository.resolveReport(report);
    await load();
  }

  Future<void> updatePriority(FaultReport report, String priority) async {
    await _repository.updatePriority(report, priority);
    await load();
  }

  Future<void> createMaintenanceRecord({
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
    await _repository.createMaintenanceRecord(
      summary: summary,
      description: description,
      status: status,
      maintenanceDate: maintenanceDate,
      reportId: reportId,
      stationId: stationId,
      technicianName: technicianName,
      etaLabel: etaLabel,
      cost: cost,
    );
    await load();
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
    await _repository.updateMaintenanceRecord(
      original,
      summary: summary,
      description: description,
      status: status,
      maintenanceDate: maintenanceDate,
      technicianName: technicianName,
      etaLabel: etaLabel,
      cost: cost,
    );
    await load();
  }

  Future<void> deleteMaintenanceRecord(String recordId) async {
    await _repository.deleteMaintenanceRecord(recordId);
    await load();
  }

  /// Looks up a report by id — used by maintenance screens that only have a
  /// `reportId` on hand (e.g. showing the linked report's category/location
  /// inline on a maintenance card).
  FaultReport? reportById(String? reportId) {
    if (reportId == null) return null;
    for (final report in reports) {
      if (report.id == reportId) return report;
    }
    return null;
  }
}
