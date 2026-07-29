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
    this.reaction = 0,
  });
  final String id, city, description, area, charger, demand;
  String status;
  final int supports;
  final double distance;
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
    required this.name,
    required this.priority,
    required this.distance,
    required this.users,
  });
  final String name, priority, users;
  final double distance;
  factory GapArea.fromJson(Map<String, dynamic> json) => GapArea(
        name: json['name'],
        priority: json['priority'],
        distance: (json['distance'] as num).toDouble(),
        users: json['users'],
      );
}
