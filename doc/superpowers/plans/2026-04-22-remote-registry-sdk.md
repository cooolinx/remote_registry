# remote_registry SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `remote_registry`, a Flutter package that lets apps pull JSON/binary config files from a CDN-backed registry, verify SHA-256 integrity, cache locally, fall back to bundled assets, and expose a simple `getFile` / `getJson` API.

**Architecture:** Single Flutter library with a small, pure-Dart core plus Flutter-only bindings (`path_provider`, `rootBundle`). At `init()` time the registry uses stale-then-refresh: local cache wins → else bundled asset snapshot wins → else blocking network. New versions always download in the background and become active next `init()`. Every file is SHA-256 verified against `manifest.json`; verification failure never writes to disk.

**Tech Stack:** Dart 3.3+, Flutter 3.22+, `package:http`, `package:crypto`, `package:path_provider`, `package:path`, `package:test` + `package:mocktail`.

---

## Registry Conventions (Contract)

These URL paths and file schemas are the public contract between the SDK and any registry that uses it.

```
<baseUrl>/latest.json                              -> LatestPointer
<baseUrl>/versions/v<semver>/manifest.json         -> Manifest
<baseUrl>/versions/v<semver>/<file.path>           -> raw bytes
```

**`latest.json`** (LatestPointer):
```json
{ "version": "0.1.0" }
```

**`manifest.json`** (Manifest):
```json
{
  "version": "0.1.0",
  "files": [
    { "path": "models/openai.json", "sha256": "e3b0c4...", "size": 1234 },
    { "path": "assets/logo.png",    "sha256": "a1b2c3...", "size": 45678 }
  ]
}
```

- `path` is a POSIX relative path (no `..`, no leading `/`).
- `sha256` is lowercase hex of the file bytes.
- `size` is optional but, if present, the SDK validates byte length.

## Storage Layout (Disk)

```
<storageDir>/
  state.json                     # { "currentVersion": "0.1.0" }
  versions/
    v0.1.0/
      manifest.json
      models/openai.json
      assets/logo.png
    v0.0.9/                      # retained by GC (keep last 2)
      ...
```

`state.json` is atomic-written (write to `state.json.tmp` then rename).

## Public API Surface

```dart
// lib/remote_registry.dart (barrel)
export 'src/remote_registry.dart' show RemoteRegistry, RegistryInitMode;
export 'src/errors.dart'          show RegistryException,
                                       RegistryNetworkException,
                                       RegistryIntegrityException,
                                       RegistryUnavailableException,
                                       RegistryFileNotFoundException;
```

```dart
// Default mode: Application Support dir + subdirectory
RemoteRegistry({
  required String baseUrl,
  String subdirectory = 'remote_registry',
  String? bundledAssetPath,        // e.g. 'assets/registry/'
  Duration httpTimeout = const Duration(seconds: 30),
  int maxConcurrentDownloads = 4,
  int keepVersions = 2,
});

// Custom storage directory
RemoteRegistry.withStorage({
  required String baseUrl,
  required Directory storageDir,
  String? bundledAssetPath,
  Duration httpTimeout = const Duration(seconds: 30),
  int maxConcurrentDownloads = 4,
  int keepVersions = 2,
});

Future<void> init({RegistryInitMode mode = RegistryInitMode.staleThenRefresh});
Future<File>    getFile(String path);
Future<dynamic> getJson(String path);
String get currentVersion;
Stream<String> get onUpdate;       // emits new version string after background refresh
Future<void> dispose();
```

---

## File Structure

```
pubspec.yaml
analysis_options.yaml
.gitignore
LICENSE                      (MIT)
README.md
CHANGELOG.md

lib/
  remote_registry.dart                       # barrel export
  src/
    remote_registry.dart                     # main class
    errors.dart                              # exception hierarchy
    integrity.dart                           # verifyBytes(bytes, sha256)
    models/
      latest.dart                            # LatestPointer
      manifest.dart                          # Manifest, ManifestFile
    storage/
      registry_storage.dart                  # disk layout read/write
    transport/
      http_transport.dart                    # fetch JSON / bytes
    bundle/
      asset_bundle_loader.dart               # read from rootBundle
    internal/
      concurrency.dart                       # bounded parallel downloader
      semver.dart                            # compare "0.1.0" < "0.2.0"

bin/
  sync_bundle.dart                           # `dart run remote_registry:sync_bundle`

test/
  integrity_test.dart
  models/manifest_test.dart
  models/latest_test.dart
  storage/registry_storage_test.dart
  transport/http_transport_test.dart
  bundle/asset_bundle_loader_test.dart
  internal/concurrency_test.dart
  internal/semver_test.dart
  remote_registry_init_test.dart
  remote_registry_refresh_test.dart
  remote_registry_get_test.dart
  fixtures/
    v0.1.0/manifest.json
    v0.1.0/models.json

example/
  pubspec.yaml
  lib/main.dart
  assets/registry/manifest.json
  assets/registry/models.json
```

---

## Task 1: Project Scaffolding

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `LICENSE`, `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Create `pubspec.yaml`**

```yaml
name: remote_registry
description: Pull JSON and binary config files from a CDN-backed registry with SHA-256 integrity, local caching, and bundled-asset fallback.
version: 0.1.0
homepage: https://github.com/<owner>/remote_registry
repository: https://github.com/<owner>/remote_registry

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  crypto: ^3.0.3
  path_provider: ^2.1.0
  path: ^1.9.0
  meta: ^1.11.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: ^1.25.0
  mocktail: ^1.0.3
  lints: ^4.0.0

flutter:
```

- [ ] **Step 2: Create `analysis_options.yaml`**

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    missing_return: error
    unused_import: error

linter:
  rules:
    - avoid_print
    - prefer_final_locals
    - prefer_const_constructors
    - always_declare_return_types
    - public_member_api_docs
```

- [ ] **Step 3: Create `.gitignore`**

```gitignore
.dart_tool/
.packages
.pub-cache/
.pub/
build/
pubspec.lock
.flutter-plugins
.flutter-plugins-dependencies
.idea/
.vscode/
*.iml
coverage/
```

- [ ] **Step 4: Create `LICENSE` (MIT), `CHANGELOG.md`, replace `README.md`**

`CHANGELOG.md`:
```markdown
# Changelog

## 0.1.0 (unreleased)

- Initial release.
```

`README.md`: one-paragraph stub — full docs come in Task 13.

- [ ] **Step 5: Install deps and verify**

Run: `flutter pub get`
Expected: `Got dependencies!`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter package"
```

---

## Task 2: Error Hierarchy

**Files:**
- Create: `lib/src/errors.dart`
- Test: `test/errors_test.dart`

- [ ] **Step 1: Write failing test**

`test/errors_test.dart`:
```dart
import 'package:remote_registry/src/errors.dart';
import 'package:test/test.dart';

void main() {
  test('RegistryIntegrityException exposes path and expected/actual hashes', () {
    final e = RegistryIntegrityException(
      path: 'models.json',
      expectedSha256: 'aaa',
      actualSha256: 'bbb',
    );
    expect(e.path, 'models.json');
    expect(e.expectedSha256, 'aaa');
    expect(e.actualSha256, 'bbb');
    expect(e.toString(), contains('models.json'));
    expect(e, isA<RegistryException>());
  });

  test('RegistryFileNotFoundException carries path', () {
    final e = RegistryFileNotFoundException('missing.json');
    expect(e.path, 'missing.json');
    expect(e, isA<RegistryException>());
  });

  test('RegistryNetworkException wraps cause', () {
    final cause = Exception('socket');
    final e = RegistryNetworkException('fetch failed', cause);
    expect(e.cause, same(cause));
    expect(e, isA<RegistryException>());
  });

  test('RegistryUnavailableException is thrown when no source works', () {
    final e = RegistryUnavailableException('no network and no bundle');
    expect(e, isA<RegistryException>());
  });
}
```

- [ ] **Step 2: Run — expect fail**

Run: `flutter test test/errors_test.dart`
Expected: file not found / symbol not defined.

- [ ] **Step 3: Implement**

`lib/src/errors.dart`:
```dart
/// Base class for all [remote_registry] exceptions.
abstract class RegistryException implements Exception {
  const RegistryException(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a network fetch fails (DNS, timeout, non-2xx).
class RegistryNetworkException extends RegistryException {
  const RegistryNetworkException(super.message, [this.cause]);
  final Object? cause;
}

/// Thrown when downloaded bytes fail SHA-256 verification.
class RegistryIntegrityException extends RegistryException {
  RegistryIntegrityException({
    required this.path,
    required this.expectedSha256,
    required this.actualSha256,
  }) : super(
          'Integrity check failed for $path '
          '(expected $expectedSha256, got $actualSha256)',
        );
  final String path;
  final String expectedSha256;
  final String actualSha256;
}

/// Thrown when a requested file is not in the current manifest.
class RegistryFileNotFoundException extends RegistryException {
  RegistryFileNotFoundException(this.path) : super('File not found: $path');
  final String path;
}

/// Thrown when no usable version can be resolved
/// (no cache, no bundle, no network).
class RegistryUnavailableException extends RegistryException {
  const RegistryUnavailableException(super.message);
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/errors_test.dart`
Expected: All tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/src/errors.dart test/errors_test.dart
git commit -m "feat: add registry exception hierarchy"
```

---

## Task 3: Models — LatestPointer and Manifest

**Files:**
- Create: `lib/src/models/latest.dart`, `lib/src/models/manifest.dart`
- Test: `test/models/latest_test.dart`, `test/models/manifest_test.dart`

- [ ] **Step 1: Write failing tests for `LatestPointer`**

`test/models/latest_test.dart`:
```dart
import 'dart:convert';
import 'package:remote_registry/src/models/latest.dart';
import 'package:test/test.dart';

void main() {
  test('parses valid JSON', () {
    final p = LatestPointer.fromJson(jsonDecode('{"version":"1.2.3"}') as Map<String, dynamic>);
    expect(p.version, '1.2.3');
  });

  test('rejects missing version', () {
    expect(
      () => LatestPointer.fromJson(<String, dynamic>{}),
      throwsFormatException,
    );
  });

  test('rejects non-string version', () {
    expect(
      () => LatestPointer.fromJson(<String, dynamic>{'version': 123}),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Write failing tests for `Manifest`**

`test/models/manifest_test.dart`:
```dart
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
```

- [ ] **Step 3: Run — expect fail**

Run: `flutter test test/models/`
Expected: compilation failure (files don't exist).

- [ ] **Step 4: Implement models**

`lib/src/models/latest.dart`:
```dart
import 'package:meta/meta.dart';

/// Points to the current "live" registry version.
/// Loaded from `<baseUrl>/latest.json`.
@immutable
class LatestPointer {
  const LatestPointer({required this.version});

  final String version;

  factory LatestPointer.fromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v is! String || v.isEmpty) {
      throw const FormatException('latest.json: "version" must be a non-empty string');
    }
    return LatestPointer(version: v);
  }

  Map<String, dynamic> toJson() => {'version': version};
}
```

`lib/src/models/manifest.dart`:
```dart
import 'package:meta/meta.dart';

@immutable
class ManifestFile {
  const ManifestFile({required this.path, required this.sha256, this.size});

  final String path;
  final String sha256;
  final int? size;

  factory ManifestFile.fromJson(Map<String, dynamic> json) {
    final p = json['path'];
    if (p is! String || p.isEmpty) {
      throw const FormatException('manifest file: "path" must be non-empty string');
    }
    if (p.startsWith('/')) {
      throw FormatException('manifest file path must be relative: $p');
    }
    final segments = p.split('/');
    if (segments.contains('..') || segments.contains('.')) {
      throw FormatException('manifest file path must not contain ".." or ".": $p');
    }
    final s = json['sha256'];
    if (s is! String || s.isEmpty) {
      throw FormatException('manifest file "$p": sha256 must be non-empty');
    }
    final sz = json['size'];
    if (sz != null && sz is! int) {
      throw FormatException('manifest file "$p": size must be int if present');
    }
    return ManifestFile(path: p, sha256: s, size: sz as int?);
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'sha256': sha256,
        if (size != null) 'size': size,
      };
}

@immutable
class Manifest {
  const Manifest({required this.version, required this.files});

  final String version;
  final List<ManifestFile> files;

  factory Manifest.fromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v is! String || v.isEmpty) {
      throw const FormatException('manifest: "version" must be non-empty string');
    }
    final rawFiles = json['files'];
    if (rawFiles is! List) {
      throw const FormatException('manifest: "files" must be a list');
    }
    final files = rawFiles
        .map((e) => ManifestFile.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return Manifest(version: v, files: files);
  }

  ManifestFile? findByPath(String path) {
    for (final f in files) {
      if (f.path == path) return f;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'files': files.map((f) => f.toJson()).toList(),
      };
}
```

- [ ] **Step 5: Run — expect pass**

Run: `flutter test test/models/`
Expected: all tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/src/models/ test/models/
git commit -m "feat: add LatestPointer and Manifest models with validation"
```

---

## Task 4: Integrity Verifier

**Files:**
- Create: `lib/src/integrity.dart`
- Test: `test/integrity_test.dart`

- [ ] **Step 1: Write failing test**

`test/integrity_test.dart`:
```dart
import 'dart:convert';
import 'package:remote_registry/src/errors.dart';
import 'package:remote_registry/src/integrity.dart';
import 'package:test/test.dart';

void main() {
  // Known: sha256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
  final helloBytes = utf8.encode('hello');
  const helloSha =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  test('sha256Hex produces lowercase hex digest', () {
    expect(sha256Hex(helloBytes), helloSha);
  });

  test('verifyBytes returns on match (case-insensitive)', () {
    verifyBytes(path: 'x', bytes: helloBytes, expectedSha256: helloSha);
    verifyBytes(path: 'x', bytes: helloBytes, expectedSha256: helloSha.toUpperCase());
  });

  test('verifyBytes throws RegistryIntegrityException on mismatch', () {
    expect(
      () => verifyBytes(path: 'x', bytes: helloBytes, expectedSha256: 'deadbeef'),
      throwsA(isA<RegistryIntegrityException>()
          .having((e) => e.path, 'path', 'x')
          .having((e) => e.actualSha256, 'actual', helloSha)),
    );
  });

  test('verifyBytes throws when size mismatches', () {
    expect(
      () => verifyBytes(
          path: 'x',
          bytes: helloBytes,
          expectedSha256: helloSha,
          expectedSize: 999),
      throwsA(isA<RegistryIntegrityException>()),
    );
  });
}
```

- [ ] **Step 2: Run — expect fail**

Run: `flutter test test/integrity_test.dart`

- [ ] **Step 3: Implement**

`lib/src/integrity.dart`:
```dart
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'errors.dart';

/// Computes lowercase hex SHA-256 of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Verifies [bytes] against [expectedSha256] (and optional [expectedSize]).
/// Throws [RegistryIntegrityException] on mismatch.
void verifyBytes({
  required String path,
  required Uint8List bytes,
  required String expectedSha256,
  int? expectedSize,
}) {
  if (expectedSize != null && bytes.length != expectedSize) {
    throw RegistryIntegrityException(
      path: path,
      expectedSha256: expectedSha256,
      actualSha256: 'size=${bytes.length}!=$expectedSize',
    );
  }
  final actual = sha256Hex(bytes);
  if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
    throw RegistryIntegrityException(
      path: path,
      expectedSha256: expectedSha256.toLowerCase(),
      actualSha256: actual,
    );
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/integrity_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/src/integrity.dart test/integrity_test.dart
git commit -m "feat: add SHA-256 integrity verifier"
```

---

## Task 5: Semver Comparator

**Files:**
- Create: `lib/src/internal/semver.dart`
- Test: `test/internal/semver_test.dart`

Needed early so refresh logic can compare `localVersion` vs `remoteVersion`. We only support the subset `MAJOR.MINOR.PATCH` (no pre-release tags) — keep it small.

- [ ] **Step 1: Write failing test**

```dart
import 'package:remote_registry/src/internal/semver.dart';
import 'package:test/test.dart';

void main() {
  test('compareSemver: equal', () {
    expect(compareSemver('1.2.3', '1.2.3'), 0);
  });
  test('compareSemver: major/minor/patch ordering', () {
    expect(compareSemver('1.0.0', '2.0.0'), lessThan(0));
    expect(compareSemver('2.0.0', '1.0.0'), greaterThan(0));
    expect(compareSemver('1.1.0', '1.2.0'), lessThan(0));
    expect(compareSemver('1.2.0', '1.2.1'), lessThan(0));
  });
  test('compareSemver: numeric, not lexical', () {
    expect(compareSemver('1.10.0', '1.2.0'), greaterThan(0));
  });
  test('compareSemver: rejects malformed', () {
    expect(() => compareSemver('1.2', '1.2.3'), throwsFormatException);
    expect(() => compareSemver('abc', '1.2.3'), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

`lib/src/internal/semver.dart`:
```dart
/// Compares two `MAJOR.MINOR.PATCH` strings. Returns negative if [a] < [b],
/// 0 if equal, positive if [a] > [b]. Throws [FormatException] on bad input.
int compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

List<int> _parse(String s) {
  final parts = s.split('.');
  if (parts.length != 3) throw FormatException('Bad semver: $s');
  return parts.map((p) {
    final n = int.tryParse(p);
    if (n == null || n < 0) throw FormatException('Bad semver: $s');
    return n;
  }).toList(growable: false);
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add lib/src/internal/semver.dart test/internal/semver_test.dart
git commit -m "feat: add semver comparator"
```

---

## Task 6: Bounded Parallel Downloader

**Files:**
- Create: `lib/src/internal/concurrency.dart`
- Test: `test/internal/concurrency_test.dart`

A small utility: run N async tasks with max concurrency. First failure cancels remaining (for download-set atomicity).

- [ ] **Step 1: Write failing test**

```dart
import 'dart:async';
import 'package:remote_registry/src/internal/concurrency.dart';
import 'package:test/test.dart';

void main() {
  test('runBounded runs all tasks and preserves order', () async {
    final results = await runBounded<int>(
      maxConcurrent: 2,
      tasks: List.generate(
        5,
        (i) => () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return i * 2;
        },
      ),
    );
    expect(results, [0, 2, 4, 6, 8]);
  });

  test('runBounded enforces max concurrency', () async {
    var active = 0;
    var peak = 0;
    final tasks = List.generate(
      6,
      (_) => () async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return 0;
      },
    );
    await runBounded<int>(maxConcurrent: 2, tasks: tasks);
    expect(peak, lessThanOrEqualTo(2));
  });

  test('runBounded propagates first error and stops pending starts', () async {
    var started = 0;
    final tasks = List.generate(
      10,
      (i) => () async {
        started++;
        if (i == 0) throw StateError('boom');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return i;
      },
    );
    await expectLater(
      runBounded<int>(maxConcurrent: 2, tasks: tasks),
      throwsA(isA<StateError>()),
    );
    // Not all should start.
    expect(started, lessThan(10));
  });
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

`lib/src/internal/concurrency.dart`:
```dart
import 'dart:async';

typedef AsyncTask<T> = Future<T> Function();

/// Runs [tasks] with at most [maxConcurrent] in flight at once.
/// Returns results in the same order as [tasks]. On first failure,
/// aborts launching additional tasks and rethrows.
Future<List<T>> runBounded<T>({
  required int maxConcurrent,
  required List<AsyncTask<T>> tasks,
}) async {
  if (maxConcurrent < 1) {
    throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'must be >= 1');
  }
  final results = List<T?>.filled(tasks.length, null);
  var next = 0;
  Object? error;
  StackTrace? errorStack;

  Future<void> worker() async {
    while (error == null) {
      final i = next++;
      if (i >= tasks.length) return;
      try {
        results[i] = await tasks[i]();
      } catch (e, st) {
        error ??= e;
        errorStack ??= st;
        return;
      }
    }
  }

  final workers = List.generate(
    maxConcurrent.clamp(1, tasks.length == 0 ? 1 : tasks.length),
    (_) => worker(),
  );
  await Future.wait(workers);
  if (error != null) {
    Error.throwWithStackTrace(error!, errorStack ?? StackTrace.current);
  }
  return results.cast<T>();
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add lib/src/internal/concurrency.dart test/internal/concurrency_test.dart
git commit -m "feat: add bounded parallel runner"
```

---

## Task 7: HTTP Transport

**Files:**
- Create: `lib/src/transport/http_transport.dart`
- Test: `test/transport/http_transport_test.dart`

Thin wrapper over `package:http`. Converts non-2xx and exceptions to `RegistryNetworkException`. Testable via `http.Client` injection (internal only, not exposed on `RemoteRegistry`).

- [ ] **Step 1: Write failing test**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_registry/src/errors.dart';
import 'package:remote_registry/src/transport/http_transport.dart';
import 'package:test/test.dart';

void main() {
  test('fetchJson decodes JSON on 200', () async {
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://x/latest.json');
      return http.Response(jsonEncode({'version': '1.0.0'}), 200,
          headers: {'content-type': 'application/json'});
    });
    final t = HttpTransport(client: client);
    final body = await t.fetchJson(Uri.parse('https://x/latest.json'));
    expect(body, {'version': '1.0.0'});
  });

  test('fetchBytes returns Uint8List on 200', () async {
    final client = MockClient((req) async {
      return http.Response.bytes([1, 2, 3], 200);
    });
    final t = HttpTransport(client: client);
    final bytes = await t.fetchBytes(Uri.parse('https://x/file'));
    expect(bytes, isA<Uint8List>());
    expect(bytes, [1, 2, 3]);
  });

  test('non-2xx raises RegistryNetworkException', () async {
    final client = MockClient((_) async => http.Response('nope', 404));
    final t = HttpTransport(client: client);
    expect(
      () => t.fetchJson(Uri.parse('https://x/y.json')),
      throwsA(isA<RegistryNetworkException>()),
    );
  });

  test('IOException wrapped as RegistryNetworkException', () async {
    final client = MockClient((_) async => throw Exception('socket down'));
    final t = HttpTransport(client: client);
    expect(
      () => t.fetchBytes(Uri.parse('https://x/y')),
      throwsA(isA<RegistryNetworkException>()),
    );
  });
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

`lib/src/transport/http_transport.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../errors.dart';

/// HTTP layer. Keep [HttpTransport] package-private-ish: not exported from
/// the public barrel, so users can't inject their own client.
class HttpTransport {
  HttpTransport({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  final http.Client _client;
  final Duration _timeout;

  Future<Map<String, dynamic>> fetchJson(Uri url) async {
    final bytes = await fetchBytes(url);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw RegistryNetworkException('Expected JSON object at $url');
    }
    return decoded;
  }

  Future<Uint8List> fetchBytes(Uri url) async {
    try {
      final resp = await _client.get(url).timeout(_timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw RegistryNetworkException(
          'GET $url -> HTTP ${resp.statusCode}',
        );
      }
      return resp.bodyBytes;
    } on RegistryNetworkException {
      rethrow;
    } catch (e) {
      throw RegistryNetworkException('GET $url failed: $e', e);
    }
  }

  void close() => _client.close();
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add lib/src/transport/ test/transport/
git commit -m "feat: add HTTP transport"
```

---

## Task 8: Registry Storage

**Files:**
- Create: `lib/src/storage/registry_storage.dart`
- Test: `test/storage/registry_storage_test.dart`

Owns the disk layout. Pure Dart (no Flutter deps) so it tests with `Directory.systemTemp`.

- [ ] **Step 1: Write failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:remote_registry/src/models/manifest.dart';
import 'package:remote_registry/src/storage/registry_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('registry_test_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('readState returns null on fresh dir', () async {
    final s = RegistryStorage(root);
    expect(await s.readCurrentVersion(), isNull);
  });

  test('writeState then read round-trips', () async {
    final s = RegistryStorage(root);
    await s.writeCurrentVersion('0.1.0');
    expect(await s.readCurrentVersion(), '0.1.0');
  });

  test('writeVersionFile verifies and stores at versioned path', () async {
    final s = RegistryStorage(root);
    final bytes = utf8.encode('hello');
    const sha = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
    await s.writeVersionFile(
      version: '0.1.0',
      file: ManifestFile(path: 'a/b.txt', sha256: sha),
      bytes: bytes,
    );
    final f = File(p.join(root.path, 'versions', 'v0.1.0', 'a', 'b.txt'));
    expect(await f.exists(), isTrue);
    expect(await f.readAsBytes(), bytes);
  });

  test('writeVersionFile rejects bad sha', () async {
    final s = RegistryStorage(root);
    expect(
      () => s.writeVersionFile(
        version: '0.1.0',
        file: const ManifestFile(path: 'x', sha256: 'deadbeef'),
        bytes: [1, 2, 3],
      ),
      throwsA(anything),
    );
    // Must not have written the file.
    final f = File(p.join(root.path, 'versions', 'v0.1.0', 'x'));
    expect(await f.exists(), isFalse);
  });

  test('resolveFile returns path under current version', () async {
    final s = RegistryStorage(root);
    await s.writeCurrentVersion('0.1.0');
    final path = s.resolveVersionFilePath('0.1.0', 'a/b.txt');
    expect(p.isWithin(root.path, path), isTrue);
    expect(path, endsWith(p.join('versions', 'v0.1.0', 'a', 'b.txt')));
  });

  test('listVersions returns sorted versions', () async {
    final s = RegistryStorage(root);
    await Directory(p.join(root.path, 'versions', 'v0.0.9')).create(recursive: true);
    await Directory(p.join(root.path, 'versions', 'v0.1.0')).create(recursive: true);
    await Directory(p.join(root.path, 'versions', 'v0.2.0')).create(recursive: true);
    final versions = await s.listInstalledVersions();
    expect(versions, ['0.0.9', '0.1.0', '0.2.0']);
  });

  test('gcOldVersions keeps the last N', () async {
    final s = RegistryStorage(root);
    for (final v in ['0.0.7', '0.0.8', '0.0.9', '0.1.0']) {
      await Directory(p.join(root.path, 'versions', 'v$v')).create(recursive: true);
    }
    await s.gcOldVersions(keep: 2, current: '0.1.0');
    expect(await s.listInstalledVersions(), ['0.0.9', '0.1.0']);
  });
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

`lib/src/storage/registry_storage.dart`:
```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../integrity.dart';
import '../internal/semver.dart';
import '../models/manifest.dart';

class RegistryStorage {
  RegistryStorage(this.root);
  final Directory root;

  static const _stateFile = 'state.json';
  static const _versionsDir = 'versions';

  File _stateFileRef() => File(p.join(root.path, _stateFile));

  Directory _versionDir(String version) =>
      Directory(p.join(root.path, _versionsDir, 'v$version'));

  String resolveVersionFilePath(String version, String relPath) =>
      p.join(_versionDir(version).path, relPath);

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

  Future<void> writeCurrentVersion(String version) async {
    await root.create(recursive: true);
    final tmp = File(p.join(root.path, '$_stateFile.tmp'));
    await tmp.writeAsString(jsonEncode({'currentVersion': version}), flush: true);
    await tmp.rename(_stateFileRef().path);
  }

  Future<void> writeManifest(String version, Manifest m) async {
    final dir = _versionDir(version);
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, 'manifest.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(m.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Future<Manifest?> readManifest(String version) async {
    final f = File(p.join(_versionDir(version).path, 'manifest.json'));
    if (!await f.exists()) return null;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return Manifest.fromJson(json);
  }

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

  Future<void> gcOldVersions({required int keep, required String current}) async {
    final all = await listInstalledVersions();
    if (all.length <= keep) return;
    final toKeep = all.sublist(all.length - keep).toSet()..add(current);
    for (final v in all) {
      if (!toKeep.contains(v)) {
        final d = _versionDir(v);
        if (await d.exists()) await d.delete(recursive: true);
      }
    }
  }

  /// Returns true if every file in [m] exists on disk at the expected path.
  Future<bool> hasAllFiles(String version, Manifest m) async {
    for (final f in m.files) {
      if (!await File(resolveVersionFilePath(version, f.path)).exists()) {
        return false;
      }
    }
    return true;
  }
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add lib/src/storage/ test/storage/
git commit -m "feat: add registry disk storage"
```

---

## Task 9: Asset Bundle Loader

**Files:**
- Create: `lib/src/bundle/asset_bundle_loader.dart`
- Test: `test/bundle/asset_bundle_loader_test.dart`

Reads `<bundledAssetPath>manifest.json` and file bytes from `rootBundle`. Uses Flutter's `AssetBundle` (injectable for testing via `TestDefaultBinaryMessenger`).

- [ ] **Step 1: Write failing test**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_registry/src/bundle/asset_bundle_loader.dart';

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
        {'path': 'a.txt', 'sha256': 'ignored-in-asset-load', 'size': 5},
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
    expect(m.version, '0.1.0');

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
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

`lib/src/bundle/asset_bundle_loader.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/manifest.dart';

class AssetBundleLoader {
  AssetBundleLoader({required this.assetPath, AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle,
        _prefix = assetPath.endsWith('/') ? assetPath : '$assetPath/';

  final String assetPath;
  final AssetBundle _bundle;
  final String _prefix;

  Future<Manifest?> loadManifest() async {
    try {
      final data = await _bundle.load('${_prefix}manifest.json');
      final json = jsonDecode(utf8.decode(data.buffer.asUint8List()))
          as Map<String, dynamic>;
      return Manifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> loadFile(String relPath) async {
    final data = await _bundle.load('$_prefix$relPath');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/bundle/asset_bundle_loader_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/src/bundle/ test/bundle/
git commit -m "feat: add asset bundle loader"
```

---

## Task 10: RemoteRegistry — Construction + Cold Init (offline paths)

Now the central class. First pass: construction, local cache hit, bundle fallback. **No network code yet** — refresh comes in Task 11.

**Files:**
- Create: `lib/src/remote_registry.dart`
- Create: `lib/remote_registry.dart` (barrel)
- Test: `test/remote_registry_init_test.dart`

- [ ] **Step 1: Write failing test (local cache hit)**

`test/remote_registry_init_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:remote_registry/remote_registry.dart';
import 'package:remote_registry/src/models/manifest.dart';
import 'package:remote_registry/src/storage/registry_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rr_init_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> seedCache(String version, Map<String, String> files) async {
    final s = RegistryStorage(root);
    final m = Manifest(
      version: version,
      files: files.entries
          .map((e) => ManifestFile(
                path: e.key,
                sha256: _sha(e.value),
                size: utf8.encode(e.value).length,
              ))
          .toList(),
    );
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

  test('init uses local cache when present', () async {
    await seedCache('0.1.0', {'a.json': '{"x":1}'});
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://unused.example/',
      storageDir: root,
    );
    await r.init();
    expect(r.currentVersion, '0.1.0');
    final f = await r.getFile('a.json');
    expect(await f.readAsString(), '{"x":1}');
    await r.dispose();
  });

  test('init with no cache and no bundle and no network throws Unavailable',
      () async {
    final r = RemoteRegistry.withStorage(
      baseUrl: 'http://127.0.0.1:1', // unroutable
      storageDir: root,
    );
    expect(() => r.init(), throwsA(isA<RegistryUnavailableException>()));
    await r.dispose();
  });
}

String _sha(String s) {
  // Use verifier-compatible sha; defer to real crypto in fixture helpers.
  return sha256Hex(utf8.encode(s));
}
```

Note: the test above references `sha256Hex` — import from `package:remote_registry/src/integrity.dart` in the test file. (Add that import.)

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement the class skeleton (offline paths only)**

`lib/src/remote_registry.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bundle/asset_bundle_loader.dart';
import 'errors.dart';
import 'integrity.dart';
import 'internal/semver.dart';
import 'models/latest.dart';
import 'models/manifest.dart';
import 'storage/registry_storage.dart';
import 'transport/http_transport.dart';

enum RegistryInitMode {
  /// Use local cache / bundle immediately; refresh in background.
  staleThenRefresh,

  /// Always block until latest is fetched and verified.
  blockUntilLatest,
}

class RemoteRegistry {
  RemoteRegistry({
    required String baseUrl,
    String subdirectory = 'remote_registry',
    String? bundledAssetPath,
    Duration httpTimeout = const Duration(seconds: 30),
    int maxConcurrentDownloads = 4,
    int keepVersions = 2,
  })  : _baseUrl = _normalizeBase(baseUrl),
        _subdirectory = subdirectory,
        _customStorageDir = null,
        _bundledAssetPath = bundledAssetPath,
        _httpTimeout = httpTimeout,
        _maxConcurrent = maxConcurrentDownloads,
        _keepVersions = keepVersions;

  RemoteRegistry.withStorage({
    required String baseUrl,
    required Directory storageDir,
    String? bundledAssetPath,
    Duration httpTimeout = const Duration(seconds: 30),
    int maxConcurrentDownloads = 4,
    int keepVersions = 2,
  })  : _baseUrl = _normalizeBase(baseUrl),
        _subdirectory = '',
        _customStorageDir = storageDir,
        _bundledAssetPath = bundledAssetPath,
        _httpTimeout = httpTimeout,
        _maxConcurrent = maxConcurrentDownloads,
        _keepVersions = keepVersions;

  final Uri _baseUrl;
  final String _subdirectory;
  final Directory? _customStorageDir;
  final String? _bundledAssetPath;
  final Duration _httpTimeout;
  final int _maxConcurrent;
  final int _keepVersions;

  final _updateController = StreamController<String>.broadcast();
  Stream<String> get onUpdate => _updateController.stream;

  late final RegistryStorage _storage;
  late final HttpTransport _http;
  AssetBundleLoader? _bundle;

  Manifest? _activeManifest;
  String? _activeVersion;
  bool _initialized = false;

  String get currentVersion {
    final v = _activeVersion;
    if (v == null) {
      throw StateError('RemoteRegistry.init() has not completed.');
    }
    return v;
  }

  Future<void> init({RegistryInitMode mode = RegistryInitMode.staleThenRefresh}) async {
    if (_initialized) return;
    final dir = _customStorageDir ?? await _defaultStorageDir();
    _storage = RegistryStorage(dir);
    _http = HttpTransport(timeout: _httpTimeout);
    if (_bundledAssetPath != null) {
      _bundle = AssetBundleLoader(assetPath: _bundledAssetPath!);
    }

    final seeded = await _tryLoadLocal();
    if (seeded) {
      _initialized = true;
      // Task 11 will start background refresh here for staleThenRefresh.
      return;
    }

    if (_bundle != null) {
      final ok = await _seedFromBundle();
      if (ok) {
        _initialized = true;
        return;
      }
    }

    // Task 11: network fallback.
    throw const RegistryUnavailableException(
      'No local cache, no bundle, and network not yet implemented.',
    );
  }

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

  Future<dynamic> getJson(String relPath) async {
    final f = await getFile(relPath);
    return jsonDecode(await f.readAsString());
  }

  Future<void> dispose() async {
    await _updateController.close();
    _http.close();
  }

  // ---------------- internals ----------------

  void _ensureInitialized() {
    if (!_initialized) throw StateError('RemoteRegistry.init() has not completed.');
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
        await _storage.writeVersionFile(version: m.version, file: f, bytes: bytes);
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
```

`lib/remote_registry.dart`:
```dart
/// remote_registry — CDN-backed config registry client for Flutter.
library;

export 'src/remote_registry.dart' show RemoteRegistry, RegistryInitMode;
export 'src/errors.dart'
    show
        RegistryException,
        RegistryNetworkException,
        RegistryIntegrityException,
        RegistryFileNotFoundException,
        RegistryUnavailableException;
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/remote_registry_init_test.dart`
Expected: both tests pass. (The second test passes because `_tryLoadLocal` returns false, no bundle, and we throw `RegistryUnavailableException`.)

- [ ] **Step 5: Add test for bundle fallback**

Extend `test/remote_registry_init_test.dart` with:
```dart
test('init falls back to bundle when no cache', () async {
  // Use a fake bundle by constructing AssetBundleLoader directly via a test-only seam.
  // Since RemoteRegistry currently hardcodes rootBundle, add a constructor parameter
  // `@visibleForTesting AssetBundle? testBundle` to enable this test.
});
```

Add to `RemoteRegistry.withStorage`:
```dart
@visibleForTesting
final AssetBundle? testBundle;
```

...and wire it: `_bundle = AssetBundleLoader(assetPath: ..., bundle: testBundle)`.

Implement the test body using the `_FakeBundle` pattern from Task 9. Verify the seeded files end up on disk and `getFile` works.

- [ ] **Step 6: Run — expect pass**

- [ ] **Step 7: Commit**

```bash
git add lib/ test/remote_registry_init_test.dart
git commit -m "feat: RemoteRegistry construction + cache/bundle cold init"
```

---

## Task 11: RemoteRegistry — Network Refresh

Adds network-backed refresh: fetch `latest.json`, compare versions, download new version, verify, swap `currentVersion`.

**Files:**
- Modify: `lib/src/remote_registry.dart`
- Test: `test/remote_registry_refresh_test.dart`

- [ ] **Step 1: Extract the network fetch logic behind an injectable seam**

Add a test seam to `HttpTransport`: accept `http.Client` in constructor (already done in Task 7). Wire `RemoteRegistry` to accept an optional client:

```dart
// In RemoteRegistry (both constructors), add:
@visibleForTesting
final http.Client? testHttpClient;
```

Use it when constructing `_http` in `init()`.

- [ ] **Step 2: Write failing test (fresh install, network only)**

`test/remote_registry_refresh_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_registry/remote_registry.dart';
import 'package:remote_registry/src/integrity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('rr_net_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Build a client that serves a single version's registry.
  MockClient buildClient({
    required String version,
    required Map<String, String> files, // relPath -> text content
    int latestStatus = 200,
    int Function(String path)? fileStatusOverride,
    int? callCounter,
  }) {
    var calls = 0;
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
      calls++;
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
          final status = fileStatusOverride?.call(e.key) ?? 200;
          return http.Response(e.value, status);
        }
      }
      return http.Response('not found', 404);
    });
  }

  test('cold init (no cache, no bundle) downloads everything', () async {
    final client = buildClient(
      version: '0.1.0',
      files: {'a.json': '{"x":1}'},
    );
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: client,
    );
    await r.init(mode: RegistryInitMode.blockUntilLatest);
    expect(r.currentVersion, '0.1.0');
    final f = await r.getFile('a.json');
    expect(await f.readAsString(), '{"x":1}');
    await r.dispose();
  });

  test('refresh promotes newer version and GCs old', () async {
    // Seed 0.1.0.
    final seedClient = buildClient(
      version: '0.1.0',
      files: {'a.json': '{"v":1}'},
    );
    final seed = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: seedClient,
    );
    await seed.init(mode: RegistryInitMode.blockUntilLatest);
    await seed.dispose();

    // Now bump to 0.2.0.
    final client = buildClient(
      version: '0.2.0',
      files: {'a.json': '{"v":2}'},
    );
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: client,
      keepVersions: 1,
    );
    await r.init(mode: RegistryInitMode.blockUntilLatest);
    expect(r.currentVersion, '0.2.0');
    expect(await (await r.getFile('a.json')).readAsString(), '{"v":2}');
    // Old dir gone.
    expect(Directory('${root.path}/versions/v0.1.0').existsSync(), isFalse);
    await r.dispose();
  });

  test('stale-then-refresh swallows network failure', () async {
    // Seed 0.1.0.
    final seed = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: buildClient(
        version: '0.1.0',
        files: {'a.json': '{"v":1}'},
      ),
    );
    await seed.init(mode: RegistryInitMode.blockUntilLatest);
    await seed.dispose();

    // Network broken.
    final r = RemoteRegistry.withStorage(
      baseUrl: 'https://cdn.example/',
      storageDir: root,
      testHttpClient: buildClient(
        version: '0.1.0',
        files: {'a.json': '{"v":1}'},
        latestStatus: 500,
      ),
    );
    await r.init(); // staleThenRefresh is default — must not throw
    expect(r.currentVersion, '0.1.0');
    await r.dispose();
  });
}
```

- [ ] **Step 3: Implement `_refreshFromNetwork()`**

Add to `RemoteRegistry`:
```dart
Future<bool> _refreshFromNetwork({required bool blocking}) async {
  try {
    final latest = LatestPointer.fromJson(
      await _http.fetchJson(_baseUrl.resolve('latest.json')),
    );

    if (_activeVersion != null &&
        compareSemver(latest.version, _activeVersion!) <= 0) {
      return false; // already on latest or newer
    }

    final manifest = Manifest.fromJson(
      await _http.fetchJson(
        _baseUrl.resolve('versions/v${latest.version}/manifest.json'),
      ),
    );
    if (manifest.version != latest.version) {
      throw RegistryNetworkException(
        'Manifest version mismatch: latest=${latest.version} '
        'manifest=${manifest.version}',
      );
    }

    await _storage.writeManifest(manifest.version, manifest);
    await runBounded<void>(
      maxConcurrent: _maxConcurrent,
      tasks: manifest.files
          .map((f) => () async {
                final bytes = await _http.fetchBytes(
                  _baseUrl.resolve('versions/v${manifest.version}/${f.path}'),
                );
                await _storage.writeVersionFile(
                  version: manifest.version,
                  file: f,
                  bytes: bytes,
                );
              })
          .toList(),
    );
    await _storage.writeCurrentVersion(manifest.version);
    _activeVersion = manifest.version;
    _activeManifest = manifest;
    await _storage.gcOldVersions(keep: _keepVersions, current: manifest.version);
    if (!_updateController.isClosed) _updateController.add(manifest.version);
    return true;
  } catch (e) {
    if (blocking) rethrow;
    return false; // stale-then-refresh: swallow, keep the stale cache
  }
}
```

Wire into `init()`:
```dart
Future<void> init({RegistryInitMode mode = RegistryInitMode.staleThenRefresh}) async {
  if (_initialized) return;
  // ...existing setup...

  final seeded = await _tryLoadLocal();
  if (seeded) {
    _initialized = true;
    if (mode == RegistryInitMode.blockUntilLatest) {
      await _refreshFromNetwork(blocking: true);
    } else {
      unawaited(_refreshFromNetwork(blocking: false));
    }
    return;
  }

  if (_bundle != null && await _seedFromBundle()) {
    _initialized = true;
    if (mode == RegistryInitMode.blockUntilLatest) {
      await _refreshFromNetwork(blocking: true);
    } else {
      unawaited(_refreshFromNetwork(blocking: false));
    }
    return;
  }

  // No local, no bundle → must succeed online.
  try {
    await _refreshFromNetwork(blocking: true);
  } on RegistryException {
    rethrow;
  } catch (e) {
    throw RegistryUnavailableException('init failed: $e');
  }
  if (_activeVersion == null) {
    throw const RegistryUnavailableException(
      'No local cache, no bundle, and no network source.',
    );
  }
  _initialized = true;
}
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/remote_registry_refresh_test.dart test/remote_registry_init_test.dart`

- [ ] **Step 5: Add test: refresh promotes newer version**

- Seed cache with 0.1.0
- Mock CDN returning 0.2.0
- Call init with `blockUntilLatest`
- Assert `currentVersion == '0.2.0'`, old version GC'd per keepVersions

- [ ] **Step 6: Add test: refresh failure in staleThenRefresh doesn't break**

- Seed cache with 0.1.0
- Mock CDN: latest.json returns 500
- init() still resolves to 0.1.0; `getFile` still works

- [ ] **Step 7: Commit**

```bash
git add lib/ test/remote_registry_refresh_test.dart
git commit -m "feat: network-backed registry refresh with stale-then-refresh"
```

---

## Task 12: CLI — sync_bundle

**Files:**
- Create: `bin/sync_bundle.dart`
- Modify: `pubspec.yaml` (declare executable)
- Test: `test/bin_sync_bundle_test.dart` (spawns the CLI via `Process.run`)

- [ ] **Step 1: Write failing test**

`test/bin_sync_bundle_test.dart`:
```dart
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
      req.response.headers.contentType = ContentType.json;
      if (path == '/latest.json') {
        req.response.write(jsonEncode({'version': '0.1.0'}));
      } else if (path == '/versions/v0.1.0/manifest.json') {
        req.response.write(jsonEncode({
          'version': '0.1.0',
          'files': [
            {'path': 'a.txt',       'sha256': helloSha,  'size': hello.length},
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
  }, timeout: const Timeout(Duration(seconds: 30)));
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

`bin/sync_bundle.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:remote_registry/src/integrity.dart';
import 'package:remote_registry/src/models/latest.dart';
import 'package:remote_registry/src/models/manifest.dart';
import 'package:remote_registry/src/transport/http_transport.dart';

/// Usage:
///   dart run remote_registry:sync_bundle \
///       --base https://tavoai.dev/registry \
///       --out  example/assets/registry \
///       [--version 0.1.0]
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
    final version = opts['version'] ??
        LatestPointer.fromJson(await http.fetchJson(base.resolve('latest.json')))
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
        stderr.writeln('Integrity failed for ${f.path}');
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
    stderr.writeln('usage: sync_bundle --base <url> --out <dir> [--version X.Y.Z]');
    exit(64);
  }
  return m;
}
```

Add to `pubspec.yaml`:
```yaml
executables:
  sync_bundle:
```

- [ ] **Step 4: Run — expect pass**

Run: `flutter test test/bin_sync_bundle_test.dart`

- [ ] **Step 5: Commit**

```bash
git add bin/ pubspec.yaml test/bin_sync_bundle_test.dart
git commit -m "feat: add sync_bundle CLI"
```

---

## Task 13: Example App + README + Docs

**Files:**
- Create: `example/pubspec.yaml`, `example/lib/main.dart`, `example/assets/registry/{manifest.json,models.json}`
- Modify: `README.md`, `CHANGELOG.md`

- [ ] **Step 1: Scaffold `example/` as a minimal Flutter app**

Run: `flutter create --org dev.tavoai --template=app example`
Then replace `example/lib/main.dart` and `example/pubspec.yaml`:

`example/pubspec.yaml` must include:
```yaml
dependencies:
  flutter:
    sdk: flutter
  remote_registry:
    path: ../
flutter:
  assets:
    - assets/registry/
```

`example/lib/main.dart` (sketch):
```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:remote_registry/remote_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final registry = RemoteRegistry(
    baseUrl: 'https://tavoai.dev/registry',
    bundledAssetPath: 'assets/registry/',
  );
  await registry.init();
  runApp(MyApp(models: await registry.getJson('models.json')));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.models});
  final dynamic models;
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('remote_registry example')),
          body: Center(child: Text(const JsonEncoder.withIndent('  ').convert(models))),
        ),
      );
}
```

- [ ] **Step 2: Pre-populate the bundled snapshot**

Seed `example/assets/registry/manifest.json` and `example/assets/registry/models.json` by running the CLI against a real (or local) registry:
```bash
dart run remote_registry:sync_bundle --base https://tavoai.dev/registry --out example/assets/registry
```

- [ ] **Step 3: Write the public README**

`README.md` must cover:
- What it is + 30-second pitch
- Install (`dart pub add remote_registry`)
- Quick start (both constructors)
- Registry contract (latest.json, manifest.json, URL layout) — link to this plan's "Registry Conventions"
- Bundled-assets workflow + CLI usage
- Error handling table (each exception + when)
- Platforms: iOS, Android, macOS, Windows, Linux (no web)

- [ ] **Step 4: Update `CHANGELOG.md`**

```markdown
## 0.1.0

- Initial release.
- `RemoteRegistry` with default (app support dir) and `withStorage` constructors.
- Stale-then-refresh init with bundled-asset fallback.
- SHA-256 integrity verification on all downloads.
- `sync_bundle` CLI to snapshot a version into a Flutter assets directory.
```

- [ ] **Step 5: `flutter pub publish --dry-run`**

Run: `flutter pub publish --dry-run`
Expected: 0 warnings (or only the unavoidable "no versions yet on pub.dev").

- [ ] **Step 6: Final full-suite run**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add example/ README.md CHANGELOG.md
git commit -m "docs: example app, README, and 0.1.0 changelog"
```

---

## Post-plan checklist

- [ ] `flutter analyze` has zero warnings
- [ ] `flutter test --coverage`; coverage ≥ 80 % for `lib/src/**`
- [ ] `flutter pub publish --dry-run` is clean
- [ ] Tag `v0.1.0` and push
- [ ] (Deferred) `flutter pub publish` once you've validated against tavoai.dev from an example app

## Deferred (not in 0.1.0)

- ETag / If-None-Match for `latest.json` (currently always downloads it, ~hundreds of bytes — fine).
- Retry with backoff on transient network errors.
- Per-version file deduplication across versions (content-addressed store).
- Progress callbacks on downloads.
- `pub.dev` platform declarations for non-Flutter (we deliberately restrict to mobile+desktop).
