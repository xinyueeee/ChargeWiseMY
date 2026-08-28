import '../../planning/models/proposal.dart' show CoordinateParser;

/// Fixed category options for a fault report — mirrors how `charger_type`
/// is offered as a fixed dropdown on the proposal form (see
/// `new_proposal_screen.dart`), rather than free text.
const List<String> kFaultReportCategories = [
  'Broken Connector',
  'Not Charging',
  'Slow Charging',
  'Damaged Screen',
  'Payment Issue',
  'Blocked Access',
  'Physical Damage / Vandalism',
  'Safety Hazard',
  'Incorrect Location / Signage',
  'Other',
];

/// Admin-only triage priorities — drivers never set or see this (the
/// "Report an Issue" form has no priority input). See
/// MODULE3_ADMIN_IMPLEMENTATION_PLAN.md.
const List<String> kFaultReportPriorities = ['High', 'Medium', 'Low'];

/// Up to this many photos may be attached to a single report (matches the
/// "Report an Issue" mockup's photo picker).
const int kFaultReportMaxPhotos = 3;

/// A driver-submitted fault report against a charging station or location.
///
/// Same shape as `Proposal` in `planning/models/proposal.dart`: a plain
/// class with a `fromSupabase` factory and a `copyWith`-style helper for the
/// location step. `CoordinateParser` is reused from that file rather than
/// duplicated — it's a generic lat/lng validator, not proposal-specific.
class FaultReport {
  FaultReport({
    required this.id,
    required this.category,
    required this.description,
    required this.status,
    this.priority = 'Medium',
    this.stationId,
    this.photoUrls = const [],
    this.contactInfo,
    this.locationLabel = '',
    this.state,
    this.nearestTown,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.userId,
    this.reporterName,
  });

  final String id, category, description;

  /// Human-display status ('Submitted' / 'Verified' / 'In Progress' /
  /// 'Resolved') — the raw DB value is lowercase/snake_case
  /// (`fault_reports.status`), mapped here for display. When writing back to
  /// Supabase, map it back down (see `AdminFeedbackRepository`'s reverse
  /// mapping — drivers never write status directly).
  String status;

  /// Human-display priority ('High' / 'Medium' / 'Low'), admin-set only.
  String priority;

  final String? stationId;

  /// Up to [kFaultReportMaxPhotos] public Storage URLs, in upload order.
  final List<String> photoUrls;

  /// Optional phone/email the driver leaves in case an admin needs to
  /// follow up — separate from their account email.
  final String? contactInfo;

  final String locationLabel;
  final String? state;
  final String? nearestTown;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final String? userId;

  /// The reporter's display name — not part of `fault_reports` itself (only
  /// `user_id` is stored there), so this stays null unless a caller joins
  /// against `users` and attaches it via [copyWithReporter]. Only the admin
  /// report list/details screens need this; drivers never see who filed a
  /// report other than themselves.
  final String? reporterName;

  factory FaultReport.fromSupabase(Map<String, dynamic> row) => FaultReport(
        id: row['report_id'] as String,
        category: row['category'] as String? ?? 'Other',
        description: row['description'] as String? ?? '',
        status: _displayStatus(row['status'] as String?),
        priority: _displayPriority(row['priority'] as String?),
        stationId: row['station_id'] as String?,
        photoUrls: (row['photo_urls'] as List?)
                ?.map((url) => url.toString())
                .toList() ??
            const [],
        contactInfo: row['contact_info'] as String?,
        locationLabel: (row['address'] as String?)?.trim() ?? '',
        latitude: CoordinateParser.latitude(row['latitude']),
        longitude: CoordinateParser.longitude(row['longitude']),
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
        userId: row['user_id'] as String?,
      );

  /// Returns a copy with location fields overwritten (used once the picked
  /// point resolves to a state / nearest town / display label via
  /// `ProposalLocationService.resolve()`).
  FaultReport copyWithLocation({
    required String locationLabel,
    required String state,
    required String nearestTown,
  }) =>
      _copyWith(
        locationLabel: locationLabel,
        state: state,
        nearestTown: nearestTown,
      );

  /// Returns a copy with the reporter's display name attached — used by
  /// `AdminFeedbackRepository` after joining against `users`, since
  /// `fault_reports` itself only stores `user_id`.
  FaultReport copyWithReporter(String reporterName) =>
      _copyWith(reporterName: reporterName);

  FaultReport _copyWith({
    String? locationLabel,
    String? state,
    String? nearestTown,
    String? reporterName,
  }) =>
      FaultReport(
        id: id,
        category: category,
        description: description,
        status: status,
        priority: priority,
        stationId: stationId,
        photoUrls: photoUrls,
        contactInfo: contactInfo,
        locationLabel: locationLabel ?? this.locationLabel,
        state: state ?? this.state,
        nearestTown: nearestTown ?? this.nearestTown,
        latitude: latitude,
        longitude: longitude,
        createdAt: createdAt,
        userId: userId,
        reporterName: reporterName ?? this.reporterName,
      );

  static String _displayStatus(String? value) {
    switch (value) {
      case 'verified':
        return 'Verified';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'submitted':
      default:
        return 'Submitted';
    }
  }

  static String _displayPriority(String? value) {
    switch (value) {
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      case 'medium':
      default:
        return 'Medium';
    }
  }
}
