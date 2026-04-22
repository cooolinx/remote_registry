import 'dart:convert';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_registry/src/bundle/asset_bundle_loader.dart';

const _sha1 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads manifest and bytes from bundled path', () async {
    final manifest = {
      'version': '0.1.0',
      'files': [
        {'path': 'a.txt', 'sha256': _sha1, 'size': 5},
      ],
    };
    final bundle = _FakeBundle({
      'assets/registry/manifest.json':
          Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      'assets/registry/a.txt': Uint8List.fromList(utf8.encode('hello')),
    });
    final loader = AssetBundleLoader(
      assetPath: 'assets/registry/',
      bundle: bundle,
    );

    final m = await loader.loadManifest();
    expect(m, isNotNull);
    expect(m!.version, '0.1.0');

    final bytes = await loader.loadFile('a.txt');
    expect(utf8.decode(bytes), 'hello');
  });

  test('loadManifest returns null if asset missing', () async {
    final loader = AssetBundleLoader(
      assetPath: 'assets/registry/',
      bundle: _FakeBundle({}),
    );
    expect(await loader.loadManifest(), isNull);
  });

  test('loadManifest returns null if asset is not valid JSON manifest', () async {
    final bundle = _FakeBundle({
      'assets/registry/manifest.json':
          Uint8List.fromList(utf8.encode('not json!')),
    });
    final loader = AssetBundleLoader(
      assetPath: 'assets/registry/',
      bundle: bundle,
    );
    expect(await loader.loadManifest(), isNull);
  });

  test('accepts assetPath without trailing slash', () async {
    final manifest = {'version': '0.1.0', 'files': <Map<String, dynamic>>[]};
    final bundle = _FakeBundle({
      'assets/registry/manifest.json':
          Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    });
    final loader = AssetBundleLoader(
      assetPath: 'assets/registry',     // no trailing /
      bundle: bundle,
    );
    final m = await loader.loadManifest();
    expect(m, isNotNull);
  });
}
