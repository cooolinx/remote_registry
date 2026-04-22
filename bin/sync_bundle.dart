import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:remote_registry/src/integrity.dart';
import 'package:remote_registry/src/internal/semver.dart';
import 'package:remote_registry/src/models/latest.dart';
import 'package:remote_registry/src/models/manifest.dart';
import 'package:remote_registry/src/transport/http_transport.dart';

/// Snapshots a registry version to a local directory for Flutter-asset
/// bundling.
///
/// Usage:
///   dart run remote_registry:sync_bundle --base URL --out DIR [--version X.Y.Z]
Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final base = Uri.parse(
    opts['base']!.endsWith('/') ? opts['base']! : '${opts['base']}/',
  );
  final outDir = Directory(opts['out']!);
  if (await outDir.exists()) await outDir.delete(recursive: true);
  await outDir.create(recursive: true);

  final http = HttpTransport();
  try {
    final version = opts['version'] != null
        ? stripVPrefix(opts['version']!)
        : LatestPointer.fromJson(
                await http.fetchJson(base.resolve('latest.json')))
            .version;

    final manifest = Manifest.fromJson(
      await http.fetchJson(base.resolve('versions/v$version/manifest.json')),
    );

    await File(p.join(outDir.path, 'manifest.json'))
        .writeAsString(jsonEncode(manifest.toJson()), flush: true);

    for (final f in manifest.files) {
      final bytes = await http.fetchBytes(
        base.resolve('versions/v$version/${f.path}'),
      );
      final actual = sha256Hex(bytes);
      if (actual != f.sha256.toLowerCase()) {
        stderr.writeln(
            'Integrity failed for ${f.path}: expected ${f.sha256}, got $actual');
        exitCode = 2;
        return;
      }
      final out = File(p.join(outDir.path, f.path));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes, flush: true);
      stdout.writeln('fetched ${f.path} (${bytes.length} bytes)');
    }
    stdout.writeln('synced v$version to ${outDir.path}');
  } finally {
    http.close();
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final m = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--') && i + 1 < args.length) {
      m[a.substring(2)] = args[++i];
    }
  }
  if (!m.containsKey('base') || !m.containsKey('out')) {
    stderr.writeln(
        'usage: sync_bundle --base <url> --out <dir> [--version X.Y.Z]');
    exit(64);
  }
  return m;
}
