import 'dart:async';

/// A zero-argument async closure returning `T`.
typedef AsyncTask<T> = Future<T> Function();

/// Runs [tasks] with at most [maxConcurrent] in flight at once.
///
/// Returns results in the same order as [tasks]. On first failure,
/// aborts launching additional tasks and rethrows the error with its
/// original stack trace.
///
/// Throws [ArgumentError] if [maxConcurrent] is less than 1.
Future<List<T>> runBounded<T>({
  required int maxConcurrent,
  required List<AsyncTask<T>> tasks,
}) async {
  if (maxConcurrent < 1) {
    throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'must be >= 1');
  }
  final results = List<T?>.filled(tasks.length, null);
  var next = 0;
  Object? error;
  StackTrace? errorStack;

  Future<void> worker() async {
    while (error == null) {
      final i = next++;
      if (i >= tasks.length) return;
      try {
        results[i] = await tasks[i]();
      } catch (e, st) {
        error ??= e;
        errorStack ??= st;
        return;
      }
    }
  }

  final workerCount = maxConcurrent.clamp(1, tasks.isEmpty ? 1 : tasks.length);
  final workers = List.generate(workerCount, (_) => worker());
  await Future.wait(workers);
  if (error != null) {
    Error.throwWithStackTrace(error!, errorStack ?? StackTrace.current);
  }
  return results.cast<T>();
}
