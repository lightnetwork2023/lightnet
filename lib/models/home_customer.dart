import 'package:lightnetwork/utils/flex_date.dart';

enum PaymentScheduleType { weekly, monthly }

class HomeCustomer {
  final String id; // 5-digit customer ID (document ID)
  final String name;
  final String phone;
  final String location;
  final String zone; // dropdown
  final int speedMbps; // plan speed
  final String customerType; // dropdown (e.g., Home, Business)
  final double planAmount; // price per period
  final String currency; // e.g., TZS
  final PaymentScheduleType schedule; // weekly / monthly
  final DateTime startDate; // billing anchor
  final int? billingDayOfMonth; // optional anchor day for monthly (1..28)
  final int? billingWeekday; // optional anchor weekday for weekly (Mon..Sun as 1..7)
  final String? address;
  final String? notes;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool active;
  final Map<String, dynamic>? status;
  final String? loginEmail;

  HomeCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.location,
    required this.zone,
    required this.speedMbps,
    required this.customerType,
    required this.planAmount,
    this.currency = 'TZS',
    required this.schedule,
    required this.startDate,
    this.billingDayOfMonth,
    this.billingWeekday,
    this.address,
    this.notes,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.active = true,
    this.status,
    this.loginEmail,
  });

  factory HomeCustomer.fromMap(Map<String, dynamic> map, String id) {
    return HomeCustomer(
      id: id,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      location: map['location'] ?? '',
      zone: map['zone'] ?? '',
      speedMbps: (map['speed_mbps'] ?? 0) is int
          ? map['speed_mbps']
          : int.tryParse('${map['speed_mbps']}') ?? 0,
      customerType: map['customer_type'] ?? '',
      planAmount: (map['plan_amount'] is num)
          ? (map['plan_amount'] as num).toDouble()
          : double.tryParse('${map['plan_amount']}') ?? 0.0,
      currency: map['currency'] ?? 'TZS',
      schedule: (map['schedule'] == 'weekly')
          ? PaymentScheduleType.weekly
          : PaymentScheduleType.monthly,
      startDate: parseFlexDate(map['start_date']) ?? DateTime.now(),
      billingDayOfMonth: map['billing_day_of_month'] is int
          ? map['billing_day_of_month']
          : int.tryParse('${map['billing_day_of_month'] ?? ''}'),
      billingWeekday: map['billing_weekday'] is int
          ? map['billing_weekday']
          : int.tryParse('${map['billing_weekday'] ?? ''}'),
      address: map['address'],
      notes: map['notes'],
      createdByUid: map['created_by_uid'] ?? '',
      createdByName: map['created_by_name'] ?? '',
      createdAt: parseFlexDate(map['created_at']) ?? DateTime.now(),
      updatedAt: parseFlexDate(map['updated_at']),
      active: map['active'] == true || map['active'] == 1 || map['active'] == 'true',
      status: (map['status'] is Map) ? Map<String, dynamic>.from(map['status']) : null,
      loginEmail: map['login_email']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'location': location,
      'zone': zone,
      'speed_mbps': speedMbps,
      'customer_type': customerType,
      'plan_amount': planAmount,
      'currency': currency,
      'schedule': schedule.name,
      'start_date': startDate.toIso8601String(),
      if (billingDayOfMonth != null) 'billing_day_of_month': billingDayOfMonth,
      if (billingWeekday != null) 'billing_weekday': billingWeekday,
      if (address != null) 'address': address,
      if (notes != null) 'notes': notes,
      'created_by_uid': createdByUid,
      'created_by_name': createdByName,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      'active': active,
    };
  }

}
