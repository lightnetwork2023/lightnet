/// Limits Firestore reads that previously downloaded entire collections.
///
/// Sep 2026 bill: 7.4M reads/day. Causes:
/// - Location analytics queried every `payments` doc (~200k) for "this year"
/// - Monitor list called `radacct_history` (500 docs × every router) on each rebuild
class FirestoreCostGuards {
  FirestoreCostGuards._();

  /// Max span for a `payments` collection scan.
  static const int maxPaymentQueryDays = 31;

  /// Hard cap so a bad query cannot download the full payments history.
  static const int maxPaymentDocs = 3000;

  /// radacct_history docs per NAS. Was 500 and ran on every list rebuild.
  static const int maxRadacctDocs = 50;

  static const Duration radacctCacheTtl = Duration(minutes: 10);

  /// Returns a [start, end) range, or null if the UI should use location
  /// metadata instead of scanning `payments` (year / all-time).
  static DateTimeRangeBounds? paymentQueryBounds({
    required String period,
    required DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    DateTime? start;
    DateTime? end;

    switch (period) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        break;
      case 'last24Hours':
        start = now.subtract(const Duration(hours: 24));
        end = now;
        break;
      case 'thisMonth':
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        break;
      case 'lastMonth':
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 1);
        break;
      case 'thisYear':
      case 'allTime':
        return null;
      case 'custom':
        if (customStart == null || customEnd == null) {
          throw ArgumentError('Custom period requires start and end dates');
        }
        start = DateTime(customStart.year, customStart.month, customStart.day);
        end = DateTime(customEnd.year, customEnd.month, customEnd.day)
            .add(const Duration(days: 1));
        break;
      default:
        throw ArgumentError('Unknown period: $period');
    }

    final days = end.difference(start).inDays;
    if (days > maxPaymentQueryDays) {
      throw ArgumentError(
        'Payment query span $days days exceeds max $maxPaymentQueryDays',
      );
    }
    return DateTimeRangeBounds(start: start, end: end);
  }

  /// Map Flask `live_speed` / `wan_traffic_total` (or legacy `wan_stats`)
  /// into the fields the monitor cards already render. Null = no inline data.
  static Map<String, dynamic>? inlineWanStats(Map<String, dynamic> data) {
    final nested = data['wan_stats'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }

    final live = data['live_speed'];
    final total = data['wan_traffic_total'];
    if (live is! Map && total is! Map) return null;

    final liveMap = live is Map ? Map<String, dynamic>.from(live) : const {};
    final totalMap = total is Map ? Map<String, dynamic>.from(total) : const {};
    return {
      'rx_bps': liveMap['rx_bps'] ?? 0,
      'tx_bps': liveMap['tx_bps'] ?? 0,
      'rx_bytes': totalMap['rx_bytes'] ?? 0,
      'tx_bytes': totalMap['tx_bytes'] ?? 0,
    };
  }
}

class DateTimeRangeBounds {
  const DateTimeRangeBounds({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
}
