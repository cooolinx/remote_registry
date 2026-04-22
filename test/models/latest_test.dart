import 'dart:convert';
import 'package:remote_registry/src/models/latest.dart';
import 'package:test/test.dart';

void main() {
  test('parses valid JSON', () {
    final p = LatestPointer.fromJson(jsonDecode('{"version":"1.2.3"}') as Map<String, dynamic>);
    expect(p.version, '1.2.3');
  });

  test('rejects missing version', () {
    expect(
      () => LatestPointer.fromJson(<String, dynamic>{}),
      throwsFormatException,
    );
  });

  test('rejects non-string version', () {
    expect(
      () => LatestPointer.fromJson(<String, dynamic>{'version': 123}),
      throwsFormatException,
    );
  });

  test('accepts and strips leading v prefix', () {
    final p = LatestPointer.fromJson(
        jsonDecode('{"version":"v1.2.3"}') as Map<String, dynamic>);
    expect(p.version, '1.2.3');
  });

  test('accepts and strips leading V prefix', () {
    final p = LatestPointer.fromJson(
        jsonDecode('{"version":"V1.2.3"}') as Map<String, dynamic>);
    expect(p.version, '1.2.3');
  });

  test('rejects version that is only a v prefix', () {
    expect(
      () => LatestPointer.fromJson(<String, dynamic>{'version': 'v'}),
      throwsFormatException,
    );
  });
}
