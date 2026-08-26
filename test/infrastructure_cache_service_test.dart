import 'dart:async';

import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/infrastructure_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cachedAt = DateTime.utc(2026, 8, 23, 10);
  final refreshedAt = DateTime.utc(2026, 8, 24, 10);

  test('empty cache uses complete remote infrastructure and writes cache',
      () async {
    final cache = _MemoryInfrastructureCache();
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      clock: () => refreshedAt,
      remoteLoader: (status) async => status == ChargingStation.statusExisting
          ? [_station('existing-1', status: status)]
          : [_station('planned-1', status: status, proposedCount: 3)],
    );

    final updates = await coordinator.synchronize().toList();

    expect(
      updates.map((update) => update.phase),
      [
        InfrastructureLoadPhase.remoteExistingReady,
        InfrastructureLoadPhase.remoteFresh,
      ],
    );
    expect(updates.last.snapshot!.stations, hasLength(2));
    expect(cache.replaceCalls, 1);
    expect(cache.snapshot!.stations, hasLength(2));
  });

  test('cache is emitted before a slow remote request completes', () async {
    final cache = _MemoryInfrastructureCache(
      InfrastructureCacheSnapshot(
        stations: [
          _station('cached-existing', status: ChargingStation.statusExisting),
          _station(
            'cached-planned',
            status: ChargingStation.statusNewlyProposed,
            proposedCount: 2,
          ),
        ],
        cachedAt: cachedAt,
      ),
    );
    final existingCompleter = Completer<List<ChargingStation>>();
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      clock: () => refreshedAt,
      remoteLoader: (status) {
        if (status == ChargingStation.statusExisting) {
          return existingCompleter.future;
        }
        return Future.value([
          _station(
            'fresh-planned',
            status: status,
            proposedCount: 4,
          ),
        ]);
      },
    );
    final iterator = StreamIterator(coordinator.synchronize());

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.phase, InfrastructureLoadPhase.cacheReady);
    expect(iterator.current.snapshot!.existingStations, hasLength(1));

    var remotePublished = false;
    final pendingRemote = iterator.moveNext().then((value) {
      remotePublished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(remotePublished, isFalse);

    existingCompleter.complete([
      _station('fresh-existing', status: ChargingStation.statusExisting),
    ]);
    expect(await pendingRemote, isTrue);
    expect(
      iterator.current.phase,
      InfrastructureLoadPhase.remoteExistingReady,
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.phase, InfrastructureLoadPhase.remoteFresh);
    await iterator.cancel();
  });

  test('remote success replaces a different cache atomically', () async {
    final cache = _MemoryInfrastructureCache(
      InfrastructureCacheSnapshot(
        stations: [
          _station('old', status: ChargingStation.statusExisting),
        ],
        cachedAt: cachedAt,
      ),
    );
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      clock: () => refreshedAt,
      remoteLoader: (status) async => status == ChargingStation.statusExisting
          ? [_station('new', status: status)]
          : const <ChargingStation>[],
    );

    await coordinator.synchronize().drain<void>();

    expect(cache.replaceCalls, 1);
    expect(cache.snapshot!.stations.single.id, 'new');
    expect(cache.snapshot!.cachedAt, refreshedAt);
  });

  test('remote failure keeps a usable cache', () async {
    final original = InfrastructureCacheSnapshot(
      stations: [
        _station('cached', status: ChargingStation.statusExisting),
      ],
      cachedAt: cachedAt,
    );
    final cache = _MemoryInfrastructureCache(original);
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      remoteLoader: (_) async => throw StateError('offline'),
    );

    final updates = await coordinator.synchronize().toList();

    expect(updates.last.phase, InfrastructureLoadPhase.remoteFailed);
    expect(updates.last.hasUsableInfrastructure, isTrue);
    expect(updates.last.snapshot, same(original));
    expect(cache.replaceCalls, 0);
  });

  test('remote failure without cache reports complete failure', () async {
    final cache = _MemoryInfrastructureCache();
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      remoteLoader: (_) async => throw StateError('offline'),
    );

    final updates = await coordinator.synchronize().toList();

    expect(updates, hasLength(1));
    expect(updates.single.phase, InfrastructureLoadPhase.remoteFailed);
    expect(updates.single.hasUsableInfrastructure, isFalse);
    expect(updates.single.error, isA<StateError>());
  });

  test('cache read failure falls back to fresh remote data', () async {
    final cache = _MemoryInfrastructureCache()
      ..readError = StateError('cache unavailable');
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      clock: () => refreshedAt,
      remoteLoader: (status) async => status == ChargingStation.statusExisting
          ? [_station('existing', status: status)]
          : const <ChargingStation>[],
    );

    final updates = await coordinator.synchronize().toList();

    expect(updates.last.phase, InfrastructureLoadPhase.remoteFresh);
    expect(updates.last.hasUsableInfrastructure, isTrue);
    expect(cache.replaceCalls, 1);
  });

  test('cache write failure does not discard fresh remote data', () async {
    final cache = _MemoryInfrastructureCache()
      ..writeError = StateError('disk full');
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      clock: () => refreshedAt,
      remoteLoader: (status) async => status == ChargingStation.statusExisting
          ? [_station('existing', status: status)]
          : const <ChargingStation>[],
    );

    final updates = await coordinator.synchronize().toList();

    expect(updates.last.phase, InfrastructureLoadPhase.remoteFresh);
    expect(updates.last.cacheWriteFailed, isTrue);
    expect(updates.last.snapshot!.existingStations, hasLength(1));
  });

  test('cache partitions Existing and Newly Proposed without duplication', () {
    final snapshot = InfrastructureCacheSnapshot(
      stations: [
        _station('existing', status: ChargingStation.statusExisting),
        _station(
          'proposed',
          status: ChargingStation.statusNewlyProposed,
          proposedCount: 8,
        ),
      ],
      cachedAt: cachedAt,
    );

    expect(snapshot.stations, hasLength(2));
    expect(snapshot.existingStations.single.id, 'existing');
    expect(snapshot.proposedStations.single.id, 'proposed');
    expect(snapshot.proposedStations.single.proposedChargerCount, 8);
  });

  test('cache serialization preserves nullable numeric and date fields', () {
    final station = ChargingStation(
      id: 'station-1',
      name: 'MEVnet location',
      latitude: 3.123456,
      longitude: 101.654321,
      chargerType: 'AC + DC',
      chargerCount: 5,
      acChargerCount: 3,
      dcChargerCount: 2,
      proposedChargerCount: 0,
      mevnetObjectId: 42,
      dataDate: DateTime.utc(2024, 8, 31),
      importedAt: DateTime.utc(2026, 8, 1, 12, 30),
      state: 'Selangor',
      pbt: 'Petaling Jaya',
      category: 'Commercial',
      status: ChargingStation.statusExisting,
    );

    final saved = station.toCacheMap(cachedAt: cachedAt);
    final restored = ChargingStation.fromCacheMap(saved);

    expect(restored, isNotNull);
    expect(restored!.hasSameRuntimeDataAs(station), isTrue);
    expect(restored.address, isNull);
    expect(saved['cached_at'], cachedAt.toIso8601String());
  });

  test('cache equality detects metadata changes at unchanged coordinates', () {
    final first = InfrastructureCacheSnapshot(
      stations: [
        _station('same-id', status: ChargingStation.statusExisting, count: 2),
      ],
      cachedAt: cachedAt,
    );
    final changed = InfrastructureCacheSnapshot(
      stations: [
        _station('same-id', status: ChargingStation.statusExisting, count: 3),
      ],
      cachedAt: refreshedAt,
    );

    expect(first.hasSameStationDataAs(changed), isFalse);
  });

  test('unchanged refresh touches freshness without duplicating rows',
      () async {
    final originalStations = [
      _station('one', status: ChargingStation.statusExisting),
      _station(
        'two',
        status: ChargingStation.statusNewlyProposed,
        proposedCount: 7,
      ),
    ];
    final cache = _MemoryInfrastructureCache(
      InfrastructureCacheSnapshot(
        stations: originalStations,
        cachedAt: cachedAt,
      ),
    );
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      clock: () => refreshedAt,
      remoteLoader: (status) async => originalStations
          .where((station) => station.status == status)
          .toList(),
    );

    await coordinator.synchronize().drain<void>();

    expect(cache.replaceCalls, 0);
    expect(cache.touchCalls, 1);
    expect(cache.snapshot!.stations.map((station) => station.id).toSet(),
        {'one', 'two'});
    expect(cache.snapshot!.stations, hasLength(2));
  });

  test('proposed refresh failure never replaces a complete good cache',
      () async {
    final cache = _MemoryInfrastructureCache(
      InfrastructureCacheSnapshot(
        stations: [
          _station('old-existing', status: ChargingStation.statusExisting),
          _station(
            'old-proposed',
            status: ChargingStation.statusNewlyProposed,
            proposedCount: 2,
          ),
        ],
        cachedAt: cachedAt,
      ),
    );
    final coordinator = InfrastructureSyncCoordinator(
      cache: cache,
      remoteLoader: (status) async {
        if (status == ChargingStation.statusExisting) {
          return [
            _station('fresh-existing', status: status),
          ];
        }
        throw StateError('second page group failed');
      },
    );

    final updates = await coordinator.synchronize().toList();

    expect(updates.last.phase, InfrastructureLoadPhase.remoteFailed);
    expect(updates.last.snapshot!.existingStations.single.id, 'fresh-existing');
    expect(updates.last.snapshot!.proposedStations.single.id, 'old-proposed');
    expect(cache.replaceCalls, 0);
    expect(cache.snapshot!.stations.first.id, 'old-existing');
  });

  test('coverage source remains physical Existing locations only', () {
    final snapshot = InfrastructureCacheSnapshot(
      stations: [
        _station('physical-site', status: ChargingStation.statusExisting),
        _station(
          'future-site',
          status: ChargingStation.statusNewlyProposed,
          proposedCount: 20,
        ),
      ],
      cachedAt: cachedAt,
    );

    final coverageInput = snapshot.existingStations;

    expect(coverageInput, hasLength(1));
    expect(coverageInput.single.id, 'physical-site');
    expect(
      coverageInput.any(
        (station) => station.status == ChargingStation.statusNewlyProposed,
      ),
      isFalse,
    );
  });

  test('cache freshness is advisory and does not hide old data', () {
    final snapshot = InfrastructureCacheSnapshot(
      stations: [
        _station('cached', status: ChargingStation.statusExisting),
      ],
      cachedAt: cachedAt,
    );

    expect(
        snapshot.isStaleAt(cachedAt.add(const Duration(hours: 23))), isFalse);
    expect(snapshot.isStaleAt(cachedAt.add(const Duration(hours: 25))), isTrue);
    expect(snapshot.existingStations, isNotEmpty);
  });
}

ChargingStation _station(
  String id, {
  required String status,
  int count = 1,
  int proposedCount = 0,
}) =>
    ChargingStation(
      id: id,
      name: 'Station $id',
      latitude: 3.1 + id.length / 1000,
      longitude: 101.6 + id.length / 1000,
      chargerType:
          status == ChargingStation.statusExisting ? 'AC' : 'MEVnet Proposed',
      chargerCount: status == ChargingStation.statusExisting ? count : 0,
      acChargerCount: status == ChargingStation.statusExisting ? count : 0,
      dcChargerCount: 0,
      proposedChargerCount: proposedCount,
      state: 'Selangor',
      status: status,
    );

class _MemoryInfrastructureCache implements InfrastructureCacheStore {
  _MemoryInfrastructureCache([this.snapshot]);

  InfrastructureCacheSnapshot? snapshot;
  int replaceCalls = 0;
  int touchCalls = 0;
  Object? readError;
  Object? writeError;

  @override
  Future<InfrastructureCacheSnapshot?> readStations() async {
    final error = readError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<void> replaceStations(
    List<ChargingStation> stations, {
    required DateTime cachedAt,
  }) async {
    final error = writeError;
    if (error != null) throw error;
    replaceCalls++;
    snapshot = InfrastructureCacheSnapshot(
      stations: stations,
      cachedAt: cachedAt,
    );
  }

  @override
  Future<void> updateCachedAt(DateTime cachedAt) async {
    touchCalls++;
    final current = snapshot;
    if (current != null) {
      snapshot = InfrastructureCacheSnapshot(
        stations: current.stations,
        cachedAt: cachedAt,
      );
    }
  }

  @override
  Future<void> clearInfrastructureCache() async => snapshot = null;
}
