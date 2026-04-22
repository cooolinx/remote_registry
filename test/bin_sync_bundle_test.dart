import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:remote_registry/src/integrity.dart';
import 'package:test/test.dart';

void main() {
  test('sync_bundle fetches and writes a version snapshot', () async {
    final hello = utf8.encode('hello');
    final helloSha = sha256Hex(hello);
    final modelsJson = utf8.encode('{"ok":true}');
    final modelsSha = sha256Hex(modelsJson);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/latest.json') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'version': '0.1.0'}));
      } else if (path == '/versions/v0.1.0/manifest.json') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'version': '0.1.0',
          'files': [
            {'path': 'a.txt', 'sha256': helloSha, 'size': hello.length},
            {'path': 'models.json', 'sha256': modelsSha, 'size': modelsJson.length},
          ],
        }));
      } else if (path == '/versions/v0.1.0/a.txt') {
        req.response.add(hello);
      } else if (path == '/versions/v0.1.0/models.json') {
        req.response.add(modelsJson);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final out = await Directory.systemTemp.createTemp('sync_bundle_');
    try {
      final result = await Process.run('dart', [
        'run',
        'remote_registry:sync_bundle',
        '--base',
        'http://127.0.0.1:${server.port}',
        '--out',
        out.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(p.join(out.path, 'manifest.json')).existsSync(), isTrue);
      expect(File(p.join(out.path, 'a.txt')).readAsStringSync(), 'hello');
      expect(File(p.join(out.path, 'models.json')).readAsStringSync(),
          '{"ok":true}');
    } finally {
      await server.close(force: true);
      await out.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('sync_bundle exits 64 on missing args', () async {
    final result = await Process.run('dart', [
      'run',
      'remote_registry:sync_bundle',
    ]);
    expect(result.exitCode, 64);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
