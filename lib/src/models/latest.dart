import 'package:meta/meta.dart';

/// Parsing failures throw [FormatException]; callers at the SDK boundary
/// (HTTP transport, disk storage) are expected to wrap these into
/// [RegistryException] subtypes.

/// Points to the current "live" registry version.
///
/// Loaded from `<baseUrl>/latest.json`. The [version] string identifies
/// which versioned manifest directory is currently active.
@immutable
class LatestPointer {
  /// Creates a [LatestPointer] with the given [version].
  const LatestPointer({required this.version});

  /// The semantic version string identifying the active registry snapshot.
  final String version;

  /// Parses a [LatestPointer] from a JSON map.
  ///
  /// Throws [FormatException] if `version` is absent, not a string, or empty.
  factory LatestPointer.fromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v is! String || v.isEmpty) {
      throw const FormatException(
          'latest.json: "version" must be a non-empty string');
    }
    return LatestPointer(version: v);
  }

  /// Serialises this pointer back to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'version': version};
}
