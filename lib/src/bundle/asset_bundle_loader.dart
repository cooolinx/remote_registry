import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/manifest.dart';

/// Loads a registry snapshot bundled inside a Flutter app's assets,
/// used as a fallback source when local cache is empty and network is
/// unavailable (e.g. first launch offline).
class AssetBundleLoader {
  /// Creates a loader that reads from [assetPath] inside [bundle]
  /// (defaults to [rootBundle]). [assetPath] may be passed with or
  /// without a trailing slash.
  AssetBundleLoader({required this.assetPath, AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle,
        _prefix = assetPath.endsWith('/') ? assetPath : '$assetPath/';

  /// Asset directory prefix (e.g. `assets/registry/`).
  final String assetPath;
  final AssetBundle _bundle;
  final String _prefix;

  /// Loads `<assetPath>/manifest.json` from the bundle.
  /// Returns null if the asset is missing or cannot be parsed as a manifest.
  Future<Manifest?> loadManifest() async {
    try {
      final data = await _bundle.load('${_prefix}manifest.json');
      final decoded = jsonDecode(utf8.decode(data.buffer.asUint8List()));
      if (decoded is! Map<String, dynamic>) return null;
      return Manifest.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Loads raw bytes for [relPath] from the bundle. Throws if missing.
  Future<Uint8List> loadFile(String relPath) async {
    final data = await _bundle.load('$_prefix$relPath');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
