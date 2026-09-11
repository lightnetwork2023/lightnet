/// Limits Firestore reads that previously downloaded entire collections.
///
/// Sep 2026 bill: 7.4M reads/day. Cause: location analytics queried every
/// `payments` doc (~200k) for "this year".
class FirestoreCostGuards {
  FirestoreCostGuards._();

  /// Max span for a `payments` collection scan.
  static const int maxPaymentQueryDays = 31;

  /// Hard cap so a bad query cannot download the full payments history.
  static const int maxPaymentDocs = 3000;

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
}

class DateTimeRangeBounds {
  const DateTimeRangeBounds({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
}
