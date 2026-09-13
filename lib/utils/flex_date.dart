import 'package:lightnetwork/services/app_db.dart';

DateTime? parseFlexDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  if (v is int) {
    if (v > 9999999999) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return DateTime.fromMillisecondsSinceEpoch(v * 1000);
  }
  if (v is double) {
    return parseFlexDate(v.toInt());
  }
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
  return null;
}
