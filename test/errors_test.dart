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
    final e = const RegistryUnavailableException('no network and no bundle');
    expect(e, isA<RegistryException>());
  });
}
