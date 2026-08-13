import '../../planning/models/proposal.dart' show CoordinateParser;

/// Fixed category options for a fault report — mirrors how `charger_type`
/// is offered as a fixed dropdown on the proposal form (see
/// `new_proposal_screen.dart`), rather than free text.
const List<String> kFaultReportCategories = [
  'Broken Connector',
  'Not Charging',
  'Damaged Screen',
  'Payment Issue',
  'Other',
];

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
  });

  final String id, category, description;

  /// Human-display status ('Submitted' / 'Verified' / 'Resolved'), same
  /// convention as `Proposal.status` — the raw DB value is lowercase
  /// (`fault_reports.status`), capitalized here for display. When writing
  /// back to Supabase, lowercase it again (mirrors
  /// `SupabaseService.updateProposalStatus`).
  String status;

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

  factory FaultReport.fromSupabase(Map<String, dynamic> row) => FaultReport(
        id: row['report_id'] as String,
        category: row['category'] as String? ?? 'Other',
        description: row['description'] as String? ?? '',
        status: _displayStatus(row['status'] as String?),
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
      FaultReport(
        id: id,
        category: category,
        description: description,
        status: status,
        stationId: stationId,
        photoUrls: photoUrls,
        contactInfo: contactInfo,
        locationLabel: locationLabel,
        state: state,
        nearestTown: nearestTown,
        latitude: latitude,
        longitude: longitude,
        createdAt: createdAt,
        userId: userId,
      );

  static String _displayStatus(String? value) {
    if (value == null || value.isEmpty) return 'Submitted';
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }
}