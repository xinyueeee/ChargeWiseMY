import 'dart:convert';
import 'dart:io';

import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/mevnet_api_service.dart';
import 'package:chargewise_my/modules/planning/services/mevnet_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Unmodified ArcGIS attribute rows captured from the official MEVnet layer.
/// A record-by-record comparison against the live FeatureServer on
/// 2026-08-28 found zero attribute differences across all 4,477 records, so
/// this fixture exercises the mapper against real source data offline.
const String mevnetRawFixture = 'tools/mevnet/staging/mevnet_raw.json';

const String fakeLayerUrl = 'https://example.test/FeatureServer/0';

final DateTime importedAt = DateTime.utc(2026, 8, 28, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> rawRows;

  setUpAll(() async {
    final source = await File(mevnetRawFixture).readAsString();
    rawRows = (jsonDecode(source) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  });

  group('station identity', () {
    test('reproduces the production deterministic UUID scheme', () {
      // saved_stations and charging_sessions reference these identifiers.
      // Changing the derivation would orphan every saved station.
      expect(mevnetStationId(1), '6d65766e-6574-5000-8000-000000000001');
      expect(mevnetStationId(4477), '6d65766e-6574-5000-8000-00000000117d');
      expect(mevnetStationId(255), '6d65766e-6574-5000-8000-0000000000ff');
    });

    test('every mapped station id is unique across the whole dataset', () {
      final ids = <String>{};
      for (final row in rawRows) {
        final station = mapMevnetAttributes(row, importedAt: importedAt);
        if (station != null) expect(ids.add(station.id), isTrue);
      }
      expect(ids, hasLength(4474));
    });
  });

  group('attribute mapping', () {
    test('derives charger type from the published AC and DC columns', () {
      expect(
        mevnetChargerType(acChargerCount: 2, dcChargerCount: 1),
        'AC & DC Charger',
      );
      expect(
        mevnetChargerType(acChargerCount: 0, dcChargerCount: 2),
        'DC Fast Charger',
      );
      expect(
        mevnetChargerType(acChargerCount: 3, dcChargerCount: 0),
        'AC Charger',
      );
      expect(
        mevnetChargerType(acChargerCount: 0, dcChargerCount: 0),
        'Charger type not specified',
      );
    });

    test('normalises the 16 published MEVnet state names', () {
      expect(mevnetStateName('W.P. KUALA LUMPUR'), 'Kuala Lumpur');
      expect(mevnetStateName('W.P. LABUAN'), 'Labuan');
      expect(mevnetStateName('W.P. PUTRAJAYA'), 'Putrajaya');
      expect(mevnetStateName('PULAU PINANG'), 'Penang');
      expect(mevnetStateName('SELANGOR'), 'Selangor');
      expect(mevnetStateName('  '), isNull);
      // An unmapped future value is passed through, never silently dropped.
      expect(mevnetStateName('NEW STATE'), 'NEW STATE');
    });

    test('parses the d-MMM-yy survey date', () {
      expect(mevnetDataDate('6-Mar-23'), DateTime.utc(2023, 3, 6));
      expect(mevnetDataDate('20-May-25'), DateTime.utc(2025, 5, 20));
      expect(mevnetDataDate('31-Dec-24'), DateTime.utc(2024, 12, 31));
      expect(mevnetDataDate(null), isNull);
      expect(mevnetDataDate('not-a-date'), isNull);
    });

    test('every fixture data_as value parses', () {
      for (final row in rawRows) {
        expect(
          mevnetDataDate(row['data_as']),
          isNotNull,
          reason: 'objectid ${row['objectid']} has data_as ${row['data_as']}',
        );
      }
    });

    test('Existing rows carry installed counts and zero proposed counts', () {
      final station = mapMevnetAttributes(
        <String, dynamic>{
          'objectid': 1,
          'location': '  AEON MALL TAIPING  ',
          'latitude': 4.8731511,
          'longitude': 100.7308056,
          'state': 'PERAK',
          'pbt': 'Majlis Perbandaran Taiping',
          'category': 'Shopping Mall',
          'status': 'Existing',
          'indoor___outdoor': 'Outdoor',
          'type_ac': null,
          'type_dc': 2,
          'number_of_existing_ev_charger_s': 2,
          // Existing rows also publish planned chargers; production discards
          // them so Existing markers never advertise future capacity.
          'number_of_proposed_ev_charger__': 4,
          'data_as': '31-Aug-24',
        },
        importedAt: importedAt,
      );

      expect(station, isNotNull);
      expect(station!.id, '6d65766e-6574-5000-8000-000000000001');
      expect(station.name, 'AEON MALL TAIPING');
      expect(station.status, ChargingStation.statusExisting);
      expect(station.chargerType, 'DC Fast Charger');
      expect(station.chargerCount, 2);
      expect(station.acChargerCount, 0);
      expect(station.dcChargerCount, 2);
      expect(station.proposedChargerCount, 0);
      expect(station.state, 'Perak');
      expect(station.category, 'Shopping Mall');
      expect(station.indoorOutdoor, 'Outdoor');
      expect(station.mevnetObjectId, 1);
      expect(station.source, 'MEVnet / PLANMalaysia');
      expect(station.sourceUrl, mevnetLayerUrl);
      expect(station.dataDate, DateTime.utc(2024, 8, 31));
      expect(station.importedAt, importedAt);
      // MEVnet publishes no verified postal address.
      expect(station.address, isNull);
    });

    test('Newly Proposed rows carry proposed counts and zero installed', () {
      final station = mapMevnetAttributes(
        <String, dynamic>{
          'objectid': 4477,
          'location': 'PROPOSED SITE',
          'latitude': 5.2831,
          'longitude': 115.2308,
          'state': 'W.P. LABUAN',
          'pbt': '',
          'category': null,
          'status': 'Newly Proposed',
          'indoor___outdoor': null,
          'type_ac': null,
          'type_dc': null,
          'number_of_existing_ev_charger_s': 0,
          'number_of_proposed_ev_charger__': 3,
          'data_as': '6-Mar-23',
        },
        importedAt: importedAt,
      );

      expect(station, isNotNull);
      expect(station!.status, ChargingStation.statusNewlyProposed);
      expect(station.chargerCount, 0);
      expect(station.acChargerCount, 0);
      expect(station.dcChargerCount, 0);
      expect(station.proposedChargerCount, 3);
      expect(station.chargerType, 'Charger type not specified');
      expect(station.state, 'Labuan');
      expect(station.pbt, isNull);
      expect(station.category, isNull);
      expect(station.indoorOutdoor, isNull);
    });
  });

  group('row exclusion', () {
    Map<String, dynamic> row(Map<String, dynamic> overrides) => <String, dynamic>{
          'objectid': 10,
          'location': 'SITE',
          'latitude': 3.1,
          'longitude': 101.6,
          'state': 'SELANGOR',
          'status': 'Existing',
          'number_of_existing_ev_charger_s': 1,
          'number_of_proposed_ev_charger__': 0,
          'type_ac': 1,
          'type_dc': 0,
          'data_as': '6-Mar-23',
          ...overrides,
        };

    test('drops null coordinates', () {
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'latitude': null, 'longitude': null}),
          importedAt: importedAt,
        ),
        isNull,
      );
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'longitude': null}),
          importedAt: importedAt,
        ),
        isNull,
      );
    });

    test('drops coordinates outside Malaysia', () {
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'latitude': 51.5, 'longitude': -0.12}),
          importedAt: importedAt,
        ),
        isNull,
      );
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'latitude': 0.0}),
          importedAt: importedAt,
        ),
        isNull,
      );
    });

    test('drops rows outside the two canonical MEVnet statuses', () {
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'status': 'Decommissioned'}),
          importedAt: importedAt,
        ),
        isNull,
      );
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'status': ''}),
          importedAt: importedAt,
        ),
        isNull,
      );
    });

    test('drops rows without a usable objectid', () {
      expect(
        mapMevnetAttributes(
          row(<String, dynamic>{'objectid': null}),
          importedAt: importedAt,
        ),
        isNull,
      );
    });

    test('excludes exactly the three known invalid-coordinate rows', () {
      final excluded = rawRows
          .where((r) => mapMevnetAttributes(r, importedAt: importedAt) == null)
          .map((r) => r['objectid'])
          .toList(growable: false);
      expect(excluded, <int>[4034, 4176, 4177]);
    });
  });

  group('dataset totals match the reviewed MEVnet baseline', () {
    late List<ChargingStation> existing;
    late List<ChargingStation> proposed;

    setUpAll(() {
      final stations = rawRows
          .map((row) => mapMevnetAttributes(row, importedAt: importedAt))
          .whereType<ChargingStation>()
          .toList(growable: false);
      existing = stations
          .where((s) => s.status == ChargingStation.statusExisting)
          .toList(growable: false);
      proposed = stations
          .where((s) => s.status == ChargingStation.statusNewlyProposed)
          .toList(growable: false);
      expect(stations, hasLength(4474));
    });

    test('Existing = 1374 locations', () => expect(existing, hasLength(1374)));

    test('Newly Proposed = 3100 locations',
        () => expect(proposed, hasLength(3100)));

    test('Existing EVCB = 4161', () {
      expect(
        existing.fold<int>(0, (sum, s) => sum + (s.chargerCount ?? 0)),
        4161,
      );
    });

    test('AC = 2857', () {
      expect(
        existing.fold<int>(0, (sum, s) => sum + (s.acChargerCount ?? 0)),
        2857,
      );
    });

    test('DC = 1304', () {
      expect(
        existing.fold<int>(0, (sum, s) => sum + (s.dcChargerCount ?? 0)),
        1304,
      );
    });

    test('Proposed EVCB = 8266', () {
      expect(
        proposed.fold<int>(0, (sum, s) => sum + s.proposedChargerCount),
        8266,
      );
    });

    test('Existing locations never advertise proposed chargers', () {
      expect(
        existing.every((s) => s.proposedChargerCount == 0),
        isTrue,
      );
    });

    test('Newly Proposed locations never contribute installed capacity', () {
      expect(
        proposed.every((s) =>
            (s.chargerCount ?? 0) == 0 &&
            (s.acChargerCount ?? 0) == 0 &&
            (s.dcChargerCount ?? 0) == 0),
        isTrue,
      );
    });

    test('Labuan = 0 Existing / 17 Proposed / 50 Proposed EVCB', () {
      expect(existing.where((s) => s.state == 'Labuan'), isEmpty);
      final labuanProposed =
          proposed.where((s) => s.state == 'Labuan').toList(growable: false);
      expect(labuanProposed, hasLength(17));
      expect(
        labuanProposed.fold<int>(0, (sum, s) => sum + s.proposedChargerCount),
        50,
      );
    });
  });

  group('MEVnetApiService request shape and pagination', () {
    late List<Uri> requests;

    /// Serves the real fixture the way the ArcGIS FeatureServer does:
    /// server-side `status` filtering plus `resultOffset` / `resultRecordCount`
    /// paging over an `objectid ASC` ordering.
    MockClient fakeLayer(List<Map<String, dynamic>> rows, {int? cap}) {
      return MockClient((request) async {
        requests.add(request.url);
        final query = request.url.queryParameters;
        final where = query['where']!;
        final status = where.substring(
          where.indexOf("'") + 1,
          where.lastIndexOf("'"),
        );
        final offset = int.parse(query['resultOffset']!);
        final count = int.parse(query['resultRecordCount']!);
        final matching = rows
            .where((row) => row['status'] == status)
            .toList(growable: false)
          ..sort((a, b) => (a['objectid'] as int).compareTo(b['objectid'] as int));
        final pageSize = cap == null ? count : (count < cap ? count : cap);
        final page = matching.skip(offset).take(pageSize).toList();
        return http.Response(
          jsonEncode(<String, dynamic>{
            'features': page
                .map((attributes) => <String, dynamic>{'attributes': attributes})
                .toList(),
            'exceededTransferLimit': offset + page.length < matching.length,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
    }

    setUp(() => requests = <Uri>[]);

    test('sends the agreed lean request parameters', () async {
      final service = MEVnetApiService(
        httpClient: fakeLayer(rawRows),
        layerUrl: fakeLayerUrl,
        clock: () => importedAt,
      );

      await service.getStations(status: ChargingStation.statusExisting);

      final first = requests.first;
      expect(first.path, endsWith('/FeatureServer/0/query'));
      final query = first.queryParameters;
      expect(query['f'], 'json');
      expect(query['where'], "status='Existing'");
      expect(query['returnGeometry'], 'false');
      expect(query['orderByFields'], 'objectid ASC');
      expect(query['resultRecordCount'], '1000');
      expect(query['resultOffset'], '0');
      // Lean field list only; outFields=* would cost roughly 4x the payload.
      expect(query['outFields'], mevnetRequestedFields.join(','));
      expect(query['outFields'], isNot(contains('*')));
      expect(query['outFields'], isNot(contains('number_of_ev_charger_by')));
    });

    test('pages until a short page and returns the full Existing set',
        () async {
      final service = MEVnetApiService(
        httpClient: fakeLayer(rawRows),
        layerUrl: fakeLayerUrl,
        clock: () => importedAt,
      );

      final stations =
          await service.getStations(status: ChargingStation.statusExisting);

      expect(stations, hasLength(1374));
      expect(
        stations.every((s) => s.status == ChargingStation.statusExisting),
        isTrue,
      );
      // 1374 rows at 1000 per page: a full page then a short page.
      expect(requests, hasLength(2));
      expect(requests[0].queryParameters['resultOffset'], '0');
      expect(requests[1].queryParameters['resultOffset'], '1000');
    });

    test('pages the Newly Proposed set and drops the invalid rows', () async {
      final service = MEVnetApiService(
        httpClient: fakeLayer(rawRows),
        layerUrl: fakeLayerUrl,
        clock: () => importedAt,
      );

      final stations =
          await service.getStations(status: ChargingStation.statusNewlyProposed);

      // 3103 published rows, 3 with null coordinates.
      expect(stations, hasLength(3100));
      expect(
        stations.fold<int>(0, (sum, s) => sum + s.proposedChargerCount),
        8266,
      );
      expect(requests, hasLength(4));
    });

    test('offset paging stays correct when the server caps a page short',
        () async {
      // ArcGIS may return fewer rows than requested; the loop must advance by
      // what it received, not by what it asked for.
      final service = MEVnetApiService(
        httpClient: fakeLayer(rawRows, cap: 300),
        layerUrl: fakeLayerUrl,
        clock: () => importedAt,
      );

      final stations =
          await service.getStations(status: ChargingStation.statusExisting);

      expect(stations, hasLength(1374));
      expect(stations.map((s) => s.id).toSet(), hasLength(1374));
      // 300 per page: four full pages then a 174-row page.
      expect(requests, hasLength(5));
      expect(requests.last.queryParameters['resultOffset'], '1200');
    });

    test('rejects any status outside the two canonical MEVnet values',
        () async {
      final service = MEVnetApiService(
        httpClient: fakeLayer(rawRows),
        layerUrl: fakeLayerUrl,
      );

      // Guards the interpolated `where` clause against injection.
      expect(
        () => service.getStations(status: "Existing' or '1'='1"),
        throwsArgumentError,
      );
      expect(() => service.getStations(status: 'Approved'), throwsArgumentError);
      expect(requests, isEmpty);
    });
  });

  group('MEVnetApiService failure handling', () {
    test('throws on a non-200 response', () async {
      final service = MEVnetApiService(
        httpClient: MockClient((_) async => http.Response('down', 503)),
        layerUrl: fakeLayerUrl,
      );

      expect(
        () => service.getStations(status: ChargingStation.statusExisting),
        throwsA(isA<MEVnetApiException>()),
      );
    });

    test('throws on an ArcGIS error delivered inside an HTTP 200 body',
        () async {
      final service = MEVnetApiService(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{'code': 400, 'message': 'Invalid URL'},
            }),
            200,
          ),
        ),
        layerUrl: fakeLayerUrl,
      );

      expect(
        () => service.getStations(status: ChargingStation.statusExisting),
        throwsA(isA<MEVnetApiException>()),
      );
    });

    test('throws on a malformed payload rather than returning empty data',
        () async {
      final service = MEVnetApiService(
        httpClient: MockClient((_) async => http.Response('<html>', 200)),
        layerUrl: fakeLayerUrl,
      );

      // An empty Existing result would be rejected by the sync coordinator
      // anyway; failing loudly keeps the SQLite snapshot in place.
      expect(
        () => service.getStations(status: ChargingStation.statusExisting),
        throwsA(isA<MEVnetApiException>()),
      );
    });
  });

  group('TLS client wiring', () {
    test('builds its client from the factory when none is injected', () async {
      var factoryCalls = 0;
      final service = MEVnetApiService(
        layerUrl: fakeLayerUrl,
        clock: () => importedAt,
        clientFactory: () async {
          factoryCalls++;
          return MockClient(
            (_) async => http.Response(
              jsonEncode(<String, dynamic>{'features': <dynamic>[]}),
              200,
            ),
          );
        },
      );

      await service.getStations(status: ChargingStation.statusNewlyProposed);

      expect(factoryCalls, 1);
    });

    test('reuses one client across the pages of a request', () async {
      var factoryCalls = 0;
      final service = MEVnetApiService(
        layerUrl: fakeLayerUrl,
        pageSize: 2,
        clock: () => importedAt,
        clientFactory: () async {
          factoryCalls++;
          var call = 0;
          return MockClient((_) async {
            call++;
            // Two full pages then a short page: three requests, one client.
            final rows = call <= 2 ? 2 : 1;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'features': List<Map<String, dynamic>>.generate(
                  rows,
                  (index) => <String, dynamic>{
                    'attributes': <String, dynamic>{
                      'objectid': call * 10 + index,
                      'location': 'SITE',
                      'latitude': 3.1,
                      'longitude': 101.6,
                      'state': 'SELANGOR',
                      'status': 'Existing',
                      'number_of_existing_ev_charger_s': 1,
                      'type_ac': 1,
                      'type_dc': 0,
                      'data_as': '6-Mar-23',
                    },
                  },
                ),
              }),
              200,
            );
          });
        },
      );

      final stations =
          await service.getStations(status: ChargingStation.statusExisting);

      expect(stations, hasLength(5));
      expect(factoryCalls, 1);
    });

    test('surfaces a trust-anchor failure instead of returning empty data',
        () async {
      final service = MEVnetApiService(
        layerUrl: fakeLayerUrl,
        clientFactory: () async =>
            throw const MEVnetTrustAnchorException('missing asset'),
      );

      // The sync coordinator turns this into remoteFailed, which keeps any
      // existing SQLite snapshot in place rather than wiping it.
      await expectLater(
        service.getStations(status: ChargingStation.statusExisting),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
    });

    test('does not cache a failed client build', () async {
      var attempts = 0;
      final service = MEVnetApiService(
        layerUrl: fakeLayerUrl,
        clock: () => importedAt,
        clientFactory: () async {
          attempts++;
          if (attempts == 1) {
            throw const MEVnetTrustAnchorException('transient');
          }
          return MockClient(
            (_) async => http.Response(
              jsonEncode(<String, dynamic>{'features': <dynamic>[]}),
              200,
            ),
          );
        },
      );

      await expectLater(
        service.getStations(status: ChargingStation.statusExisting),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
      // A later refresh must be able to recover.
      await service.getStations(status: ChargingStation.statusExisting);

      expect(attempts, 2);
    });
  });

  group('mapped stations round-trip through the SQLite cache', () {
    test('cache serialization preserves the API mapping', () {
      final station = mapMevnetAttributes(
        rawRows.firstWhere((row) => row['objectid'] == 1),
        importedAt: importedAt,
      )!;

      final restored = ChargingStation.fromCacheMap(
        station.toCacheMap(cachedAt: importedAt),
      );

      expect(restored, isNotNull);
      expect(restored!.hasSameRuntimeDataAs(station), isTrue);
    });
  });
}
