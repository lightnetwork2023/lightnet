import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Stream<T> pollStream<T>(Future<T> Function() load) {
  late StreamController<T> controller;
  Timer? timer;
  var inFlight = false;

  Future<void> emit() async {
    if (inFlight || controller.isClosed) return;
    inFlight = true;
    try {
      final value = await load();
      if (!controller.isClosed) controller.add(value);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      inFlight = false;
    }
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      emit();
      timer ??= Timer.periodic(const Duration(seconds: 10), (_) => emit());
    },
    onCancel: () {
      if (!controller.hasListener) {
        timer?.cancel();
        timer = null;
      }
    },
  );
  return controller.stream;
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
    expect(await second, 1);
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
