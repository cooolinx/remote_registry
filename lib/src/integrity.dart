import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'errors.dart';

/// Computes a lowercase hex-encoded SHA-256 digest of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Verifies [bytes] against [expectedSha256] (and optional [expectedSize]).
///
/// Parameters:
/// - [path]: registry-relative path used in error reporting.
/// - [bytes]: the raw bytes to verify.
/// - [expectedSha256]: the expected SHA-256 hex digest (case-insensitive).
/// - [expectedSize]: optional byte-length constraint.
///
/// Throws [RegistryIntegrityException] when the size or digest does not match.
void verifyBytes({
  required String path,
  required Uint8List bytes,
  required String expectedSha256,
  int? expectedSize,
}) {
  if (expectedSize != null && bytes.length != expectedSize) {
    throw RegistryIntegrityException(
      path: path,
      expectedSha256: expectedSha256,
      actualSha256: 'size=${bytes.length}!=$expectedSize',
    );
  }
  final actual = sha256Hex(bytes);
  if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
    throw RegistryIntegrityException(
      path: path,
      expectedSha256: expectedSha256.toLowerCase(),
      actualSha256: actual,
    );
  }
}
