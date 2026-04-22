import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_registry/remote_registry.dart';
import 'package:remote_registry/src/integrity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('rr_net_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Build a MockClient that serves one CDN version's registry.
  MockClient cdn({
    required String version,
    required Map<String, String> files, // relPath -> text content
    int latestStatus = 200,
    Map<String, int>? fileStatusOverride,
  }) {
    final manifest = {
      'version': version,
      'files': [
        for (final e in files.entries)
          {
            'path': e.key,
            'sha256': sha256Hex(utf8.encode(e.value)),
            'size': utf8.encode(e.value).length,
          }
      ],
    };
    return MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/latest.json')) {
        if (latestStatus != 200) return http.Response('err', latestStatus);
        return http.Response(jsonEncode({'version': version}), 200);
      }
      if (path.endsWith('/manifest.json')) {
        return http.Response(jsonEncode(manifest), 200);
      }
      for (final e in files.entries) {
        if (path.endsWith('/${e.key}')) {
          final status = fileStatusOverride?[e.key] ?? 200;
          if (status != 200) return http.Response('err', status);
          return http.Response(e.value, status);
        }
      }
      return http.Response('not found', 404);
    });
  }

  test('cold init (no cache, no bundle) downloads everything', () async {
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: cdn(version: '0.1.0', files: {'a.json': '{"x":1}'}),
    );
    await r.init(mode: RegistryInitMode.blockUntilLatest);
    expect(r.currentVersion, '0.1.0');
    final f = await r.getFile('a.json');
    expect(await f.readAsString(), '{"x":1}');
    await r.dispose();
  });

  test('refresh promotes newer version and GCs old', () async {
    // Seed 0.1.0.
    {
      final seed = RemoteRegistry.withStorage(
        baseUrl: 'https://cdn.example/',
        storageDir: root,
        testHttpClient:
            cdn(version: '0.1.0', files: {'a.json': '{"v":1}'}),
      );
      await seed.init(mode: RegistryInitMode.blockUntilLatest);
      await seed.dispose();
    }

    // Now bump to 0.2.0.
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient:
          cdn(version: '0.2.0', files: {'a.json': '{"v":2}'}),
      keepVersions: 1,
    );
    await r.init(mode: RegistryInitMode.blockUntilLatest);
    expect(r.currentVersion, '0.2.0');
    expect(await (await r.getFile('a.json')).readAsString(), '{"v":2}');
    // Old dir GC'd.
    expect(Directory('${root.path}/versions/v0.1.0').existsSync(), isFalse);
    await r.dispose();
  });

  test('stale-then-refresh swallows network failure', () async {
    // Seed 0.1.0.
    {
      final seed = RemoteRegistry.withStorage(
        baseUrl: 'https://cdn.example/',
        storageDir: root,
        testHttpClient:
            cdn(version: '0.1.0', files: {'a.json': '{"v":1}'}),
      );
      await seed.init(mode: RegistryInitMode.blockUntilLatest);
      await seed.dispose();
    }

    // Network broken but we have cache.
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: cdn(
        version: '0.1.0',
        files: {'a.json': '{"v":1}'},
        latestStatus: 500,
      ),
    );
    await r.init(); // staleThenRefresh default — must not throw
    expect(r.currentVersion, '0.1.0');
    await r.dispose();
  });

  test('no cache + no bundle + network 500 throws Unavailable', () async {
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: cdn(
        version: '0.1.0',
        files: {'a.json': '{"v":1}'},
        latestStatus: 500,
      ),
    );
    await expectLater(
      r.init(mode: RegistryInitMode.blockUntilLatest),
      throwsA(isA<RegistryException>()),
    );
    await r.dispose();
  });

  test('onUpdate emits new version after background refresh', () async {
    // Seed 0.1.0.
    {
      final seed = RemoteRegistry.withStorage(
        baseUrl: 'https://cdn.example/',
        storageDir: root,
        testHttpClient:
            cdn(version: '0.1.0', files: {'a.json': '{"v":1}'}),
      );
      await seed.init(mode: RegistryInitMode.blockUntilLatest);
      await seed.dispose();
    }

    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient:
          cdn(version: '0.2.0', files: {'a.json': '{"v":2}'}),
    );
    // Use blocking to make the test deterministic (still exercises the emit).
    final emitted = <String>[];
    final sub = r.onUpdate.listen(emitted.add);
    await r.init(mode: RegistryInitMode.blockUntilLatest);
    // Let the stream flush.
    await Future<void>.delayed(Duration.zero);
    expect(emitted, ['0.2.0']);
    await sub.cancel();
    await r.dispose();
  });

  test('non-semver latest.version throws RegistryNetworkException', () async {
    // Seed 0.1.0 so _activeVersion is set and compareSemver is actually called.
    {
      final seed = RemoteRegistry.withStorage(
        baseUrl: 'https://cdn.example/',
        storageDir: root,
        testHttpClient: cdn(version: '0.1.0', files: {'a.json': '{"v":1}'}),
      );
      await seed.init(mode: RegistryInitMode.blockUntilLatest);
      await seed.dispose();
    }
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/latest.json')) {
        return http.Response(jsonEncode({'version': 'not-a-semver'}), 200);
      }
      return http.Response('not found', 404);
    });
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: client,
    );
    await expectLater(
      r.init(mode: RegistryInitMode.blockUntilLatest),
      throwsA(isA<RegistryNetworkException>()),
    );
    await r.dispose();
  });

  test('manifest version mismatch with latest.json throws', () async {
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/latest.json')) {
        return http.Response(jsonEncode({'version': '0.1.0'}), 200);
      }
      if (path.endsWith('/manifest.json')) {
        return http.Response(
          jsonEncode({
            'version': '0.2.0', // mismatch!
            'files': <Map<String, dynamic>>[],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: client,
    );
    await expectLater(
      r.init(mode: RegistryInitMode.blockUntilLatest),
      throwsA(isA<RegistryException>()),
    );
    await r.dispose();
  });
}
