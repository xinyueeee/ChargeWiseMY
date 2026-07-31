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
    this.latitude,
    this.longitude,
    this.reaction = 0,
  });
  final String id, city, description, area, charger, demand;
  String status;
  final int supports;
  final double distance;
  final double? latitude;
  final double? longitude;
  int reaction;
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
        latitude: CoordinateParser.latitude(row['latitude']),
        longitude: CoordinateParser.longitude(row['longitude']),
        reaction: reaction,
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

  int get displayedSupports => supports + (reaction == 1 ? 1 : 0);
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
    this.latitude,
    this.longitude,
  });
  final String id, name, state, priority, reason;
  final double distance;
  final int nearbyStationCount;
  final double priorityScore;
  final double coverageScore;
  final double nearbyRadiusKm;
  final double? latitude;
  final double? longitude;

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
        reason: data['reason']! as String,
        latitude: CoordinateParser.latitude(data['latitude']),
        longitude: CoordinateParser.longitude(data['longitude']),
      );
}

class ChargingStation {
  const ChargingStation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.chargerType,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String chargerType;

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
    );
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
