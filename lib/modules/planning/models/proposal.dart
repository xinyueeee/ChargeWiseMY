enum ProposalReaction {
  support('Like'),
  oppose('Dislike');

  const ProposalReaction(this.databaseValue);

  final String databaseValue;

  static ProposalReaction? fromDatabase(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'like' => ProposalReaction.support,
      'dislike' => ProposalReaction.oppose,
      _ => null,
    };
  }

  /// Tapping an already-selected response clears it; tapping the other
  /// response replaces the previous database row through the unique upsert.
  static ProposalReaction? selectionAfterTap(
    ProposalReaction? current,
    ProposalReaction tapped,
  ) =>
      current == tapped ? null : tapped;
}

class Proposal {
  static const statusPending = 'Pending';
  static const statusApproved = 'Approved';
  static const statusRejected = 'Rejected';
  static const statusUnderReview = 'Under Review';
  static const validStatuses = <String>{
    statusPending,
    statusApproved,
    statusRejected,
    statusUnderReview,
  };

  Proposal({
    required this.id,
    required this.city,
    required this.description,
    required this.supports,
    this.opposes = 0,
    required this.status,
    required this.area,
    required this.charger,
    required this.distance,
    required this.demand,
    this.locationLabel = '',
    this.state,
    this.nearestTown,
    this.createdAt,
    this.createdBy = 'Community member',
    this.ownerUserId,
    this.sitePhotoPath,
    this.latitude,
    this.longitude,
    this.currentUserReaction,
  });
  final String id, city, description, area, charger, demand;
  final String locationLabel;
  final String? state;
  final String? nearestTown;
  final DateTime? createdAt;
  final String createdBy;
  final String? ownerUserId;
  final String? sitePhotoPath;
  String status;
  final int supports;
  final int opposes;
  final double distance;
  final double? latitude;
  final double? longitude;
  final ProposalReaction? currentUserReaction;
  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
        id: json['id'],
        city: json['city'],
        description: json['description'],
        supports: json['supports'],
        opposes: json['opposes'] as int? ?? 0,
        status: databaseStatus(json['status'] as String?),
        area: json['area'],
        charger: json['charger'],
        distance: (json['distance'] as num).toDouble(),
        demand: json['demand'],
        locationLabel: json['locationLabel'] as String? ?? '',
        state: json['state'] as String?,
        nearestTown: json['nearestTown'] as String?,
        createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
        createdBy: json['createdBy'] as String? ?? 'Community member',
        ownerUserId: json['ownerUserId'] as String?,
        sitePhotoPath: json['sitePhotoPath'] as String?,
        currentUserReaction: ProposalReaction.fromDatabase(
          json['currentUserReaction'] ?? json['reaction'],
        ),
        latitude: CoordinateParser.latitude(json['latitude']),
        longitude: CoordinateParser.longitude(json['longitude']),
      );

  factory Proposal.fromSupabase(
    Map<String, dynamic> row, {
    required double nearestStationKm,
    required int supportCount,
    required int opposeCount,
    required ProposalReaction? currentUserReaction,
  }) =>
      Proposal(
        id: row['proposal_id'] as String,
        city: (row['title'] as String?)?.trim().isNotEmpty == true
            ? row['title'] as String
            : (row['address'] as String? ?? 'Unnamed location'),
        description: row['description'] as String? ?? '',
        supports: supportCount,
        opposes: opposeCount,
        status: databaseStatus(row['status'] as String?),
        // The current schema has no area-type column. Keep this presentation
        // default until an `area_type` column is added later.
        area: 'Residential Area',
        charger: row['charger_type'] as String? ?? 'AC Charger',
        distance: nearestStationKm,
        demand: _displayDemand(row['expected_demand']),
        locationLabel: (row['address'] as String?)?.trim().isNotEmpty == true
            ? (row['address'] as String).trim()
            : (row['title'] as String? ?? 'Selected location'),
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
        createdBy: row['user_id'] == '00000000-0000-4000-8000-000000000001'
            ? 'ChargeWise Demo User'
            : 'Community member',
        ownerUserId: row['user_id']?.toString(),
        sitePhotoPath:
            (row['site_photo_path'] as String?)?.trim().isNotEmpty == true
                ? (row['site_photo_path'] as String).trim()
                : null,
        latitude: CoordinateParser.latitude(row['latitude']),
        longitude: CoordinateParser.longitude(row['longitude']),
        currentUserReaction: currentUserReaction,
      );

  Proposal copyWithLocation({
    required String locationLabel,
    required String state,
    required String nearestTown,
  }) =>
      Proposal(
        id: id,
        city: city,
        description: description,
        supports: supports,
        opposes: opposes,
        status: status,
        area: area,
        charger: charger,
        distance: distance,
        demand: demand,
        locationLabel: locationLabel,
        state: state,
        nearestTown: nearestTown,
        createdAt: createdAt,
        createdBy: createdBy,
        ownerUserId: ownerUserId,
        sitePhotoPath: sitePhotoPath,
        latitude: latitude,
        longitude: longitude,
        currentUserReaction: currentUserReaction,
      );

  Proposal withReaction(ProposalReaction? reaction) {
    var nextSupports = supports;
    var nextOpposes = opposes;
    if (currentUserReaction == ProposalReaction.support) nextSupports--;
    if (currentUserReaction == ProposalReaction.oppose) nextOpposes--;
    if (reaction == ProposalReaction.support) nextSupports++;
    if (reaction == ProposalReaction.oppose) nextOpposes++;
    return _copy(
      supports: nextSupports < 0 ? 0 : nextSupports,
      opposes: nextOpposes < 0 ? 0 : nextOpposes,
      currentUserReaction: reaction,
      replaceReaction: true,
    );
  }

  Proposal withSitePhotoPath(String? path) => _copy(
        sitePhotoPath: path,
        replaceSitePhotoPath: true,
      );

  Proposal _copy({
    int? supports,
    int? opposes,
    ProposalReaction? currentUserReaction,
    bool replaceReaction = false,
    String? sitePhotoPath,
    bool replaceSitePhotoPath = false,
  }) =>
      Proposal(
        id: id,
        city: city,
        description: description,
        supports: supports ?? this.supports,
        opposes: opposes ?? this.opposes,
        status: status,
        area: area,
        charger: charger,
        distance: distance,
        demand: demand,
        locationLabel: locationLabel,
        state: state,
        nearestTown: nearestTown,
        createdAt: createdAt,
        createdBy: createdBy,
        ownerUserId: ownerUserId,
        sitePhotoPath:
            replaceSitePhotoPath ? sitePhotoPath : this.sitePhotoPath,
        latitude: latitude,
        longitude: longitude,
        currentUserReaction:
            replaceReaction ? currentUserReaction : this.currentUserReaction,
      );

  /// Normalizes only historic presentation variants when reading data. All
  /// runtime values use the database constraint's exact values.
  static String databaseStatus(String? value) {
    switch (value?.trim().toLowerCase().replaceAll('_', ' ')) {
      case 'approved':
        return statusApproved;
      case 'rejected':
        return statusRejected;
      case 'under review':
        return statusUnderReview;
      case 'pending':
      default:
        return statusPending;
    }
  }

  static String _displayDemand(dynamic value) {
    final demand = value is int ? value : int.tryParse('$value') ?? 2;
    if (demand >= 3) return 'High';
    if (demand <= 1) return 'Low';
    return 'Medium';
  }

  int get supportCount => supports;
  int get opposeCount => opposes;
  bool get isActive => status == statusUnderReview || status == statusPending;
  bool get isApproved => status == statusApproved;
  bool get isRejected => status == statusRejected;
  bool get isTerminal => isApproved || isRejected;
  bool get canOwnerEdit => isActive;
  bool get canOwnerDelete => isActive;

  bool canTransitionTo(String nextStatus) => switch (status) {
        statusPending => nextStatus == statusUnderReview,
        statusUnderReview =>
          nextStatus == statusApproved || nextStatus == statusRejected,
        _ => false,
      };

  /// Operational queue order: unresolved review work first, terminal records
  /// later. Dates provide deterministic newest-first ordering within a status.
  static int compareForReviewQueue(Proposal a, Proposal b) {
    final statusComparison =
        statusPriority(a.status).compareTo(statusPriority(b.status));
    if (statusComparison != 0) return statusComparison;
    final dateComparison = (b.createdAt ?? DateTime(1970))
        .compareTo(a.createdAt ?? DateTime(1970));
    return dateComparison != 0 ? dateComparison : a.id.compareTo(b.id);
  }

  static int statusPriority(String status) => switch (status) {
        statusUnderReview => 0,
        statusPending => 1,
        statusApproved => 2,
        statusRejected => 3,
        _ => 4,
      };

  // Retained for existing assessment/dashboard consumers. Reaction rows are
  // already included in [supports], so no local adjustment is required.
  int get displayedSupports => supports;
}

class GapArea {
  const GapArea({
    required this.id,
    required this.name,
    required this.state,
    required this.priority,
    required this.distance,
    required this.nearbyStationCount,
    required this.priorityScore,
    required this.reason,
    this.coverageScore = 0,
    this.nearbyRadiusKm = 25,
    this.localStationLocationCount = 0,
    this.neighbouringCellAverage = 0,
    this.analysisProfileId = 'regional',
    this.roadAccessibilityValidated = false,
    this.coordinateAdjusted = false,
    this.adjustmentDistanceMeters = 0,
    this.suitabilityNote =
        'Road-access validation is unavailable for this analysis.',
    this.nearestSettlementId,
    this.nearestSettlementName,
    this.nearestSettlementCategory,
    this.distanceToSettlementKm,
    this.settlementEligibilityValidated = false,
    this.settlementCoordinateAdjusted = false,
    this.settlementAdjustmentDistanceKm = 0,
    this.latitude,
    this.longitude,
    this.originalAnalyticalLatitude,
    this.originalAnalyticalLongitude,
    this.nearestRoadLatitude,
    this.nearestRoadLongitude,
    this.nearestRoadDistanceMeters,
  });
  final String id, name, state, priority, reason;
  final double distance;
  final int nearbyStationCount;
  final double priorityScore;
  final double coverageScore;
  final double nearbyRadiusKm;
  final int localStationLocationCount;
  final double neighbouringCellAverage;
  final String analysisProfileId;
  final bool roadAccessibilityValidated;
  final bool coordinateAdjusted;
  final double adjustmentDistanceMeters;
  final String suitabilityNote;
  final String? nearestSettlementId;
  final String? nearestSettlementName;
  final String? nearestSettlementCategory;
  final double? distanceToSettlementKm;
  final bool settlementEligibilityValidated;
  final bool settlementCoordinateAdjusted;
  final double settlementAdjustmentDistanceKm;
  final double? latitude;
  final double? longitude;
  final double? originalAnalyticalLatitude;
  final double? originalAnalyticalLongitude;
  final double? nearestRoadLatitude;
  final double? nearestRoadLongitude;
  final double? nearestRoadDistanceMeters;

  factory GapArea.fromAnalysis(Map<Object?, Object?> data) => GapArea(
        id: data['id']! as String,
        name: data['name']! as String,
        state: data['state']! as String,
        priority: data['priority']! as String,
        distance: (data['nearestStationKm']! as num).toDouble(),
        nearbyStationCount: data['nearbyStationCount']! as int,
        priorityScore: (data['score']! as num).toDouble(),
        coverageScore: (data['coverageScore']! as num).toDouble(),
        nearbyRadiusKm: (data['nearbyRadiusKm'] as num?)?.toDouble() ?? 25,
        localStationLocationCount:
            data['localStationLocationCount'] as int? ?? 0,
        neighbouringCellAverage:
            (data['neighbouringCellAverage'] as num?)?.toDouble() ?? 0,
        analysisProfileId: data['analysisProfileId'] as String? ?? 'regional',
        roadAccessibilityValidated:
            data['roadAccessibilityValidated'] as bool? ?? false,
        coordinateAdjusted: data['coordinateAdjusted'] as bool? ?? false,
        adjustmentDistanceMeters:
            (data['adjustmentDistanceMeters'] as num?)?.toDouble() ?? 0,
        suitabilityNote: data['suitabilityNote'] as String? ??
            'Road-access validation is unavailable for this analysis.',
        nearestSettlementId: data['nearestSettlementId'] as String?,
        nearestSettlementName: data['nearestSettlementName'] as String?,
        nearestSettlementCategory: data['nearestSettlementCategory'] as String?,
        distanceToSettlementKm:
            (data['distanceToSettlementKm'] as num?)?.toDouble(),
        settlementEligibilityValidated:
            data['settlementEligibilityValidated'] as bool? ?? false,
        settlementCoordinateAdjusted:
            data['settlementCoordinateAdjusted'] as bool? ?? false,
        settlementAdjustmentDistanceKm:
            (data['settlementAdjustmentDistanceKm'] as num?)?.toDouble() ?? 0,
        reason: data['reason']! as String,
        latitude: CoordinateParser.latitude(data['latitude']),
        longitude: CoordinateParser.longitude(data['longitude']),
        originalAnalyticalLatitude: CoordinateParser.latitude(
          data['originalAnalyticalLatitude'] ?? data['latitude'],
        ),
        originalAnalyticalLongitude: CoordinateParser.longitude(
          data['originalAnalyticalLongitude'] ?? data['longitude'],
        ),
        nearestRoadLatitude:
            CoordinateParser.latitude(data['nearestRoadLatitude']),
        nearestRoadLongitude:
            CoordinateParser.longitude(data['nearestRoadLongitude']),
        nearestRoadDistanceMeters:
            (data['nearestRoadDistanceMeters'] as num?)?.toDouble(),
      );
}

class ChargingStation {
  static const statusExisting = 'Existing';
  static const statusNewlyProposed = 'Newly Proposed';

  const ChargingStation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.chargerType,
    this.address,
    this.chargerCount,
    this.acChargerCount,
    this.dcChargerCount,
    this.proposedChargerCount = 0,
    this.mevnetObjectId,
    this.source,
    this.sourceUrl,
    this.dataDate,
    this.importedAt,
    this.state,
    this.pbt,
    this.category,
    this.status,
    this.indoorOutdoor,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String chargerType;
  final String? address;
  final int? chargerCount;
  final int? acChargerCount;
  final int? dcChargerCount;
  final int proposedChargerCount;
  final int? mevnetObjectId;
  final String? source;
  final String? sourceUrl;
  final DateTime? dataDate;
  final DateTime? importedAt;
  final String? state;
  final String? pbt;
  final String? category;
  final String? status;
  final String? indoorOutdoor;

  /// A database row represents one physical MEVnet location. The ViewModel
  /// admits only `Existing` rows to coverage analysis; `Newly Proposed` rows
  /// remain separate planning context. Counts never expand into extra markers.
  String get planningInfoWindowSnippet {
    final context = <String>[
      if (pbt?.trim().isNotEmpty == true) pbt!.trim(),
      if (state?.trim().isNotEmpty == true) state!.trim(),
    ].join(', ');
    if (status == 'MEVnet Proposed') {
      return <String>[
        'Status: MEVnet Proposed',
        'Proposed EVCB: $proposedChargerCount',
        'Existing EVCB: 0',
        if (context.isNotEmpty) context,
      ].join('\n');
    }
    return <String>[
      'Status: ${status ?? 'Existing'}',
      chargerType,
      'Installed Chargers: ${chargerCount?.toString() ?? 'Not available'}',
      'AC: ${acChargerCount?.toString() ?? 'Not available'} · '
          'DC: ${dcChargerCount?.toString() ?? 'Not available'}',
      if (context.isNotEmpty) context,
    ].join('\n');
  }

  bool hasSameSpatialIdentityAs(ChargingStation other) =>
      id == other.id &&
      latitude == other.latitude &&
      longitude == other.longitude;

  bool hasSameRuntimeDataAs(ChargingStation other) =>
      hasSameSpatialIdentityAs(other) &&
      name == other.name &&
      chargerType == other.chargerType &&
      address == other.address &&
      chargerCount == other.chargerCount &&
      acChargerCount == other.acChargerCount &&
      dcChargerCount == other.dcChargerCount &&
      proposedChargerCount == other.proposedChargerCount &&
      mevnetObjectId == other.mevnetObjectId &&
      source == other.source &&
      sourceUrl == other.sourceUrl &&
      dataDate == other.dataDate &&
      importedAt == other.importedAt &&
      state == other.state &&
      pbt == other.pbt &&
      category == other.category &&
      status == other.status &&
      indoorOutdoor == other.indoorOutdoor;

  static ChargingStation? fromSupabase(Map<String, dynamic> row) {
    final latitude = CoordinateParser.latitude(row['latitude']);
    final longitude = CoordinateParser.longitude(row['longitude']);
    final id = row['station_id']?.toString();
    if (id == null || latitude == null || longitude == null) return null;
    return ChargingStation(
      id: id,
      name: row['station_name']?.toString() ?? 'Charging station',
      latitude: latitude,
      longitude: longitude,
      chargerType: row['charger_type']?.toString() ?? 'Charger',
      address: row['address']?.toString(),
      chargerCount: _nullableCount(row['charger_count']),
      acChargerCount: _nullableCount(row['ac_charger_count']),
      dcChargerCount: _nullableCount(row['dc_charger_count']),
      proposedChargerCount: _nullableCount(row['proposed_charger_count']) ?? 0,
      mevnetObjectId: _nullableCount(row['mevnet_object_id']),
      source: row['source']?.toString(),
      sourceUrl: row['source_url']?.toString(),
      dataDate: DateTime.tryParse('${row['data_date'] ?? ''}'),
      importedAt: DateTime.tryParse('${row['imported_at'] ?? ''}'),
      state: row['state']?.toString(),
      pbt: row['pbt']?.toString(),
      category: row['category']?.toString(),
      status: row['status']?.toString(),
      indoorOutdoor: row['indoor_outdoor']?.toString(),
    );
  }

  static int? _nullableCount(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString().trim() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
  }
}

/// One official future charging location published by PLANMalaysia MEVnet.
/// This is planning context only and must never be passed to current-coverage
/// calculations as an operational [ChargingStation].
class PlannedChargingLocation {
  const PlannedChargingLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.proposedChargerCount,
    required this.status,
    this.state,
    this.pbt,
    this.category,
    this.indoorOutdoor,
    this.mevnetObjectId,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int proposedChargerCount;
  final String status;
  final String? state;
  final String? pbt;
  final String? category;
  final String? indoorOutdoor;
  final int? mevnetObjectId;

  bool hasSameRuntimeDataAs(PlannedChargingLocation other) =>
      id == other.id &&
      name == other.name &&
      latitude == other.latitude &&
      longitude == other.longitude &&
      proposedChargerCount == other.proposedChargerCount &&
      status == other.status &&
      state == other.state &&
      pbt == other.pbt &&
      category == other.category &&
      indoorOutdoor == other.indoorOutdoor &&
      mevnetObjectId == other.mevnetObjectId;

  factory PlannedChargingLocation.fromStation(ChargingStation station) =>
      PlannedChargingLocation(
        id: station.id,
        name: station.name,
        latitude: station.latitude,
        longitude: station.longitude,
        proposedChargerCount: station.proposedChargerCount,
        status: station.status ?? 'Newly Proposed',
        state: station.state,
        pbt: station.pbt,
        category: station.category,
        indoorOutdoor: station.indoorOutdoor,
        mevnetObjectId: station.mevnetObjectId,
      );

  ChargingStation get mapLocation => ChargingStation(
        id: 'mevnet_planned_$id',
        name: name,
        latitude: latitude,
        longitude: longitude,
        chargerType: 'MEVnet Proposed',
        proposedChargerCount: proposedChargerCount,
        state: state,
        pbt: pbt,
        category: category,
        status: 'MEVnet Proposed',
        indoorOutdoor: indoorOutdoor,
      );
}

class PlannedInfrastructureContext {
  const PlannedInfrastructureContext({
    required this.nearestDistanceKm,
    required this.nearbyLocationCount,
    required this.nearbyProposedChargerCount,
    required this.radiusKm,
    this.nearestLocation,
  });

  final double? nearestDistanceKm;
  final int nearbyLocationCount;
  final int nearbyProposedChargerCount;
  final double radiusKm;
  final PlannedChargingLocation? nearestLocation;
}

class CoordinateParser {
  const CoordinateParser._();

  static double? latitude(dynamic value) => _parse(value, -90, 90);
  static double? longitude(dynamic value) => _parse(value, -180, 180);

  static double? _parse(dynamic value, double minimum, double maximum) {
    final coordinate =
        value is num ? value.toDouble() : double.tryParse('$value');
    if (coordinate == null ||
        !coordinate.isFinite ||
        coordinate < minimum ||
        coordinate > maximum) {
      return null;
    }
    return coordinate;
  }
}
