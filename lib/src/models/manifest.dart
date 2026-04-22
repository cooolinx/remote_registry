import 'package:meta/meta.dart';

/// Parsing failures throw [FormatException]; callers at the SDK boundary
/// (HTTP transport, disk storage) are expected to wrap these into
/// [RegistryException] subtypes.

// Module-private pattern: exactly 64 lowercase hex characters.
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Describes a single file entry within a [Manifest].
@immutable
class ManifestFile {
  /// Creates a [ManifestFile].
  ///
  /// [path] must be a relative, traversal-safe POSIX path with no backslashes
  /// or empty segments.
  /// [sha256] must be exactly 64 lowercase hex characters.
  /// [size] is optional and represents the file size in bytes.
  const ManifestFile({
    required this.path,
    required this.sha256,
    this.size,
  });

  /// Relative POSIX path of the file within the registry bundle.
  final String path;

  /// SHA-256 hex digest of the file contents.
  final String sha256;

  /// Optional file size in bytes; `null` when not provided by the server.
  final int? size;

  /// Parses a [ManifestFile] from a JSON map.
  ///
  /// Throws [FormatException] if:
  /// - `path` is missing, empty, absolute, contains `..` / `.` segments,
  ///   backslashes, or empty segments (e.g. `a//b`).
  /// - `sha256` is not exactly 64 lowercase hex characters.
  /// - `size` is present but not an integer.
  factory ManifestFile.fromJson(Map<String, dynamic> json) {
    final p = json['path'];
    if (p is! String || p.isEmpty) {
      throw const FormatException(
          'manifest file: "path" must be non-empty string');
    }
    if (p.startsWith('/')) {
      throw FormatException('manifest file path must be relative: $p');
    }
    if (p.contains('\\')) {
      throw FormatException(
          'manifest file path must not contain backslashes: $p');
    }
    final segments = p.split('/');
    if (segments.contains('..') ||
        segments.contains('.') ||
        segments.any((s) => s.isEmpty)) {
      throw FormatException(
          'manifest file path must not contain "..", ".", or empty segments: $p');
    }
    final s = json['sha256'];
    if (s is! String || !_sha256Pattern.hasMatch(s)) {
      throw FormatException(
          'manifest file "$p": sha256 must be 64 lowercase hex chars (got "$s")');
    }
    final sz = json['size'];
    if (sz != null && sz is! int) {
      throw FormatException(
          'manifest file "$p": size must be int if present');
    }
    return ManifestFile(path: p, sha256: s, size: sz as int?);
  }

  /// Serialises this file entry to a JSON-compatible map.
  ///
  /// The `size` key is omitted when [size] is `null`.
  Map<String, dynamic> toJson() => {
        'path': path,
        'sha256': sha256,
        if (size != null) 'size': size,
      };
}

/// Describes all files that make up a versioned registry snapshot.
///
/// Loaded from `<baseUrl>/<version>/manifest.json`.
@immutable
class Manifest {
  /// Creates a [Manifest] with the given [version] and [files] list.
  const Manifest({required this.version, required this.files});

  /// The semantic version string for this manifest snapshot.
  final String version;

  /// Ordered, unmodifiable list of files included in this registry snapshot.
  final List<ManifestFile> files;

  /// Parses a [Manifest] from a JSON map.
  ///
  /// Throws [FormatException] if `version` or `files` are invalid,
  /// or if any file entry fails [ManifestFile.fromJson] validation.
  factory Manifest.fromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v is! String || v.isEmpty) {
      throw const FormatException(
          'manifest: "version" must be non-empty string');
    }
    final rawFiles = json['files'];
    if (rawFiles is! List) {
      throw const FormatException('manifest: "files" must be a list');
    }
    final files = List<ManifestFile>.unmodifiable(
      rawFiles.map((e) => ManifestFile.fromJson(e as Map<String, dynamic>)),
    );
    return Manifest(version: v, files: files);
  }

  /// Returns the [ManifestFile] whose [ManifestFile.path] matches [path],
  /// or `null` if no such file exists in this manifest.
  ManifestFile? findByPath(String path) {
    for (final f in files) {
      if (f.path == path) return f;
    }
    return null;
  }

  /// Serialises this manifest to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'version': version,
        'files': files.map((f) => f.toJson()).toList(),
      };
}
