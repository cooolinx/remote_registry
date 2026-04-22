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

/// Thrown when downloaded bytes fail SHA-256 verification.
class RegistryIntegrityException extends RegistryException {
  /// Creates a [RegistryIntegrityException] for [path] when the downloaded
  /// content has [actualSha256] instead of the [expectedSha256] listed in the
  /// manifest.
  RegistryIntegrityException({
    required this.path,
    required this.expectedSha256,
    required this.actualSha256,
  }) : super(
          'Integrity check failed for $path '
          '(expected $expectedSha256, got $actualSha256)',
        );

  /// The registry-relative path of the file that failed verification.
  final String path;

  /// The SHA-256 digest declared in the manifest.
  final String expectedSha256;

  /// The SHA-256 digest computed from the downloaded bytes.
  final String actualSha256;
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
