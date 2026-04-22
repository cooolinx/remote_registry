import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:remote_registry/src/models/manifest.dart';
import 'package:remote_registry/src/storage/registry_storage.dart';
import 'package:test/test.dart';

const _sha1 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _sha2 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('registry_test_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('readCurrentVersion returns null on fresh dir', () async {
    final s = RegistryStorage(root);
    expect(await s.readCurrentVersion(), isNull);
  });

  test('writeCurrentVersion then read round-trips', () async {
    final s = RegistryStorage(root);
    await s.writeCurrentVersion('0.1.0');
    expect(await s.readCurrentVersion(), '0.1.0');
  });

  test('writeVersionFile verifies and stores at versioned path', () async {
    final s = RegistryStorage(root);
    final bytes = utf8.encode('hello');
    const helloSha =
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
    await s.writeVersionFile(
      version: '0.1.0',
      file: const ManifestFile(path: 'a/b.txt', sha256: helloSha),
      bytes: bytes,
    );
    final f = File(p.join(root.path, 'versions', 'v0.1.0', 'a', 'b.txt'));
    expect(await f.exists(), isTrue);
    expect(await f.readAsBytes(), bytes);
  });

  test('writeVersionFile rejects bad sha and does not write partial', () async {
    final s = RegistryStorage(root);
    expect(
      () => s.writeVersionFile(
        version: '0.1.0',
        file: const ManifestFile(path: 'x', sha256: _sha1),
        bytes: [1, 2, 3],
      ),
      throwsA(anything),
    );
    final f = File(p.join(root.path, 'versions', 'v0.1.0', 'x'));
    expect(await f.exists(), isFalse);
  });

  test('resolveVersionFilePath returns path under version dir', () async {
    final s = RegistryStorage(root);
    final path = s.resolveVersionFilePath('0.1.0', 'a/b.txt');
    expect(p.isWithin(root.path, path), isTrue);
    expect(path, endsWith(p.join('versions', 'v0.1.0', 'a', 'b.txt')));
  });

  test('writeManifest then readManifest round-trips', () async {
    final s = RegistryStorage(root);
    final m = const Manifest(version: '0.1.0', files: [
      ManifestFile(path: 'a.json', sha256: _sha1, size: 1),
      ManifestFile(path: 'b.bin', sha256: _sha2),
    ]);
    await s.writeManifest('0.1.0', m);
    final read = await s.readManifest('0.1.0');
    expect(read, isNotNull);
    expect(read!.version, '0.1.0');
    expect(read.files, hasLength(2));
    expect(read.files[0].path, 'a.json');
    expect(read.files[0].sha256, _sha1);
    expect(read.files[0].size, 1);
    expect(read.files[1].path, 'b.bin');
    expect(read.files[1].size, isNull);
  });

  test('readManifest returns null if missing', () async {
    final s = RegistryStorage(root);
    expect(await s.readManifest('0.1.0'), isNull);
  });

  test('listInstalledVersions returns sorted semver', () async {
    final s = RegistryStorage(root);
    for (final v in ['0.0.9', '0.1.0', '0.2.0', '0.10.0']) {
      await Directory(p.join(root.path, 'versions', 'v$v'))
          .create(recursive: true);
    }
    expect(await s.listInstalledVersions(),
        ['0.0.9', '0.1.0', '0.2.0', '0.10.0']);
  });

  test('gcOldVersions keeps the last N plus current', () async {
    final s = RegistryStorage(root);
    for (final v in ['0.0.7', '0.0.8', '0.0.9', '0.1.0']) {
      await Directory(p.join(root.path, 'versions', 'v$v'))
          .create(recursive: true);
    }
    await s.gcOldVersions(keep: 2, current: '0.1.0');
    expect(await s.listInstalledVersions(), ['0.0.9', '0.1.0']);
  });

  test('hasAllFiles true only when every listed file is present', () async {
    final s = RegistryStorage(root);
    const m = Manifest(version: '0.1.0', files: [
      ManifestFile(path: 'a.json', sha256: _sha1),
      ManifestFile(path: 'b.bin', sha256: _sha2),
    ]);

    // Neither file exists yet.
    expect(await s.hasAllFiles('0.1.0', m), isFalse);

    // Write only the first file.
    final aFile =
        File(p.join(root.path, 'versions', 'v0.1.0', 'a.json'));
    await aFile.parent.create(recursive: true);
    await aFile.writeAsBytes(utf8.encode('a'));
    expect(await s.hasAllFiles('0.1.0', m), isFalse);

    // Write the second file.
    final bFile =
        File(p.join(root.path, 'versions', 'v0.1.0', 'b.bin'));
    await bFile.writeAsBytes([1]);
    expect(await s.hasAllFiles('0.1.0', m), isTrue);
  });

  test('writeCurrentVersion is atomic (tmp + rename)', () async {
    final s = RegistryStorage(root);
    await s.writeCurrentVersion('0.1.0');
    // After rename, no state.json.tmp remains.
    final tmp = File(p.join(root.path, 'state.json.tmp'));
    expect(await tmp.exists(), isFalse);
  });

  test('listInstalledVersions skips non-semver v* dirs', () async {
    final s = RegistryStorage(root);
    for (final name in ['v0.1.0', 'vfoo', 'v1.0', 'v2.3.4', 'vbar-beta']) {
      await Directory(p.join(root.path, 'versions', name))
          .create(recursive: true);
    }
    expect(await s.listInstalledVersions(), ['0.1.0', '2.3.4']);
  });

  test('readCurrentVersion returns null on malformed (not-object) state.json',
      () async {
    final s = RegistryStorage(root);
    await root.create(recursive: true);
    await File(p.join(root.path, 'state.json')).writeAsString('[1,2]');
    expect(await s.readCurrentVersion(), isNull);
  });

  test('readManifest returns null on not-object JSON', () async {
    final s = RegistryStorage(root);
    final dir = Directory(p.join(root.path, 'versions', 'v0.1.0'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'manifest.json')).writeAsString('"hello"');
    expect(await s.readManifest('0.1.0'), isNull);
  });
}
