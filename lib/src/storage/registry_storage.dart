import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../integrity.dart';
import '../internal/semver.dart';
import '../models/manifest.dart';

/// Owns the on-disk layout for a locally cached registry.
///
/// Layout:
/// ```
/// <root>/
///   state.json                     { "currentVersion": "X.Y.Z" }
///   versions/
///     vX.Y.Z/
///       manifest.json
///       <files...>
/// ```
class RegistryStorage {
  /// Creates a storage rooted at [root]. The directory is created lazily
  /// on first write.
  RegistryStorage(this.root);

  /// Root directory of the registry cache.
  final Directory root;

  static const _stateFile = 'state.json';
  static const _versionsDir = 'versions';

  File _stateFileRef() => File(p.join(root.path, _stateFile));

  Directory _versionDir(String version) =>
      Directory(p.join(root.path, _versionsDir, 'v$version'));

  /// Returns the absolute path where [relPath] would live under [version].
  String resolveVersionFilePath(String version, String relPath) =>
      p.join(_versionDir(version).path, relPath);

  /// Reads the currently installed version, or `null` if none.
  Future<String?> readCurrentVersion() async {
    final f = _stateFileRef();
    if (!await f.exists()) return null;
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final v = raw['currentVersion'];
      return v is String ? v : null;
    } on FormatException {
      return null;
    }
  }

  /// Atomically writes [version] as the new current version.
  ///
  /// Uses a temp-file + rename strategy so a partial write never leaves
  /// `state.json` in a corrupted state.
  Future<void> writeCurrentVersion(String version) async {
    await root.create(recursive: true);
    final tmp = File(p.join(root.path, '$_stateFile.tmp'));
    await tmp.writeAsString(
      jsonEncode({'currentVersion': version}),
      flush: true,
    );
    await tmp.rename(_stateFileRef().path);
  }

  /// Atomically writes [m] to `versions/v<version>/manifest.json`.
  Future<void> writeManifest(String version, Manifest m) async {
    final dir = _versionDir(version);
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, 'manifest.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(m.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  /// Reads the manifest for [version], or `null` if missing or corrupted.
  Future<Manifest?> readManifest(String version) async {
    final f = File(p.join(_versionDir(version).path, 'manifest.json'));
    if (!await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Manifest.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  /// Writes [bytes] to the location identified by [file] under [version].
  ///
  /// Verifies the SHA-256 digest (and optional size) before writing.
  /// On integrity failure, no file is written. Writes atomically via
  /// a temp-file + rename.
  Future<void> writeVersionFile({
    required String version,
    required ManifestFile file,
    required List<int> bytes,
  }) async {
    final u8 = Uint8List.fromList(bytes);
    verifyBytes(
      path: file.path,
      bytes: u8,
      expectedSha256: file.sha256,
      expectedSize: file.size,
    );
    final out = File(resolveVersionFilePath(version, file.path));
    await out.parent.create(recursive: true);
    final tmp = File('${out.path}.tmp');
    await tmp.writeAsBytes(u8, flush: true);
    await tmp.rename(out.path);
  }

  /// Lists installed versions in ascending semver order.
  ///
  /// Ignores any entry that does not start with `v`.
  Future<List<String>> listInstalledVersions() async {
    final d = Directory(p.join(root.path, _versionsDir));
    if (!await d.exists()) return const [];
    final entries = await d.list().toList();
    final versions = <String>[];
    for (final e in entries) {
      if (e is! Directory) continue;
      final name = p.basename(e.path);
      if (name.startsWith('v')) versions.add(name.substring(1));
    }
    versions.sort(compareSemver);
    return versions;
  }

  /// Deletes installed versions not in the top-[keep] newest and not
  /// equal to [current].
  Future<void> gcOldVersions({
    required int keep,
    required String current,
  }) async {
    final all = await listInstalledVersions();
    if (all.length <= keep) return;
    final toKeep = all.sublist(all.length - keep).toSet()..add(current);
    for (final v in all) {
      if (!toKeep.contains(v)) {
        final dir = _versionDir(v);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }
  }

  /// Returns `true` iff every file listed in [m] exists on disk for [version].
  Future<bool> hasAllFiles(String version, Manifest m) async {
    for (final f in m.files) {
      if (!await File(resolveVersionFilePath(version, f.path)).exists()) {
        return false;
      }
    }
    return true;
  }
}
