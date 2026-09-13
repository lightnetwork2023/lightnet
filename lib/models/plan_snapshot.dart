import 'package:lightnetwork/utils/flex_date.dart';

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
    final eff = parseFlexDate(map['effective_from']) ?? DateTime(1970);
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
      'effective_from': effectiveFrom.toIso8601String(),
    };
  }

}
