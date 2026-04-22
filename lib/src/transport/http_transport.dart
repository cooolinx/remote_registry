import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../errors.dart';

/// HTTP fetch layer for the registry. Wraps package:http and
/// translates all failures (non-2xx, socket errors, bad JSON)
/// into [RegistryNetworkException].
class HttpTransport {
  /// Creates an [HttpTransport] with an optional injected [client]
  /// (useful for tests) and request [timeout].
  HttpTransport({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  final http.Client _client;
  final Duration _timeout;

  /// Fetches [url] and decodes the response body as a JSON object.
  /// Throws [RegistryNetworkException] for non-2xx, socket errors,
  /// invalid JSON, or non-object JSON.
  Future<Map<String, dynamic>> fetchJson(Uri url) async {
    final bytes = await fetchBytes(url);
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw RegistryNetworkException(
          'Expected JSON object at $url, got ${decoded.runtimeType}',
        );
      }
      return decoded;
    } on RegistryNetworkException {
      rethrow;
    } on FormatException catch (e) {
      throw RegistryNetworkException('Invalid JSON at $url: ${e.message}', e);
    }
  }

  /// Fetches [url] and returns the response body bytes.
  /// Throws [RegistryNetworkException] on non-2xx or socket errors.
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

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
