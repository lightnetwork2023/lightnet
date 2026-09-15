import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Stream<T> pollStream<T>(Future<T> Function() load) {
  return Stream<T>.multi((listener) async {
    try {
      listener.add(await load());
      await for (final _ in Stream<void>.periodic(const Duration(seconds: 10))) {
        if (listener.isCanceled) return;
        listener.add(await load());
      }
    } catch (e, st) {
      if (!listener.isCanceled) listener.addError(e, st);
    }
  });
}

void main() {
  test('two listeners can share a snapshot-style stream', () async {
    var loads = 0;
    final stream = pollStream(() async {
      loads += 1;
      return loads;
    });

    final first = stream.first;
    final second = stream.first;
    expect(await first, 1);
    expect(await second, 2);
  });

  test('a single-subscription async* stream fails the second listener', () async {
    Stream<int> once() async* {
      yield 1;
    }

    final stream = once();
    await stream.first;
    expect(() => stream.listen((_) {}), throwsStateError);
  });
}
