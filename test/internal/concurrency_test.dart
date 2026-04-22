import 'dart:async';
import 'package:remote_registry/src/internal/concurrency.dart';
import 'package:test/test.dart';

void main() {
  test('runBounded runs all tasks and preserves order', () async {
    final results = await runBounded<int>(
      maxConcurrent: 2,
      tasks: List.generate(
        5,
        (i) => () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return i * 2;
        },
      ),
    );
    expect(results, [0, 2, 4, 6, 8]);
  });

  test('runBounded enforces max concurrency', () async {
    var active = 0;
    var peak = 0;
    final tasks = List.generate(
      6,
      (_) => () async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return 0;
      },
    );
    await runBounded<int>(maxConcurrent: 2, tasks: tasks);
    expect(peak, lessThanOrEqualTo(2));
  });

  test('runBounded propagates first error and stops pending starts', () async {
    var started = 0;
    final tasks = List.generate(
      10,
      (i) => () async {
        started++;
        if (i == 0) throw StateError('boom');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return i;
      },
    );
    await expectLater(
      runBounded<int>(maxConcurrent: 2, tasks: tasks),
      throwsA(isA<StateError>()),
    );
    // Not all should start.
    expect(started, lessThan(10));
  });
}
