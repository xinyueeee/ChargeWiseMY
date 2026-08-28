import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/proposal.dart';
import 'mevnet_http_client.dart';

/// Selects the remote source for public charging infrastructure.
///
/// `true`  : official PLANMalaysia MEVnet ArcGIS REST API.
/// `false` : the previous `public.charging_stations` Supabase loader.
///
/// This is a developer rollback switch only. The application never flips it at
/// runtime and never falls back from the API to Supabase silently; a failed
/// remote refresh keeps serving the SQLite cache exactly as before.
const bool useMevnetApi = true;

/// Official PLANMalaysia MEVnet EV charging layer. Anonymous, read-only
/// (`capabilities: Query`), ArcGIS Server 10.91.
const String mevnetLayerUrl =
    'https://gisdev.planmalaysia.gov.my/server/rest/services/Hosted/'
    'MEVnet_EVCB/FeatureServer/0';

const String mevnetSourceName = 'MEVnet / PLANMalaysia';

/// `maxRecordCount` published by the layer. Paging never requests more.
const int mevnetPageSize = 1000;

/// Only the attributes that map onto [ChargingStation] are requested. The
/// layer also publishes 27 per-network columns plus unused survey columns;
/// `outFields=*` costs roughly 6.9 MB per full pull against 1.6 MB here.
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

/// Malaysia bounding box used by the reviewed production import. Keeping it
/// here preserves parity with `public.charging_stations`, whose rows were
/// inserted under `where coordinate_valid`.
const double mevnetMinimumLatitude = 0.5;
const double mevnetMaximumLatitude = 7.6;
const double mevnetMinimumLongitude = 99.5;
const double mevnetMaximumLongitude = 120.0;

/// MEVnet publishes state names in upper case with `W.P.` prefixes. The app
/// and the GeoJSON state boundaries use these display names.
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

/// Raised when the MEVnet service is reachable but does not return a usable
/// feature page. The sync coordinator treats this like any other remote
/// failure: the SQLite snapshot stays active.
class MEVnetApiException implements Exception {
  const MEVnetApiException(this.message);

  final String message;

  @override
  String toString() => 'MEVnetApiException: $message';
}

/// Reads public charging infrastructure from the official PLANMalaysia MEVnet
/// ArcGIS REST FeatureServer.
///
/// The service is anonymous and query-only, so Flutter calls it directly; no
/// key is held and nothing can be written back. Supabase remains responsible
/// for authentication, proposals, reactions, admin decisions and photos.
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

  /// Supplied by tests. When null the MEVnet-scoped TLS client is built lazily
  /// on the first request, because loading the bundled trust anchor is async.
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
      // Do not cache a failed build; a later refresh may succeed.
      _pendingClient = null;
      rethrow;
    }
  }

  /// Returns every valid MEVnet location for [status], filtered server-side.
  ///
  /// [status] must be one of the two canonical MEVnet values so that no caller
  /// can inject a `where` clause.
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
      // An empty page always terminates the loop, so paging cannot spin.
      if (page.features.isEmpty) break;
      offset += page.features.length;
      // ArcGIS may return fewer rows than requested while more remain, so a
      // short page only ends paging when the server also stops advertising a
      // transfer limit. Advancing by the received count keeps offsets exact.
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
    // ArcGIS reports query errors inside an HTTP 200 body.
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

/// Converts one ArcGIS attribute row into the existing [ChargingStation]
/// model, reproducing the reviewed production import exactly.
///
/// Returns `null` when the row must be excluded: an unusable `objectid`, a
/// status outside the two canonical MEVnet values, or a coordinate that fails
/// either [CoordinateParser] or the Malaysia bounding box.
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

  // Charger type is derived from the published AC/DC columns before the
  // status-based zeroing below, matching the production import.
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
    // MEVnet publishes no verified postal address. A fabricated address is
    // never presented; PBT and state remain in their own fields.
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

/// Stable station identifier shared with `public.charging_stations`.
///
/// `saved_stations` and `charging_sessions` reference these values, so the
/// derivation must stay byte-identical to the reviewed production import: a
/// fixed UUID namespace whose final 12 hex digits encode the MEVnet OBJECTID.
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

/// Parses the MEVnet `data_as` survey date, published as `d-MMM-yy`.
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

/// MEVnet leaves count columns null rather than zero. The production table
/// stores those as `0`, so the model must too.
int _asCount(Object? value) {
  final parsed = _asInteger(value);
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}

String? _nullIfBlank(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
