import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/proposal.dart';
import 'mevnet_http_client.dart';

const bool useMevnetApi = true;

const String mevnetLayerUrl =
    'https://gisdev.planmalaysia.gov.my/server/rest/services/Hosted/'
    'MEVnet_EVCB/FeatureServer/0';

const String mevnetSourceName = 'MEVnet / PLANMalaysia';

const int mevnetPageSize = 1000;

const List<String> mevnetRequestedFields = <String>[
  'objectid',
  'location',
  'latitude',
  'longitude',
  'state',
  'pbt',
  'category',
  'status',
  'indoor___outdoor',
  'type_ac',
  'type_dc',
  'number_of_existing_ev_charger_s',
  'number_of_proposed_ev_charger__',
  'data_as',
];

const double mevnetMinimumLatitude = 0.5;
const double mevnetMaximumLatitude = 7.6;
const double mevnetMinimumLongitude = 99.5;
const double mevnetMaximumLongitude = 120.0;

const Map<String, String> mevnetStateNames = <String, String>{
  'JOHOR': 'Johor',
  'KEDAH': 'Kedah',
  'KELANTAN': 'Kelantan',
  'MELAKA': 'Melaka',
  'NEGERI SEMBILAN': 'Negeri Sembilan',
  'PAHANG': 'Pahang',
  'PERAK': 'Perak',
  'PERLIS': 'Perlis',
  'PULAU PINANG': 'Penang',
  'SABAH': 'Sabah',
  'SARAWAK': 'Sarawak',
  'SELANGOR': 'Selangor',
  'TERENGGANU': 'Terengganu',
  'W.P. KUALA LUMPUR': 'Kuala Lumpur',
  'W.P. LABUAN': 'Labuan',
  'W.P. PUTRAJAYA': 'Putrajaya',
};

const Map<String, int> _monthNumbers = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

class MEVnetApiException implements Exception {
  const MEVnetApiException(this.message);

  final String message;

  @override
  String toString() => 'MEVnetApiException: $message';
}

class MEVnetApiService {
  MEVnetApiService({
    http.Client? httpClient,
    String layerUrl = mevnetLayerUrl,
    int pageSize = mevnetPageSize,
    DateTime Function()? clock,
    Future<http.Client> Function()? clientFactory,
  })  : _injectedClient = httpClient,
        _clientFactory = clientFactory ?? createMevnetHttpClient,
        _layerUrl = layerUrl,
        _pageSize = pageSize,
        _clock = clock ?? DateTime.now;

  final http.Client? _injectedClient;
  final Future<http.Client> Function() _clientFactory;
  Future<http.Client>? _pendingClient;
  final String _layerUrl;
  final int _pageSize;
  final DateTime Function() _clock;

  Future<http.Client> _resolveClient() async {
    final injected = _injectedClient;
    if (injected != null) return injected;
    final pending = _pendingClient;
    if (pending != null) return pending;
    final future = _clientFactory();
    _pendingClient = future;
    try {
      return await future;
    } catch (_) {
      _pendingClient = null;
      rethrow;
    }
  }

  Future<List<ChargingStation>> getStations({required String status}) async {
    if (status != ChargingStation.statusExisting &&
        status != ChargingStation.statusNewlyProposed) {
      throw ArgumentError.value(
        status,
        'status',
        'Unsupported MEVnet infrastructure status',
      );
    }

    final importedAt = _clock().toUtc();
    final stations = <ChargingStation>[];
    final totalStopwatch = Stopwatch()..start();
    var offset = 0;
    var pageNumber = 0;
    var attributeRows = 0;
    var excludedRows = 0;

    while (true) {
      pageNumber++;
      final pageStopwatch = Stopwatch()..start();
      final page = await _queryPage(status: status, offset: offset);
      pageStopwatch.stop();
      for (final feature in page.features) {
        attributeRows++;
        final station = mapMevnetAttributes(feature, importedAt: importedAt);
        if (station == null) {
          excludedRows++;
        } else {
          stations.add(station);
        }
      }
      debugPrint(
        'MEVnet API pagination: page=$pageNumber, status=$status, '
        'rows=${page.features.length}, offset=$offset, '
        'exceededTransferLimit=${page.exceededTransferLimit}, '
        'duration=${pageStopwatch.elapsedMilliseconds}ms.',
      );

      if (page.features.isEmpty) break;
      offset += page.features.length;

      final maybeMoreRows =
          page.exceededTransferLimit || page.features.length >= _pageSize;
      if (!maybeMoreRows) break;
    }

    totalStopwatch.stop();
    debugPrint(
      'MEVnet API pagination complete: pages=$pageNumber, status=$status, '
      'attributeRows=$attributeRows, mappedStations=${stations.length}, '
      'excludedRows=$excludedRows, '
      'duration=${totalStopwatch.elapsedMilliseconds}ms.',
    );
    return stations;
  }

  Future<_MevnetPage> _queryPage({
    required String status,
    required int offset,
  }) async {
    final uri = Uri.parse('$_layerUrl/query').replace(
      queryParameters: <String, String>{
        'f': 'json',
        'where': 'status=\'$status\'',
        'outFields': mevnetRequestedFields.join(','),
        'returnGeometry': 'false',
        'orderByFields': 'objectid ASC',
        'resultOffset': '$offset',
        'resultRecordCount': '$_pageSize',
      },
    );

    final client = await _resolveClient();
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw MEVnetApiException(
        'MEVnet query returned HTTP ${response.statusCode}.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw MEVnetApiException('MEVnet query returned invalid JSON: $error');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MEVnetApiException(
        'MEVnet query returned an unexpected payload.',
      );
    }

    final error = decoded['error'];
    if (error != null) {
      throw MEVnetApiException('MEVnet query failed: $error');
    }
    final features = decoded['features'];
    if (features is! List) {
      throw const MEVnetApiException(
        'MEVnet query response did not contain a feature list.',
      );
    }
    return _MevnetPage(
      features: features
          .whereType<Map<String, dynamic>>()
          .map((feature) => feature['attributes'])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      exceededTransferLimit: decoded['exceededTransferLimit'] == true,
    );
  }

  Future<void> close() async {
    final injected = _injectedClient;
    if (injected != null) {
      injected.close();
      return;
    }
    final pending = _pendingClient;
    _pendingClient = null;
    if (pending != null) (await pending).close();
  }
}

class _MevnetPage {
  const _MevnetPage({
    required this.features,
    required this.exceededTransferLimit,
  });

  final List<Map<String, dynamic>> features;
  final bool exceededTransferLimit;
}

@visibleForTesting
ChargingStation? mapMevnetAttributes(
  Map<String, dynamic> attributes, {
  required DateTime importedAt,
}) {
  final objectId = _asInteger(attributes['objectid']);
  if (objectId == null || objectId < 0) return null;

  final status = attributes['status']?.toString().trim() ?? '';
  final isExisting = status == ChargingStation.statusExisting;
  final isNewlyProposed = status == ChargingStation.statusNewlyProposed;
  if (!isExisting && !isNewlyProposed) return null;

  final latitude = CoordinateParser.latitude(attributes['latitude']);
  final longitude = CoordinateParser.longitude(attributes['longitude']);
  if (latitude == null || longitude == null) return null;
  if (latitude < mevnetMinimumLatitude ||
      latitude > mevnetMaximumLatitude ||
      longitude < mevnetMinimumLongitude ||
      longitude > mevnetMaximumLongitude) {
    return null;
  }

  final acChargers = _asCount(attributes['type_ac']);
  final dcChargers = _asCount(attributes['type_dc']);
  final existingChargers =
      _asCount(attributes['number_of_existing_ev_charger_s']);
  final proposedChargers =
      _asCount(attributes['number_of_proposed_ev_charger__']);

  final name = attributes['location']?.toString().trim() ?? '';

  return ChargingStation(
    id: mevnetStationId(objectId),
    name: name.isEmpty ? 'Charging station' : name,
    latitude: latitude,
    longitude: longitude,
    chargerType: mevnetChargerType(
      acChargerCount: acChargers,
      dcChargerCount: dcChargers,
    ),
    address: null,
    chargerCount: isExisting ? existingChargers : 0,
    acChargerCount: isExisting ? acChargers : 0,
    dcChargerCount: isExisting ? dcChargers : 0,
    proposedChargerCount: isNewlyProposed ? proposedChargers : 0,
    mevnetObjectId: objectId,
    source: mevnetSourceName,
    sourceUrl: mevnetLayerUrl,
    dataDate: mevnetDataDate(attributes['data_as']),
    importedAt: importedAt,
    state: mevnetStateName(attributes['state']),
    pbt: _nullIfBlank(attributes['pbt']),
    category: _nullIfBlank(attributes['category']),
    status: status,
    indoorOutdoor: _nullIfBlank(attributes['indoor___outdoor']),
  );
}

@visibleForTesting
String mevnetStationId(int objectId) =>
    '6d65766e-6574-5000-8000-${objectId.toRadixString(16).padLeft(12, '0')}';

@visibleForTesting
String mevnetChargerType({
  required int acChargerCount,
  required int dcChargerCount,
}) {
  if (acChargerCount > 0 && dcChargerCount > 0) return 'AC & DC Charger';
  if (dcChargerCount > 0) return 'DC Fast Charger';
  if (acChargerCount > 0) return 'AC Charger';
  return 'Charger type not specified';
}

@visibleForTesting
String? mevnetStateName(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return mevnetStateNames[raw.toUpperCase()] ?? raw;
}

@visibleForTesting
DateTime? mevnetDataDate(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final parts = raw.split('-');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = _monthNumbers[parts[1].toLowerCase()];
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (day < 1 || day > 31 || year < 0 || year > 99) return null;
  return DateTime.utc(2000 + year, month, day);
}

int? _asInteger(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

int _asCount(Object? value) {
  final parsed = _asInteger(value);
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}

String? _nullIfBlank(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
