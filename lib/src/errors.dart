/// Base class for all [remote_registry] exceptions.
abstract class RegistryException implements Exception {
  /// Creates a [RegistryException] with the given [message].
  const RegistryException(this.message);

  /// Human-readable description of the error.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a network fetch fails (DNS, timeout, non-2xx).
class RegistryNetworkException extends RegistryException {
  /// Creates a [RegistryNetworkException] with the given [message] and
  /// optional [cause].
  const RegistryNetworkException(super.message, [this.cause]);

  /// The underlying exception or error that triggered this failure, if any.
  final Object? cause;

  @override
  String toString() {
    final base = super.toString();
    return cause == null ? base : '$base (cause: $cause)';
  }
}

/// Thrown when downloaded bytes fail SHA-256 verification or size check.
class RegistryIntegrityException extends RegistryException {
  /// Creates an integrity failure for [path]. At least one of the
  /// sha/size pairs should be populated so the message is informative.
  RegistryIntegrityException({
    required this.path,
    this.expectedSha256,
    this.actualSha256,
    this.expectedSize,
    this.actualSize,
  }) : super(_buildMessage(
          path,
          expectedSha256,
          actualSha256,
          expectedSize,
          actualSize,
        ));

  /// Relative path of the file whose bytes failed verification.
  final String path;

  /// The hash the manifest said the bytes should have.
  final String? expectedSha256;

  /// The hash computed from the actual bytes, when available.
  final String? actualSha256;

  /// The size the manifest said the bytes should have, when checked.
  final int? expectedSize;

  /// The size of the actual bytes, when a size check failed.
  final int? actualSize;

  static String _buildMessage(
    String path,
    String? expectedSha,
    String? actualSha,
    int? expectedSize,
    int? actualSize,
  ) {
    final parts = <String>[];
    if (expectedSize != null && actualSize != null) {
      parts.add('expected size $expectedSize, got $actualSize');
    }
    if (expectedSha != null && actualSha != null) {
      parts.add('expected sha256 $expectedSha, got $actualSha');
    }
    return 'Integrity check failed for $path (${parts.join("; ")})';
  }
}

/// Thrown when a requested file is not in the current manifest.
class RegistryFileNotFoundException extends RegistryException {
  /// Creates a [RegistryFileNotFoundException] for [path].
  const RegistryFileNotFoundException(this.path) : super('File not found: $path');

  /// The registry-relative path that was not found.
  final String path;
}

/// Thrown when no usable version can be resolved
/// (no cache, no bundle, no network).
class RegistryUnavailableException extends RegistryException {
  /// Creates a [RegistryUnavailableException] with the given [message].
  const RegistryUnavailableException(super.message);
}
