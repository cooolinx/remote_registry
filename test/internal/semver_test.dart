import 'package:remote_registry/src/internal/semver.dart';
import 'package:test/test.dart';

void main() {
  test('compareSemver: equal', () {
    expect(compareSemver('1.2.3', '1.2.3'), 0);
  });
  test('compareSemver: major/minor/patch ordering', () {
    expect(compareSemver('1.0.0', '2.0.0'), lessThan(0));
    expect(compareSemver('2.0.0', '1.0.0'), greaterThan(0));
    expect(compareSemver('1.1.0', '1.2.0'), lessThan(0));
    expect(compareSemver('1.2.0', '1.2.1'), lessThan(0));
  });
  test('compareSemver: numeric, not lexical', () {
    expect(compareSemver('1.10.0', '1.2.0'), greaterThan(0));
  });
  test('compareSemver: rejects malformed', () {
    expect(() => compareSemver('1.2', '1.2.3'), throwsFormatException);
    expect(() => compareSemver('abc', '1.2.3'), throwsFormatException);
  });
}
