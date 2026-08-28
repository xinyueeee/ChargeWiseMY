import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/proposal.dart';

const infrastructureCacheDatabaseName = 'chargewise_cache.db';
const infrastructureCacheSchemaVersion = 1;
const infrastructureCacheTable = 'charging_stations_cache';
const infrastructureCacheFreshness = Duration(hours: 24);

/// A complete, internally consistent snapshot of public charging
/// infrastructure. One item is one physical MEVnet location, never one EVCB.
class InfrastructureCacheSnapshot {
  InfrastructureCacheSnapshot({
    required Iterable<ChargingStation> stations,
    required this.cachedAt,
  }) : stations = List<ChargingStation>.unmodifiable(
          List<ChargingStation>.of(stations)
            ..sort((a, b) => a.id.compareTo(b.id)),
        ) {
    existingStations = List<ChargingStation>.unmodifiable(
      this.stations.where(
            (station) => station.status == ChargingStation.statusExisting,
          ),
    );
    proposedStations = List<ChargingStation>.unmodifiable(
      this.stations.where(
            (station) => station.status == ChargingStation.statusNewlyProposed,
          ),
    );
  }

  final List<ChargingStation> stations;
  final DateTime cachedAt;
  late final List<ChargingStation> existingStations;
  late final List<ChargingStation> proposedStations;

  bool isStaleAt(DateTime now) =>
      now.toUtc().difference(cachedAt.toUtc()) > infrastructureCacheFreshness;

  bool hasSameStationDataAs(InfrastructureCacheSnapshot other) {
    if (stations.length != other.stations.length) return false;
    for (var index = 0; index < stations.length; index++) {
      if (!stations[index].hasSameRuntimeDataAs(other.stations[index])) {
        return false;
      }
    }
    return true;
  }
}

/// Storage boundary used by production SQLite and lightweight test fakes.
abstract interface class InfrastructureCacheStore {
  Future<InfrastructureCacheSnapshot?> readStations();

  Future<void> replaceStations(
    List<ChargingStation> stations, {
    required DateTime cachedAt,
  });

  Future<void> updateCachedAt(DateTime cachedAt);

  Future<void> clearInfrastructureCache();
}

class SqliteInfrastructureCacheService implements InfrastructureCacheStore {
  Future<Database>? _database;

  Future<Database> _openDatabase() {
    final existing = _database;
    if (existing != null) return existing;
    return _database = _open();
  }

  Future<Database> _open() async {
    final stopwatch = Stopwatch()..start();
    final database = await openDatabase(
      infrastructureCacheDatabaseName,
      version: infrastructureCacheSchemaVersion,
      onCreate: (db, version) => _createVersionOne(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        // Future schema versions must add explicit, non-destructive migrations
        // here. Version 1 never drops an existing cache during normal opening.
        if (oldVersion < 1) await _createVersionOne(db);
      },
    );
    stopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        'Infrastructure SQLite opened: '
        'database=$infrastructureCacheDatabaseName, '
        'version=$infrastructureCacheSchemaVersion, '
        'duration=${stopwatch.elapsedMilliseconds}ms.',
      );
    }
    return database;
  }

  Future<void> _createVersionOne(DatabaseExecutor db) => db.execute('''
    CREATE TABLE $infrastructureCacheTable (
      station_id TEXT PRIMARY KEY NOT NULL,
      station_name TEXT NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      charger_type TEXT NOT NULL,
      address TEXT,
      charger_count INTEGER,
      ac_charger_count INTEGER,
      dc_charger_count INTEGER,
      proposed_charger_count INTEGER NOT NULL DEFAULT 0,
      state TEXT,
      pbt TEXT,
      category TEXT,
      status TEXT,
      indoor_outdoor TEXT,
      mevnet_object_id INTEGER,
      source TEXT,
      source_url TEXT,
      data_date TEXT,
      imported_at TEXT,
      cached_at TEXT NOT NULL
    )
  ''');

  @override
  Future<InfrastructureCacheSnapshot?> readStations() async {
    final stopwatch = Stopwatch()..start();
    try {
      final database = await _openDatabase();
      final rows = await database.query(
        infrastructureCacheTable,
        orderBy: 'station_id ASC',
      );
      if (rows.isEmpty) {
        stopwatch.stop();
        if (kDebugMode) {
          debugPrint(
            'Infrastructure SQLite read: rows=0, '
            'duration=${stopwatch.elapsedMilliseconds}ms.',
          );
        }
        return null;
      }

      final stations = <ChargingStation>[];
      DateTime? oldestCachedAt;
      for (final row in rows) {
        final station = ChargingStation.fromCacheMap(row);
        final rowCachedAt = DateTime.tryParse('${row['cached_at'] ?? ''}');
        if (station == null || rowCachedAt == null) {
          throw const FormatException(
            'Infrastructure cache contains an invalid row.',
          );
        }
        stations.add(station);
        if (oldestCachedAt == null || rowCachedAt.isBefore(oldestCachedAt)) {
          oldestCachedAt = rowCachedAt;
        }
      }
      final snapshot = InfrastructureCacheSnapshot(
        stations: stations,
        cachedAt: oldestCachedAt!,
      );
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          'Infrastructure SQLite read: rows=${stations.length}, '
          'existing=${snapshot.existingStations.length}, '
          'proposed=${snapshot.proposedStations.length}, '
          'duration=${stopwatch.elapsedMilliseconds}ms.',
        );
      }
      return snapshot;
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          'Infrastructure SQLite read unavailable; using remote fallback: '
          'error=$error, duration=${stopwatch.elapsedMilliseconds}ms.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    }
  }

  @override
  Future<void> replaceStations(
    List<ChargingStation> stations, {
    required DateTime cachedAt,
  }) async {
    _validateCompleteSnapshot(stations);
    final stopwatch = Stopwatch()..start();
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete(infrastructureCacheTable);
      final batch = transaction.batch();
      for (final station in stations) {
        batch.insert(
          infrastructureCacheTable,
          station.toCacheMap(cachedAt: cachedAt),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await batch.commit(noResult: true, continueOnError: false);
    });
    stopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        'Infrastructure SQLite batch replaced: rows=${stations.length}, '
        'duration=${stopwatch.elapsedMilliseconds}ms.',
      );
    }
  }

  @override
  Future<void> updateCachedAt(DateTime cachedAt) async {
    final database = await _openDatabase();
    await database.update(
      infrastructureCacheTable,
      <String, Object?>{'cached_at': cachedAt.toUtc().toIso8601String()},
    );
  }

  @override
  Future<void> clearInfrastructureCache() async {
    final database = await _openDatabase();
    await database.delete(infrastructureCacheTable);
  }

  Future<void> close() async {
    final pending = _database;
    _database = null;
    if (pending != null) await (await pending).close();
  }
}

typedef InfrastructureRemoteLoader = Future<List<ChargingStation>> Function(
  String status,
);

enum InfrastructureLoadPhase {
  cacheReady,
  remoteExistingReady,
  remoteFresh,
  remoteFailed,
}

class InfrastructureLoadUpdate {
  const InfrastructureLoadUpdate({
    required this.phase,
    required this.snapshot,
    this.error,
    this.cacheWasStale = false,
    this.cacheWriteFailed = false,
  });

  final InfrastructureLoadPhase phase;
  final InfrastructureCacheSnapshot? snapshot;
  final Object? error;
  final bool cacheWasStale;
  final bool cacheWriteFailed;

  bool get hasUsableInfrastructure =>
      snapshot != null && snapshot!.existingStations.isNotEmpty;
}

/// Coordinates stale-while-revalidate loading. The data direction is strictly
/// remote source -> memory -> SQLite; cached rows are never written back to
/// the remote source. The source itself is injected, so this coordinator is
/// agnostic to whether it is the MEVnet API or the Supabase loader.
class InfrastructureSyncCoordinator {
  InfrastructureSyncCoordinator({
    required InfrastructureCacheStore cache,
    required InfrastructureRemoteLoader remoteLoader,
    DateTime Function()? clock,
  })  : _cache = cache,
        _remoteLoader = remoteLoader,
        _clock = clock ?? DateTime.now;

  final InfrastructureCacheStore _cache;
  final InfrastructureRemoteLoader _remoteLoader;
  final DateTime Function() _clock;

  Stream<InfrastructureLoadUpdate> synchronize() async* {
    InfrastructureCacheSnapshot? cached;
    try {
      cached = await _cache.readStations();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Infrastructure cache read failed safely: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    final cacheWasStale = cached?.isStaleAt(_clock()) ?? false;
    if (cached != null && cached.existingStations.isNotEmpty) {
      yield InfrastructureLoadUpdate(
        phase: InfrastructureLoadPhase.cacheReady,
        snapshot: cached,
        cacheWasStale: cacheWasStale,
      );
    }

    final remoteStopwatch = Stopwatch()..start();
    late final List<ChargingStation> remoteExisting;
    try {
      remoteExisting = await _remoteLoader(ChargingStation.statusExisting);
      _validateStatusPartition(
        remoteExisting,
        ChargingStation.statusExisting,
        requireNonEmpty: true,
      );
    } catch (error, stackTrace) {
      remoteStopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          'Infrastructure remote refresh failed before Existing completed: '
          'error=$error, duration=${remoteStopwatch.elapsedMilliseconds}ms.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      yield InfrastructureLoadUpdate(
        phase: InfrastructureLoadPhase.remoteFailed,
        snapshot: cached,
        error: error,
        cacheWasStale: cacheWasStale,
      );
      return;
    }

    final partialSnapshot = InfrastructureCacheSnapshot(
      stations: <ChargingStation>[
        ...remoteExisting,
        ...?cached?.proposedStations,
      ],
      cachedAt: cached?.cachedAt ?? _clock(),
    );
    yield InfrastructureLoadUpdate(
      phase: InfrastructureLoadPhase.remoteExistingReady,
      snapshot: partialSnapshot,
      cacheWasStale: cacheWasStale,
    );

    late final List<ChargingStation> remoteProposed;
    try {
      remoteProposed = await _remoteLoader(ChargingStation.statusNewlyProposed);
      _validateStatusPartition(
        remoteProposed,
        ChargingStation.statusNewlyProposed,
      );
      _validateCompleteSnapshot(<ChargingStation>[
        ...remoteExisting,
        ...remoteProposed,
      ]);
    } catch (error, stackTrace) {
      remoteStopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          'Infrastructure remote refresh failed before Proposed completed: '
          'error=$error, duration=${remoteStopwatch.elapsedMilliseconds}ms.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      yield InfrastructureLoadUpdate(
        phase: InfrastructureLoadPhase.remoteFailed,
        snapshot: partialSnapshot,
        error: error,
        cacheWasStale: cacheWasStale,
      );
      return;
    }

    final refreshedAt = _clock().toUtc();
    final remoteSnapshot = InfrastructureCacheSnapshot(
      stations: <ChargingStation>[
        ...remoteExisting,
        ...remoteProposed,
      ],
      cachedAt: refreshedAt,
    );
    var cacheWriteFailed = false;
    final writeStopwatch = Stopwatch()..start();
    try {
      if (cached != null && cached.hasSameStationDataAs(remoteSnapshot)) {
        await _cache.updateCachedAt(refreshedAt);
      } else {
        await _cache.replaceStations(
          remoteSnapshot.stations,
          cachedAt: refreshedAt,
        );
      }
    } catch (error, stackTrace) {
      cacheWriteFailed = true;
      if (kDebugMode) {
        debugPrint(
          'Infrastructure SQLite write failed; fresh remote data remains '
          'active in memory: error=$error.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    writeStopwatch.stop();
    remoteStopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        'Infrastructure refresh complete: total=${remoteSnapshot.stations.length}, '
        'existing=${remoteExisting.length}, proposed=${remoteProposed.length}, '
        'supabaseDuration=${remoteStopwatch.elapsedMilliseconds}ms, '
        'cacheWriteDuration=${writeStopwatch.elapsedMilliseconds}ms, '
        'cacheWriteFailed=$cacheWriteFailed.',
      );
    }
    yield InfrastructureLoadUpdate(
      phase: InfrastructureLoadPhase.remoteFresh,
      snapshot: remoteSnapshot,
      cacheWasStale: cacheWasStale,
      cacheWriteFailed: cacheWriteFailed,
    );
  }
}

void _validateStatusPartition(
  List<ChargingStation> stations,
  String expectedStatus, {
  bool requireNonEmpty = false,
}) {
  if (requireNonEmpty && stations.isEmpty) {
    throw StateError('Remote Existing infrastructure result was empty.');
  }
  if (stations.any((station) => station.status != expectedStatus)) {
    throw StateError(
      'Remote infrastructure status partition was inconsistent.',
    );
  }
}

void _validateCompleteSnapshot(List<ChargingStation> stations) {
  final ids = <String>{};
  for (final station in stations) {
    if (!ids.add(station.id)) {
      throw StateError(
        'Infrastructure snapshot contains duplicate station IDs.',
      );
    }
  }
}
