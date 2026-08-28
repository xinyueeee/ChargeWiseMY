/// Dispatch/tracking status for a [MaintenanceRecord] — distinct from a
/// fault report's own lifecycle status (see `FaultReport.status`).
/// 'Completed' is what moves a linked report to 'Resolved'; it's excluded
/// from the "Maintenance Ongoing" list once reached.
const List<String> kMaintenanceStatuses = [
  'Scheduled',
  'On Site',
  'Delayed',
  'Other',
  'Completed',
];

/// A logged maintenance task — closes out a specific [FaultReport] (when
/// [reportId] is set) or stands alone for routine/preventive work tied only
/// to a [stationId]. See MODULE3_ADMIN_IMPLEMENTATION_PLAN.md §3.2.
class MaintenanceRecord {
  MaintenanceRecord({
    required this.id,
    required this.summary,
    required this.description,
    required this.status,
    required this.maintenanceDate,
    this.reportId,
    this.stationId,
    this.technicianName,
    this.etaLabel,
    this.cost,
    this.performedBy,
    this.createdAt,
  });

  final String id, summary, description;
  String status;
  final DateTime maintenanceDate;
  final String? reportId;
  final String? stationId;
  final String? technicianName;

  /// Free-text ETA, e.g. "1 hour" / "30 mins" — shown as "ETA: {etaLabel}"
  /// normally, or "Delayed by {etaLabel}" when [status] is 'Delayed'.
  final String? etaLabel;
  final double? cost;
  final String? performedBy;
  final DateTime? createdAt;

  bool get isOngoing => status != 'Completed';

  factory MaintenanceRecord.fromSupabase(Map<String, dynamic> row) =>
      MaintenanceRecord(
        id: row['record_id'] as String,
        summary: row['summary'] as String? ?? '',
        description: row['description'] as String? ?? '',
        status: _displayStatus(row['status'] as String?),
        maintenanceDate:
            DateTime.tryParse('${row['maintenance_date'] ?? ''}') ??
                DateTime.now(),
        reportId: row['report_id'] as String?,
        stationId: row['station_id'] as String?,
        technicianName: (row['technician_name'] as String?)?.trim().isNotEmpty ==
                true
            ? row['technician_name'] as String
            : null,
        etaLabel: (row['eta_label'] as String?)?.trim().isNotEmpty == true
            ? row['eta_label'] as String
            : null,
        cost: (row['cost'] as num?)?.toDouble(),
        performedBy: row['performed_by'] as String?,
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
      );

  /// Raw lowercase/snake_case value for writing back to Supabase — reverse
  /// of [_displayStatus].
  static String rawStatus(String displayStatus) {
    switch (displayStatus) {
      case 'On Site':
        return 'on_site';
      case 'Delayed':
        return 'delayed';
      case 'Other':
        return 'other';
      case 'Completed':
        return 'completed';
      case 'Scheduled':
      default:
        return 'scheduled';
    }
  }

  static String _displayStatus(String? value) {
    switch (value) {
      case 'on_site':
        return 'On Site';
      case 'delayed':
        return 'Delayed';
      case 'other':
        return 'Other';
      case 'completed':
        return 'Completed';
      case 'scheduled':
      default:
        return 'Scheduled';
    }
  }
}
