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

## Install

```yaml
dependencies:
  remote_registry: ^0.1.0
```

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

## Usage

```dart
import 'package:remote_registry/remote_registry.dart';

final registry = RemoteRegistry(
  baseUrl: 'https://yourcdn.example/registry',
  bundledAssetPath: 'assets/registry/',  // optional fallback
);

await registry.init();

final models = await registry.getJson('models.json');
final File logoFile = await registry.getFile('assets/logo.png');
```

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

## Bundling an asset snapshot

For first-run-offline support, ship a snapshot in your Flutter assets. Use the CLI:

```bash
dart run remote_registry:sync_bundle \
    --base https://yourcdn.example/registry \
    --out  example/assets/registry
```

Then declare the directory in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/registry/
```

Run this in CI before every release to keep the bundled snapshot fresh.

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
