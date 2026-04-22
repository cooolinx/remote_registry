import 'dart:convert';
import 'package:remote_registry/src/models/manifest.dart';
import 'package:test/test.dart';

// Valid 64-char lowercase hex strings used as test fixtures.
const _sha1 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _sha2 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final _goodJson = '''
{
  "version": "0.1.0",
  "files": [
    { "path": "models.json", "sha256": "$_sha1", "size": 42 },
    { "path": "a/b.bin",     "sha256": "$_sha2" }
  ]
}
''';

void main() {
  test('parses a well-formed manifest', () {
    final m = Manifest.fromJson(jsonDecode(_goodJson) as Map<String, dynamic>);
    expect(m.version, '0.1.0');
    expect(m.files, hasLength(2));
    expect(m.files[0].path, 'models.json');
    expect(m.files[0].sha256, _sha1);
    expect(m.files[0].size, 42);
    expect(m.files[1].size, isNull);
  });

  test('rejects absolute paths', () {
    final bad = jsonDecode(
            '{"version":"1","files":[{"path":"/abs","sha256":"$_sha1"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('rejects parent-directory traversal', () {
    final bad = jsonDecode(
            '{"version":"1","files":[{"path":"../x","sha256":"$_sha1"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('rejects empty sha256', () {
    final bad =
        jsonDecode('{"version":"1","files":[{"path":"a","sha256":""}]}')
            as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('findByPath returns file or null', () {
    final m = Manifest.fromJson(jsonDecode(_goodJson) as Map<String, dynamic>);
    expect(m.findByPath('models.json'), isNotNull);
    expect(m.findByPath('nope'), isNull);
  });

  // --- IMPORTANT 1: backslash rejection ---
  test('rejects backslash in path', () {
    final bad = jsonDecode(
            r'{"version":"1","files":[{"path":"foo\\..\\x","sha256":"y"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  // --- IMPORTANT 2: unmodifiable files list ---
  test('files list is unmodifiable', () {
    final m = Manifest.fromJson(jsonDecode(_goodJson) as Map<String, dynamic>);
    expect(
        () => m.files.add(const ManifestFile(path: 'x', sha256: 'y')),
        throwsUnsupportedError);
    expect(
        () => m.files[0] = const ManifestFile(path: 'x', sha256: 'y'),
        throwsUnsupportedError);
  });

  // --- MINOR 1: empty path segments ---
  test('rejects empty path segments', () {
    final bad = jsonDecode(
            '{"version":"1","files":[{"path":"a//b","sha256":"$_sha1"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  // --- MINOR 2: sha256 format validation ---
  test('rejects non-hex sha256', () {
    final bad = jsonDecode(
            '{"version":"1","files":[{"path":"a","sha256":"not-hex"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('accepts and strips v prefix on version', () {
    final json = jsonDecode(
            '{"version":"v0.1.0","files":[{"path":"a","sha256":"$_sha1"}]}')
        as Map<String, dynamic>;
    final m = Manifest.fromJson(json);
    expect(m.version, '0.1.0');
  });

  test('rejects version that is only a v prefix', () {
    final bad = jsonDecode(
            '{"version":"v","files":[{"path":"a","sha256":"$_sha1"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });
}
