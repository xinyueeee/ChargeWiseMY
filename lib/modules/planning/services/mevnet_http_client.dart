import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Public CA root that completes the certificate chain served by the MEVnet
/// host, bundled because Dart's built-in trust anchors may not yet include it.
///
/// The MEVnet layer is served by `gisdev.planmalaysia.gov.my`, whose chain is:
///
///   leaf  CN=*.planmalaysia.gov.my
///     issued by  CN=Entrust OV TLS Issuing RSA CA 2   (sent by the server)
///       issued by  CN=Sectigo Public Server Authentication Root R46  (root)
///
/// The server correctly sends leaf + intermediate; only the root is missing
/// locally. Android's own trust store contains this root (Chrome on the same
/// device reaches the endpoint), but `dart:io` verifies against root
/// certificates compiled into the Flutter engine rather than the platform
/// store, so the handshake fails there with
/// `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`.
///
/// Adding this one public root as an *additional* trust anchor closes that gap
/// without weakening verification anywhere.
const String mevnetTrustAnchorAsset =
    'assets/certs/sectigo_public_server_authentication_root_r46.pem';

/// SHA-256 fingerprint of [mevnetTrustAnchorAsset], recorded so the bundled
/// file can be audited against the published Sectigo root.
const String mevnetTrustAnchorSha256 =
    '7BB647A62AEEAC88BF257AA522D01FFEA395E0AB45C73F93F65654EC38F25A06';

/// Raised when the bundled trust anchor cannot be read or is not a usable
/// certificate. Failing here is deliberate: the alternative would be an
/// HTTPS client that silently falls back to weaker verification.
class MEVnetTrustAnchorException implements Exception {
  const MEVnetTrustAnchorException(this.message);

  final String message;

  @override
  String toString() => 'MEVnetTrustAnchorException: $message';
}

/// Loads the bundled PEM trust anchor.
///
/// Throws [MEVnetTrustAnchorException] when the asset is missing or does not
/// look like a PEM certificate, so a packaging mistake surfaces immediately
/// instead of degrading TLS behaviour.
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
  // Cheap shape check before handing the bytes to BoringSSL, so a truncated or
  // wrong-file asset produces a clear message rather than a TlsException.
  if (!String.fromCharCodes(bytes).contains('-----BEGIN CERTIFICATE-----')) {
    throw const MEVnetTrustAnchorException(
      'Bundled MEVnet trust anchor is not a PEM certificate.',
    );
  }
  return bytes;
}

/// Builds the `dart:io` client used for MEVnet requests only.
///
/// Verification is deliberately left at its defaults:
/// * `withTrustedRoots: true` keeps every built-in trust anchor, so the
///   bundled root *supplements* rather than replaces the default set.
/// * `badCertificateCallback` is never assigned, so an untrusted chain, an
///   expired certificate, or a hostname mismatch still fails the request.
///
/// Throws [MEVnetTrustAnchorException] if [trustAnchorPem] is rejected.
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
  // No badCertificateCallback: chain and hostname verification stay enforced.
  return HttpClient(context: context);
}

/// Creates the `package:http` client injected into `MEVnetApiService`.
///
/// Scoped to MEVnet on purpose. `SecurityContext.defaultContext` and
/// `HttpOverrides.global` are untouched, so Supabase, Google Maps and every
/// other request in the app keep using the unmodified default trust settings.
Future<http.Client> createMevnetHttpClient({AssetBundle? bundle}) async {
  final pem = await loadMevnetTrustAnchor(bundle: bundle);
  return IOClient(createMevnetHttpsClient(pem));
}
