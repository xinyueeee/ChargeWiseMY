class Proposal {
  Proposal({
    required this.id,
    required this.city,
    required this.description,
    required this.supports,
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
    this.latitude,
    this.longitude,
    this.reaction = 0,
    this.reactionIncludedInSupports = false,
  });
  final String id, city, description, area, charger, demand;
  final String locationLabel;
  final String? state;
  final String? nearestTown;
  final DateTime? createdAt;
  final String createdBy;
  final String? ownerUserId;
  String status;
  final int supports;
  final double distance;
  final double? latitude;
  final double? longitude;
  int reaction;
  final bool reactionIncludedInSupports;
  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
        id: json['id'],
        city: json['city'],
        description: json['description'],
        supports: json['supports'],
        status: json['status'],
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
        latitude: CoordinateParser.latitude(json['latitude']),
        longitude: CoordinateParser.longitude(json['longitude']),
      );

  factory Proposal.fromSupabase(
    Map<String, dynamic> row, {
    required double nearestStationKm,
    required int supportCount,
    required int reaction,
  }) =>
      Proposal(
        id: row['proposal_id'] as String,
        city: (row['title'] as String?)?.trim().isNotEmpty == true
            ? row['title'] as String
            : (row['address'] as String? ?? 'Unnamed location'),
        description: row['description'] as String? ?? '',
        supports: supportCount,
        status: _displayStatus(row['status'] as String?),
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
        createdBy:
            row['user_id'] == '00000000-0000-4000-8000-000000000001'
                ? 'ChargeWise Demo User'
                : 'Community member',
        ownerUserId: row['user_id']?.toString(),
        latitude: CoordinateParser.latitude(row['latitude']),
        longitude: CoordinateParser.longitude(row['longitude']),
        reaction: reaction,
        reactionIncludedInSupports: reaction == 1,
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
        latitude: latitude,
        longitude: longitude,
        reaction: reaction,
        reactionIncludedInSupports: reactionIncludedInSupports,
      );

  static String _displayStatus(String? value) {
    if (value == null || value.isEmpty) return 'Pending';
    return value
        .split('_')
        .map((word) =>
            '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String _displayDemand(dynamic value) {
    final demand = value is int ? value : int.tryParse('$value') ?? 2;
    if (demand >= 3) return 'High';
    if (demand <= 1) return 'Low';
    return 'Medium';
  }

  int get displayedSupports =>
      supports + (reaction == 1 && !reactionIncludedInSupports ? 1 : 0);
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
        analysisProfileId:
            data['analysisProfileId'] as String? ?? 'regional',
        roadAccessibilityValidated:
            data['roadAccessibilityValidated'] as bool? ?? false,
        coordinateAdjusted: data['coordinateAdjusted'] as bool? ?? false,
        adjustmentDistanceMeters:
            (data['adjustmentDistanceMeters'] as num?)?.toDouble() ?? 0,
        suitabilityNote: data['suitabilityNote'] as String? ??
            'Road-access validation is unavailable for this analysis.',
        nearestSettlementId: data['nearestSettlementId'] as String?,
        nearestSettlementName: data['nearestSettlementName'] as String?,
        nearestSettlementCategory:
            data['nearestSettlementCategory'] as String?,
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
  final String? state;
  final String? pbt;
  final String? category;
  final String? status;
  final String? indoorOutdoor;

  /// A database row represents one physical charging location. Installed
  /// charger counts are descriptive metadata and are never expanded into
  /// extra locations, markers, or coverage-analysis inputs.
  String get planningInfoWindowSnippet {
    final context = <String>[
      if (pbt?.trim().isNotEmpty == true) pbt!.trim(),
      if (state?.trim().isNotEmpty == true) state!.trim(),
    ].join(', ');
    return <String>[
      chargerType,
      'Installed Chargers: ${chargerCount?.toString() ?? 'Not available'}',
      'AC: ${acChargerCount?.toString() ?? 'Not available'} · '
          'DC: ${dcChargerCount?.toString() ?? 'Not available'}',
      if (context.isNotEmpty) context,
    ].join('\n');
  }

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
