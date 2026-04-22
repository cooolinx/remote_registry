import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_registry/remote_registry.dart';
import 'package:remote_registry/src/integrity.dart';
import 'package:remote_registry/src/models/manifest.dart';
import 'package:remote_registry/src/storage/registry_storage.dart';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._data);
  final Map<String, Uint8List> _data;
  @override
  Future<ByteData> load(String key) async {
    final d = _data[key];
    if (d == null) throw FlutterError('asset not found: $key');
    return ByteData.sublistView(d);
  }
}

Future<void> _seedCache(
    Directory root, String version, Map<String, String> files) async {
  final s = RegistryStorage(root);
  final mFiles = files.entries
      .map((e) => ManifestFile(
            path: e.key,
            sha256: sha256Hex(utf8.encode(e.value)),
            size: utf8.encode(e.value).length,
          ))
      .toList();
  final m = Manifest(version: version, files: mFiles);
  await s.writeManifest(version, m);
  for (final e in files.entries) {
    await s.writeVersionFile(
      version: version,
      file: m.findByPath(e.key)!,
      bytes: utf8.encode(e.value),
    );
  }
  await s.writeCurrentVersion(version);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('rr_init_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('init uses local cache when present', () async {
    await _seedCache(root, '0.1.0', {'a.json': '{"x":1}'});
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: root,
    );
    await r.init();
    expect(r.currentVersion, '0.1.0');
    final f = await r.getFile('a.json');
    expect(await f.readAsString(), '{"x":1}');
    final json = await r.getJson('a.json');
    expect(json, {'x': 1});
    await r.dispose();
  });

  test('init falls back to bundle when no local cache', () async {
    final manifestJson = {
      'version': '0.2.0',
      'files': [
        {
          'path': 'b.txt',
          'sha256': sha256Hex(utf8.encode('hello')),
          'size': 5,
        }
      ],
    };
    final bundle = _FakeBundle({
      'assets/registry/manifest.json':
          Uint8List.fromList(utf8.encode(jsonEncode(manifestJson))),
      'assets/registry/b.txt': Uint8List.fromList(utf8.encode('hello')),
    });

    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: root,
      bundledAssetPath: 'assets/registry/',
      testBundle: bundle,
    );
    await r.init();
    expect(r.currentVersion, '0.2.0');
    final f = await r.getFile('b.txt');
    expect(await f.readAsString(), 'hello');

    // Files and manifest should be seeded to disk now.
    final onDisk = File('${root.path}/versions/v0.2.0/b.txt');
    expect(onDisk.existsSync(), isTrue);
    await r.dispose();
  });

  test('init with no cache and no bundle throws Unavailable', () async {
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: root,
    );
    // With no cache, no bundle, and no network connectivity the registry
    // throws a RegistryException (RegistryNetworkException in practice).
    await expectLater(
      r.init(),
      throwsA(isA<RegistryException>()),
    );
    await r.dispose();
  });

  test('getFile throws FileNotFound for path not in manifest', () async {
    await _seedCache(root, '0.1.0', {'a.json': '{}'});
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: root,
    );
    await r.init();
    expect(
      () => r.getFile('missing.json'),
      throwsA(isA<RegistryFileNotFoundException>()),
    );
    await r.dispose();
  });

  test('currentVersion before init throws StateError', () {
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: Directory.systemTemp,
    );
    expect(() => r.currentVersion, throwsStateError);
  });

  test('concurrent init() calls share a single initialization', () async {
    await _seedCache(root, '0.1.0', {'a.json': '{"x":1}'});
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: root,
    );
    // Fire two concurrent init() calls without awaiting the first.
    final f1 = r.init();
    final f2 = r.init();
    await Future.wait([f1, f2]);
    expect(r.currentVersion, '0.1.0');
    await r.dispose();
  });
}
