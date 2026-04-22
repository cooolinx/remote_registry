import 'dart:convert';
import 'package:remote_registry/src/models/manifest.dart';
import 'package:test/test.dart';

const _goodJson = '''
{
  "version": "0.1.0",
  "files": [
    { "path": "models.json", "sha256": "abc123", "size": 42 },
    { "path": "a/b.bin",     "sha256": "def456" }
  ]
}
''';

void main() {
  test('parses a well-formed manifest', () {
    final m = Manifest.fromJson(jsonDecode(_goodJson) as Map<String, dynamic>);
    expect(m.version, '0.1.0');
    expect(m.files, hasLength(2));
    expect(m.files[0].path, 'models.json');
    expect(m.files[0].sha256, 'abc123');
    expect(m.files[0].size, 42);
    expect(m.files[1].size, isNull);
  });

  test('rejects absolute paths', () {
    final bad = jsonDecode('{"version":"1","files":[{"path":"/abs","sha256":"x"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('rejects parent-directory traversal', () {
    final bad = jsonDecode('{"version":"1","files":[{"path":"../x","sha256":"y"}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('rejects empty sha256', () {
    final bad = jsonDecode('{"version":"1","files":[{"path":"a","sha256":""}]}')
        as Map<String, dynamic>;
    expect(() => Manifest.fromJson(bad), throwsFormatException);
  });

  test('findByPath returns file or null', () {
    final m = Manifest.fromJson(jsonDecode(_goodJson) as Map<String, dynamic>);
    expect(m.findByPath('models.json'), isNotNull);
    expect(m.findByPath('nope'), isNull);
  });
}
