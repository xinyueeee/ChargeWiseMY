import '../../planning/models/proposal.dart' show CoordinateParser;

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

const List<String> kFaultReportPriorities = ['High', 'Medium', 'Low'];

const int kFaultReportMaxPhotos = 3;

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

  String status;

  String priority;

  final String? stationId;

  final List<String> photoUrls;

  final String? contactInfo;

  final String locationLabel;
  final String? state;
  final String? nearestTown;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final String? userId;

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
