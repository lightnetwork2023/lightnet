import 'package:cloud_firestore/cloud_firestore.dart';

class PlanSnapshot {
  final double amount;
  final String currency;
  final DateTime effectiveFrom;

  const PlanSnapshot({
    required this.amount,
    required this.currency,
    required this.effectiveFrom,
  });

  factory PlanSnapshot.fromMap(Map<String, dynamic> map) {
    final amt = (map['amount'] is num)
        ? (map['amount'] as num).toDouble()
        : double.tryParse('${map['amount']}') ?? 0.0;
    final eff = _fromTs(map['effective_from']) ?? DateTime(1970);
    return PlanSnapshot(
      amount: amt,
      currency: map['currency'] ?? 'TZS',
      effectiveFrom: eff,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'currency': currency,
      'effective_from': Timestamp.fromDate(effectiveFrom),
    };
  }

  static DateTime? _fromTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
