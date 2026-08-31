import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const String mevnetTrustAnchorAsset =
    'assets/certs/sectigo_public_server_authentication_root_r46.pem';

const String mevnetTrustAnchorSha256 =
    '7BB647A62AEEAC88BF257AA522D01FFEA395E0AB45C73F93F65654EC38F25A06';

class MEVnetTrustAnchorException implements Exception {
  const MEVnetTrustAnchorException(this.message);

  final String message;

  @override
  String toString() => 'MEVnetTrustAnchorException: $message';
}

@visibleForTesting
Future<Uint8List> loadMevnetTrustAnchor({AssetBundle? bundle}) async {
  final ByteData data;
  try {
    data = await (bundle ?? rootBundle).load(mevnetTrustAnchorAsset);
  } catch (error) {
    throw MEVnetTrustAnchorException(
      'Unable to load $mevnetTrustAnchorAsset: $error',
    );
  }
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  if (bytes.isEmpty) {
    throw const MEVnetTrustAnchorException(
      'Bundled MEVnet trust anchor is empty.',
    );
  }

  if (!String.fromCharCodes(bytes).contains('-----BEGIN CERTIFICATE-----')) {
    throw const MEVnetTrustAnchorException(
      'Bundled MEVnet trust anchor is not a PEM certificate.',
    );
  }
  return bytes;
}

@visibleForTesting
HttpClient createMevnetHttpsClient(List<int> trustAnchorPem) {
  final context = SecurityContext(withTrustedRoots: true);
  try {
    context.setTrustedCertificatesBytes(trustAnchorPem);
  } on TlsException catch (error) {
    throw MEVnetTrustAnchorException(
      'Bundled MEVnet trust anchor was rejected: ${error.message}',
    );
  }

  return HttpClient(context: context);
}

Future<http.Client> createMevnetHttpClient({AssetBundle? bundle}) async {
  final pem = await loadMevnetTrustAnchor(bundle: bundle);
  return IOClient(createMevnetHttpsClient(pem));
}
