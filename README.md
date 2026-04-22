# remote_registry

A Flutter package for pulling JSON and binary config files from a CDN-backed registry, with SHA-256 integrity verification, local caching, and bundled-asset fallback.

Designed for apps that ship configuration (models, prompts, feature flags, images) out of band from app releases — update instantly via CDN without waiting for App Store review.

## Features

- **CDN-first, no server required.** Point at any static URL prefix that serves `latest.json` and `versions/v<semver>/...`.
- **SHA-256 verification** on every file — malformed bytes never reach disk.
- **Stale-then-refresh** init: app startup is offline-fast; new versions download in the background.
- **Bundled-asset fallback** for first-run-offline scenarios.
- **`File` and JSON accessors** — works for text, JSON, images, and other binary assets.
- **No web, no server-Dart, no isolate complexity.** Pure client-side.

Supported platforms: Android, iOS, macOS, Windows, Linux.

## Integration

End-to-end setup for a Flutter app, in order:

### 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  remote_registry: ^0.1.1
```

### 2. Declare the bundled-asset directory

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/registry/
```

### 3. Seed the bundled snapshot

Run once and commit the result:

```bash
dart run remote_registry:sync_bundle \
    --base https://yourcdn.example/registry \
    --out  assets/registry/
```

This pulls the current CDN snapshot (manifest + files, SHA-256 verified)
into `assets/registry/` so first-run users without network still work.

### 4. Initialize before `runApp`

```dart
import 'package:flutter/material.dart';
import 'package:remote_registry/remote_registry.dart';

late final RemoteRegistry registry;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registry = RemoteRegistry(
    baseUrl: 'https://yourcdn.example/registry',
    bundledAssetPath: 'assets/registry/',
  );
  await registry.init();
  runApp(const MyApp());
}
```

The default `init()` is stale-then-refresh: local cache (or bundle) wins
immediately, new versions download in the background and become active on
the next `init()`. See [Initialization modes](#initialization-modes) for
alternatives.

### 5. Read files anywhere in your app

```dart
final models = await registry.getJson('models.json');
final File logo = await registry.getFile('images/logo.png');
```

### 6. Keep the bundle fresh in CI

Add a sync step before every release build so the shipped snapshot doesn't
drift:

```yaml
# .github/workflows/release.yml
- name: Sync bundled registry snapshot
  run: |
    dart run remote_registry:sync_bundle \
      --base https://yourcdn.example/registry \
      --out  assets/registry/
- name: Commit if changed
  run: |
    if ! git diff --quiet assets/registry; then
      git config user.email "ci@example.com"
      git config user.name "ci"
      git add assets/registry
      git commit -m "chore: sync bundled registry snapshot"
      git push
    fi
```

Or schedule it as a weekly cron workflow, independent of releases.

## Registry convention

Your CDN must serve:

```
<baseUrl>/latest.json                              LatestPointer
<baseUrl>/versions/v<semver>/manifest.json         Manifest
<baseUrl>/versions/v<semver>/<file.path>           raw bytes
```

**`latest.json`:**
```json
{ "version": "0.1.0" }
```

The `version` field is accepted with or without a leading `v` /
`V` prefix — both `"0.1.0"` and `"v0.1.0"` resolve to the same
snapshot. The same tolerance applies to `manifest.json`'s
`version` and the CLI's `--version` flag. The `v` in the URL path
(`versions/v0.1.0/...`) is always literal.

**`manifest.json`:**
```json
{
  "version": "0.1.0",
  "files": [
    { "path": "models.json", "sha256": "e3b0c4...", "size": 1234 }
  ]
}
```

- `path` is a POSIX relative path — no `..`, no leading `/`, no backslashes.
- `sha256` is 64 lowercase hex chars.
- `size` is optional but enforced when present.

## Advanced usage

### Custom storage directory

```dart
final registry = RemoteRegistry.withStorage(
  baseUrl: '...',
  storageDir: Directory('/custom/path'),
);
```

### Initialization modes

- `RegistryInitMode.staleThenRefresh` (default) — return cached version immediately, refresh in background.
- `RegistryInitMode.blockUntilLatest` — always block until the network copy is verified.

### Listening for background updates

```dart
registry.onUpdate.listen((version) {
  print('Registry updated to $version');
});
```

## Error handling

| Exception | When |
|---|---|
| `RegistryUnavailableException` | No cache, no bundle, and no reachable network. |
| `RegistryNetworkException` | HTTP error, timeout, or invalid JSON from the registry. |
| `RegistryIntegrityException` | Downloaded file failed SHA-256 or size check. |
| `RegistryFileNotFoundException` | `getFile(path)` where `path` isn't in the current manifest. |

All extend `RegistryException`.

## Platforms

This package does **not** support Flutter web — it returns `File` (from `dart:io`) for binary payloads, which the web platform does not expose.

## License

MIT
