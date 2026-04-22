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

  test('socket error wrapped as RegistryNetworkException', () async {
    final client = MockClient((_) async => throw Exception('socket down'));
    final t = HttpTransport(client: client);
    expect(
      () => t.fetchBytes(Uri.parse('https://x/y')),
      throwsA(isA<RegistryNetworkException>()),
    );
  });

  test('malformed JSON wrapped as RegistryNetworkException', () async {
    final client = MockClient((_) async => http.Response('not json!', 200));
    final t = HttpTransport(client: client);
    expect(
      () => t.fetchJson(Uri.parse('https://x/y.json')),
      throwsA(isA<RegistryNetworkException>()),
    );
  });

  test('JSON that is not an object wrapped as RegistryNetworkException', () async {
    final client = MockClient((_) async => http.Response('[1,2]', 200));
    final t = HttpTransport(client: client);
    expect(
      () => t.fetchJson(Uri.parse('https://x/y.json')),
      throwsA(isA<RegistryNetworkException>()),
    );
  });
}
