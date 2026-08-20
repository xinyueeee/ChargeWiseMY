import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class VehicleMake {
  const VehicleMake({required this.name, required this.models});

  final String name;
  final List<String> models;
}

class VehicleCatalogService {
  static List<VehicleMake>? _cache;

  Future<List<VehicleMake>> loadMakes() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(
      'assets/data/ev_makes_models.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final makes = (json['makes'] as List)
        .map(
          (entry) => VehicleMake(
            name: entry['name'] as String,
            models: List<String>.from(entry['models'] as List),
          ),
        )
        .toList();

    _cache = makes;
    return makes;
  }
}
