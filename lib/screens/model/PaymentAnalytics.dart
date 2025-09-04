class PaymentAnalytics {
  final double today;
  final double last24Hours;
  final double lastMonth;
  final double thisMonth;
  final double dailyAverageThisMonth;
  final double thisYear;

  PaymentAnalytics({
    required this.today,
    required this.last24Hours,
    required this.lastMonth,
    required this.thisMonth,
    required this.dailyAverageThisMonth,
    required this.thisYear,
  });

  factory PaymentAnalytics.fromSummary(Map<String, dynamic> summary) {
    double parseValue(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }
    return PaymentAnalytics(
      today: parseValue(summary['today']),
      last24Hours: parseValue(summary['last_24_hours']),
      lastMonth: parseValue(summary['last_month']),
      thisMonth: parseValue(summary['this_month']),
      dailyAverageThisMonth: parseValue(summary['daily_average_this_month']),
      thisYear: parseValue(summary['this_year']),
    );
  }
}