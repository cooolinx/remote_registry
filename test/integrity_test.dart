import 'dart:convert';
import 'dart:typed_data';
import 'package:remote_registry/src/errors.dart';
import 'package:remote_registry/src/integrity.dart';
import 'package:test/test.dart';

void main() {
  // Known: sha256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
  final helloBytes = Uint8List.fromList(utf8.encode('hello'));
  const helloSha =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  test('sha256Hex produces lowercase hex digest', () {
    expect(sha256Hex(helloBytes), helloSha);
  });

  test('verifyBytes returns on match (case-insensitive)', () {
    verifyBytes(path: 'x', bytes: helloBytes, expectedSha256: helloSha);
    verifyBytes(path: 'x', bytes: helloBytes, expectedSha256: helloSha.toUpperCase());
  });

  test('verifyBytes throws RegistryIntegrityException on mismatch', () {
    expect(
      () => verifyBytes(path: 'x', bytes: helloBytes, expectedSha256: 'deadbeef'),
      throwsA(isA<RegistryIntegrityException>()
          .having((e) => e.path, 'path', 'x')
          .having((e) => e.actualSha256, 'actual', helloSha)),
    );
  });

  test('verifyBytes throws when size mismatches', () {
    expect(
      () => verifyBytes(
          path: 'x',
          bytes: helloBytes,
          expectedSha256: helloSha,
          expectedSize: 999),
      throwsA(isA<RegistryIntegrityException>()),
    );
  });
}
