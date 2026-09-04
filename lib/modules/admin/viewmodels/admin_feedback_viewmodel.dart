import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../feedback/models/fault_report.dart';
import '../models/maintenance_record.dart';
import '../services/feedback_admin_repository.dart';

class AdminFeedbackViewModel extends ChangeNotifier {
  AdminFeedbackViewModel(this._repository) {
    _unsubscribe = _repository.subscribeToReports(_onRemoteChange);
  }
  final FeedbackAdminRepository _repository;

  static const _realtimeDebounce = Duration(milliseconds: 500);

  VoidCallback? _unsubscribe;
  Timer? _refreshTimer;
  bool _disposed = false;

  List<FaultReport> reports = const [];
  List<MaintenanceRecord> maintenanceRecords = const [];
  bool loading = true;
  String? errorMessage;

  bool hasLoadedOnce = false;

  void _onRemoteChange() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_realtimeDebounce, () {
      if (!_disposed) load(silent: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _unsubscribe?.call();
    super.dispose();
  }

  /// [silent] skips the full-screen loading state — used for background
  /// refreshes (tab switches, returning from a child screen) so the list
  /// doesn't flash a spinner every time.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    errorMessage = null;
    try {
      reports = await _repository.getAllReports();
      maintenanceRecords = await _repository.getMaintenanceRecords();
    } catch (error, stackTrace) {
      debugPrint('AdminFeedbackViewModel.load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage = 'Unable to load feedback data. Please try again.';
    } finally {
      loading = false;
      hasLoadedOnce = true;
      if (!_disposed) notifyListeners();
    }
  }

  int get submittedCount =>
      reports.where((r) => r.status == 'Submitted').length;
  int get verifiedCount => reports.where((r) => r.status == 'Verified').length;
  int get inProgressCount =>
      reports.where((r) => r.status == 'In Progress').length;
  int get resolvedCount => reports.where((r) => r.status == 'Resolved').length;
  int get totalReports => reports.length;

  int get openMaintenanceCount =>
      maintenanceRecords.where((r) => r.isOngoing).length;

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

  FaultReport? reportById(String? reportId) {
    if (reportId == null) return null;
    for (final report in reports) {
      if (report.id == reportId) return report;
    }
    return null;
  }
}
