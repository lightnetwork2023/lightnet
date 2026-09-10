import 'package:flutter_test/flutter_test.dart';
import 'package:lightnetwork/services/firestore_cost_guards.dart';

void main() {
  final now = DateTime(2026, 9, 11, 12, 0, 0);

  test('today is a single calendar day', () {
    final r = FirestoreCostGuards.paymentQueryBounds(period: 'today', now: now)!;
    expect(r.start, DateTime(2026, 9, 11));
    expect(r.end, DateTime(2026, 9, 12));
  });

  test('thisMonth stays under the 31-day cap in September', () {
    final r = FirestoreCostGuards.paymentQueryBounds(
      period: 'thisMonth',
      now: now,
    )!;
    expect(r.start, DateTime(2026, 9, 1));
    expect(r.end, DateTime(2026, 10, 1));
    expect(r.end.difference(r.start).inDays, 30);
  });

  test('thisYear uses metadata instead of scanning payments', () {
    expect(
      FirestoreCostGuards.paymentQueryBounds(period: 'thisYear', now: now),
      isNull,
    );
  });

  test('custom without dates is rejected', () {
    expect(
      () => FirestoreCostGuards.paymentQueryBounds(period: 'custom', now: now),
      throwsArgumentError,
    );
  });

  test('custom range longer than 31 days is rejected', () {
    expect(
      () => FirestoreCostGuards.paymentQueryBounds(
        period: 'custom',
        now: now,
        customStart: DateTime(2026, 1, 1),
        customEnd: DateTime(2026, 9, 11),
      ),
      throwsArgumentError,
    );
  });

  test('custom range of 7 days is allowed', () {
    final r = FirestoreCostGuards.paymentQueryBounds(
      period: 'custom',
      now: now,
      customStart: DateTime(2026, 9, 1),
      customEnd: DateTime(2026, 9, 7),
    )!;
    expect(r.start, DateTime(2026, 9, 1));
    expect(r.end, DateTime(2026, 9, 8));
  });

  test('inlineWanStats prefers wan_stats then Flask live_speed fields', () {
    expect(FirestoreCostGuards.inlineWanStats({}), isNull);

    final fromFlask = FirestoreCostGuards.inlineWanStats({
      'live_speed': {'rx_bps': 1000, 'tx_bps': 2000},
      'wan_traffic_total': {'rx_bytes': 10, 'tx_bytes': 20},
    });
    expect(fromFlask!['rx_bps'], 1000);
    expect(fromFlask['tx_bytes'], 20);

    final legacy = FirestoreCostGuards.inlineWanStats({
      'wan_stats': {'rx_bps': 5},
    });
    expect(legacy!['rx_bps'], 5);
  });
}
