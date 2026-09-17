import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightnetwork/services/app_db.dart';

void main() {
  test('users and other collections are one-shot, not polled', () {
    expect(watchIntervalForCollection('users'), isNull);
    expect(watchIntervalForCollection('payments'), isNull);
    expect(watchIntervalForCollection('locations/elly/users'), isNull);
  });

  test('mikrotik device watches refresh every 5 minutes', () {
    expect(
      watchIntervalForCollection('mikrotik_devices'),
      const Duration(minutes: 5),
    );
    expect(
      watchIntervalForCollection('mikrotik_devices/abc'),
      const Duration(minutes: 5),
    );
  });

  test('two listeners can share a snapshot-style stream', () async {
    var loads = 0;
    final stream = watchCollectionStream(() async {
      loads += 1;
      return loads;
    });

    final first = stream.first;
    final second = stream.first;
    expect(await first, 1);
    expect(await second, 1);
  });

  test('one-shot watch does not poll again', () async {
    var loads = 0;
    final stream = watchCollectionStream(() async {
      loads += 1;
      return loads;
    });

    final sub = stream.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(loads, 1);
    await sub.cancel();
  });

  test('interval watch polls after the interval', () async {
    var loads = 0;
    final stream = watchCollectionStream(
      () async {
        loads += 1;
        return loads;
      },
      interval: const Duration(milliseconds: 50),
    );

    final sub = stream.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(loads, greaterThanOrEqualTo(2));
    await sub.cancel();
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
