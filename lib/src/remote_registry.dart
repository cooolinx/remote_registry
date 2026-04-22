import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bundle/asset_bundle_loader.dart';
import 'errors.dart';
import 'models/manifest.dart';
import 'storage/registry_storage.dart';
import 'transport/http_transport.dart';

/// Policy for [RemoteRegistry.init].
enum RegistryInitMode {
  /// If local cache or bundle is available, resolve immediately and
  /// refresh in the background. (Default.)
  staleThenRefresh,

  /// Always block until the latest version is fetched and verified
  /// from the network.
  blockUntilLatest,
}

/// Client for a CDN-backed JSON/binary registry.
///
/// Files are resolved from — in order of preference — the local disk
/// cache, a Flutter-asset fallback snapshot, or the network. Every
/// downloaded file is SHA-256 verified against the manifest.
///
/// Typical usage:
/// ```dart
/// final registry = RemoteRegistry(baseUrl: 'https://cdn.example.com/registry/');
/// await registry.init();
/// final config = await registry.getJson('config.json');
/// ```
class RemoteRegistry {
  /// Creates a registry with a default storage directory
  /// (`getApplicationSupportDirectory()/[subdirectory]`).
  RemoteRegistry({
    required String baseUrl,
    String subdirectory = 'remote_registry',
    String? bundledAssetPath,
    Duration httpTimeout = const Duration(seconds: 30),
    int maxConcurrentDownloads = 4,
    int keepVersions = 2,
    @visibleForTesting AssetBundle? testBundle,
    @visibleForTesting http.Client? testHttpClient,
  })  : _baseUrl = _normalizeBase(baseUrl),
        _subdirectory = subdirectory,
        _customStorageDir = null,
        _bundledAssetPath = bundledAssetPath,
        _httpTimeout = httpTimeout,
        _maxConcurrent = maxConcurrentDownloads,
        _keepVersions = keepVersions,
        _testBundle = testBundle,
        _testHttpClient = testHttpClient;

  /// Creates a registry with a caller-specified storage directory.
  RemoteRegistry.withStorage({
    required String baseUrl,
    required Directory storageDir,
    String? bundledAssetPath,
    Duration httpTimeout = const Duration(seconds: 30),
    int maxConcurrentDownloads = 4,
    int keepVersions = 2,
    @visibleForTesting AssetBundle? testBundle,
    @visibleForTesting http.Client? testHttpClient,
  })  : _baseUrl = _normalizeBase(baseUrl),
        _subdirectory = '',
        _customStorageDir = storageDir,
        _bundledAssetPath = bundledAssetPath,
        _httpTimeout = httpTimeout,
        _maxConcurrent = maxConcurrentDownloads,
        _keepVersions = keepVersions,
        _testBundle = testBundle,
        _testHttpClient = testHttpClient;

  // ignore: unused_field — used in Task 11 for network URLs
  final Uri _baseUrl;
  final String _subdirectory;
  final Directory? _customStorageDir;
  final String? _bundledAssetPath;
  final Duration _httpTimeout;
  // ignore: unused_field — used in Task 11
  final int _maxConcurrent;
  // ignore: unused_field — used in Task 11
  final int _keepVersions;
  final AssetBundle? _testBundle;
  final http.Client? _testHttpClient;

  final _updateController = StreamController<String>.broadcast();

  /// Emits the new version string after a successful background refresh.
  Stream<String> get onUpdate => _updateController.stream;

  late final RegistryStorage _storage;
  // ignore: unused_field — used in Task 11
  late final HttpTransport _http;
  AssetBundleLoader? _bundle;

  Manifest? _activeManifest;
  String? _activeVersion;
  bool _initialized = false;

  /// The version currently in use.
  ///
  /// Throws [StateError] if [init] has not completed successfully.
  String get currentVersion {
    final v = _activeVersion;
    if (v == null) {
      throw StateError('RemoteRegistry.init() has not completed.');
    }
    return v;
  }

  /// Resolves a usable registry version.
  ///
  /// On first call, resolves the storage directory, constructs internal
  /// components, and attempts to load a usable version in this order:
  ///
  /// 1. **Local cache**: existing version on disk.
  /// 2. **Bundle fallback**: seeds disk from the bundled asset snapshot
  ///    (if [bundledAssetPath] was set at construction).
  /// 3. **Network** (not yet implemented — throws [RegistryUnavailableException]).
  ///
  /// Subsequent calls are no-ops (idempotent).
  ///
  /// See [RegistryInitMode] for trade-offs between modes.
  Future<void> init({
    RegistryInitMode mode = RegistryInitMode.staleThenRefresh,
  }) async {
    if (_initialized) return;

    final dir = _customStorageDir ?? await _defaultStorageDir();
    _storage = RegistryStorage(dir);
    _http = HttpTransport(client: _testHttpClient, timeout: _httpTimeout);
    if (_bundledAssetPath != null) {
      _bundle = AssetBundleLoader(
        assetPath: _bundledAssetPath,
        bundle: _testBundle,
      );
    }

    if (await _tryLoadLocal()) {
      _initialized = true;
      // Task 11: schedule background refresh here.
      return;
    }

    if (_bundle != null && await _seedFromBundle()) {
      _initialized = true;
      // Task 11: schedule background refresh here.
      return;
    }

    // Task 11 will add the network fallback. For now, fail loudly.
    throw const RegistryUnavailableException(
      'No local cache and no bundle available, and network fallback '
      'is not yet implemented.',
    );
  }

  /// Returns a [File] pointing to [relPath] under the current version.
  ///
  /// Throws [StateError] if [init] has not completed.
  /// Throws [RegistryFileNotFoundException] if [relPath] is not in the
  /// current manifest or the file is missing on disk.
  Future<File> getFile(String relPath) async {
    _ensureInitialized();
    final m = _activeManifest!;
    if (m.findByPath(relPath) == null) {
      throw RegistryFileNotFoundException(relPath);
    }
    final path = _storage.resolveVersionFilePath(_activeVersion!, relPath);
    final f = File(path);
    if (!await f.exists()) {
      throw RegistryFileNotFoundException(relPath);
    }
    return f;
  }

  /// Reads [relPath] as UTF-8 JSON and returns the decoded value.
  ///
  /// Throws [StateError] if [init] has not completed.
  /// Throws [RegistryFileNotFoundException] if [relPath] is not found.
  Future<dynamic> getJson(String relPath) async {
    final f = await getFile(relPath);
    return jsonDecode(await f.readAsString());
  }

  /// Releases resources held by this instance.
  ///
  /// Safe to call multiple times (idempotent). After [dispose], the registry
  /// must not be used.
  Future<void> dispose() async {
    if (!_updateController.isClosed) await _updateController.close();
    // _http may not be initialized if init() was never called.
    try {
      _http.close();
    } catch (_) {}
  }

  // ---------------- internals ----------------

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('RemoteRegistry.init() has not completed.');
    }
  }

  Future<Directory> _defaultStorageDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, _subdirectory));
    await d.create(recursive: true);
    return d;
  }

  Future<bool> _tryLoadLocal() async {
    final version = await _storage.readCurrentVersion();
    if (version == null) return false;
    final m = await _storage.readManifest(version);
    if (m == null) return false;
    if (!await _storage.hasAllFiles(version, m)) return false;
    _activeVersion = version;
    _activeManifest = m;
    return true;
  }

  Future<bool> _seedFromBundle() async {
    final bundle = _bundle!;
    final m = await bundle.loadManifest();
    if (m == null) return false;
    try {
      await _storage.writeManifest(m.version, m);
      for (final f in m.files) {
        final bytes = await bundle.loadFile(f.path);
        await _storage.writeVersionFile(
          version: m.version,
          file: f,
          bytes: bytes,
        );
      }
      await _storage.writeCurrentVersion(m.version);
      _activeVersion = m.version;
      _activeManifest = m;
      return true;
    } on RegistryIntegrityException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  static Uri _normalizeBase(String raw) {
    final s = raw.endsWith('/') ? raw : '$raw/';
    return Uri.parse(s);
  }
}
