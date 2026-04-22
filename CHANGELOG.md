# Changelog

## 0.1.1

- Accept version strings with or without a leading `v` / `V` prefix in
  `latest.json`, `manifest.json`, and the `--version` CLI flag. The
  prefix is stripped before the value is used in URL paths or on-disk
  layout, so registries emitting either form interoperate cleanly.

## 0.1.0

- Initial release.
- `RemoteRegistry` with default (app-support dir) and `.withStorage` constructors.
- Stale-then-refresh `init()` with local-cache → bundle → network fallback chain.
- SHA-256 integrity verification on all downloads.
- Bounded parallel downloads (default 4 concurrent).
- Version GC (keep last N).
- `onUpdate` stream for background-refresh notifications.
- `sync_bundle` CLI for CI asset-seeding.
