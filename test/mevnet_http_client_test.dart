import 'dart:io';

import 'package:chargewise_my/modules/planning/services/mevnet_http_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

/// An [AssetBundle] that serves exactly what a test hands it, so trust-anchor
/// loading can be exercised without the real asset bundle.
class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);

  final Map<String, ByteData> _assets;

  @override
  Future<ByteData> load(String key) async {
    final data = _assets[key];
    if (data == null) throw Exception('Asset not found: $key');
    return data;
  }
}

ByteData _bytes(String value) =>
    ByteData.sublistView(Uint8List.fromList(value.codeUnits));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List realAnchor;

  setUpAll(() async {
    // The genuine bundled root, read from disk exactly as it ships.
    realAnchor = Uint8List.fromList(
      await File('assets/certs/'
              'sectigo_public_server_authentication_root_r46.pem')
          .readAsBytes(),
    );
  });

  group('bundled trust anchor', () {
    test('the shipped asset is a single public CA certificate', () {
      final text = String.fromCharCodes(realAnchor);
      expect(text, contains('-----BEGIN CERTIFICATE-----'));
      expect(text, contains('-----END CERTIFICATE-----'));
      expect('-----BEGIN CERTIFICATE-----'.allMatches(text), hasLength(1));
      // A trust anchor must never ship with private key material.
      expect(text, isNot(contains('PRIVATE KEY')));
    });

    test('loads from the asset bundle', () async {
      final bundle = _FakeAssetBundle(<String, ByteData>{
        mevnetTrustAnchorAsset: ByteData.sublistView(realAnchor),
      });

      final loaded = await loadMevnetTrustAnchor(bundle: bundle);

      expect(loaded, equals(realAnchor));
    });

    test('fails loudly when the asset is missing', () async {
      final bundle = _FakeAssetBundle(<String, ByteData>{});

      // A packaging mistake must surface, never degrade into weaker TLS.
      await expectLater(
        loadMevnetTrustAnchor(bundle: bundle),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
    });

    test('fails when the asset is empty', () async {
      final bundle = _FakeAssetBundle(<String, ByteData>{
        mevnetTrustAnchorAsset: ByteData(0),
      });

      await expectLater(
        loadMevnetTrustAnchor(bundle: bundle),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
    });

    test('fails when the asset is not a PEM certificate', () async {
      final bundle = _FakeAssetBundle(<String, ByteData>{
        mevnetTrustAnchorAsset: _bytes('not a certificate'),
      });

      await expectLater(
        loadMevnetTrustAnchor(bundle: bundle),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
    });
  });

  group('MEVnet HTTPS client', () {
    test('builds an HttpClient from the real bundled anchor', () {
      final client = createMevnetHttpsClient(realAnchor);
      addTearDown(() => client.close(force: true));

      expect(client, isA<HttpClient>());
    });

    test('no source file installs a certificate-verification bypass',
        () async {
      // HttpClient.badCertificateCallback is setter-only, so it cannot be read
      // back at runtime. Asserting over the source is the durable guard: it
      // fails the build if anyone later adds a bypass anywhere in lib/.
      const banned = <String>[
        'badCertificateCallback',
        'HttpOverrides.global',
        'onBadCertificate',
      ];
      final offenders = <String>[];
      await for (final entity in Directory('lib').list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Strip comments so documentation *describing* the policy does not
        // register as a violation of it.
        final code = (await entity.readAsLines())
            .where((line) {
              final trimmed = line.trimLeft();
              return !trimmed.startsWith('//') && !trimmed.startsWith('*');
            })
            .join('\n');
        if (banned.any(code.contains)) offenders.add(entity.path);
      }

      expect(offenders, isEmpty);
    });

    test('rejects a malformed trust anchor instead of continuing', () {
      expect(
        () => createMevnetHttpsClient('-----BEGIN CERTIFICATE-----\nnope\n'
                '-----END CERTIFICATE-----\n'
            .codeUnits),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
    });

    test('createMevnetHttpClient returns an IOClient wrapping the context',
        () async {
      final bundle = _FakeAssetBundle(<String, ByteData>{
        mevnetTrustAnchorAsset: ByteData.sublistView(realAnchor),
      });

      final client = await createMevnetHttpClient(bundle: bundle);
      addTearDown(client.close);

      expect(client, isA<IOClient>());
    });

    test('propagates a missing asset rather than returning a client',
        () async {
      final bundle = _FakeAssetBundle(<String, ByteData>{});

      await expectLater(
        createMevnetHttpClient(bundle: bundle),
        throwsA(isA<MEVnetTrustAnchorException>()),
      );
    });
  });

  group('global TLS settings are untouched', () {
    test('SecurityContext.defaultContext is not replaced', () {
      final before = SecurityContext.defaultContext;
      final client = createMevnetHttpsClient(realAnchor);
      addTearDown(() => client.close(force: true));

      // Supabase, Google Maps and every other request keep the default trust
      // settings; the bundled anchor is scoped to this client alone.
      expect(identical(SecurityContext.defaultContext, before), isTrue);
    });

    test('building the client does not install an HttpOverrides', () {
      // flutter_test installs its own override, so the meaningful assertion is
      // that building the MEVnet client leaves whatever is current unchanged.
      final before = HttpOverrides.current;
      final client = createMevnetHttpsClient(realAnchor);
      addTearDown(() => client.close(force: true));

      expect(identical(HttpOverrides.current, before), isTrue);
    });
  });
}
