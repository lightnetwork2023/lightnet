import 'package:cloud_firestore/cloud_firestore.dart';
import 'attachment_ref.dart';
import 'home_customer.dart';

enum PaymentStatus { pendingApproval, approved, rejected }

class PaymentRecord {
  final String id; // document ID
  final String customerId; // 5-digit id referencing HomeCustomer
  final double amountPaid;
  final String currency; // e.g., TZS
  final List<AttachmentRef> attachments; // receipt images/PDF/SMS

  final PaymentStatus status;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final String? approvedByUid;
  final String? approvedByName;
  final DateTime? approvedAt;

  // For billing/period tracking
  final PaymentScheduleType schedule;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime dueDate;

  // Optional metadata
  final String? reference; // bank ref, SMS code, etc.
  final String? notes;
  final String? paymentType; // e.g., Cash, Bank, MobileMoney
  final String? customerZone; // denormalized for analytics
  final String? customerType; // denormalized for analytics

  PaymentRecord({
    required this.id,
    required this.customerId,
    required this.amountPaid,
    this.currency = 'TZS',
    required this.attachments,
    required this.status,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    this.approvedByUid,
    this.approvedByName,
    this.approvedAt,
    required this.schedule,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    this.reference,
    this.notes,
    this.paymentType,
    this.customerZone,
    this.customerType,
  });

  factory PaymentRecord.fromMap(Map<String, dynamic> map, String id) {
    return PaymentRecord(
      id: id,
      customerId: map['customer_id'] ?? '',
      amountPaid: (map['amount_paid'] is num)
          ? (map['amount_paid'] as num).toDouble()
          : double.tryParse('${map['amount_paid']}') ?? 0.0,
      currency: map['currency'] ?? 'TZS',
      attachments: (map['attachments'] as List? ?? [])
          .map((e) => AttachmentRef.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      status: _statusFromString(map['status']),
      createdByUid: map['created_by_uid'] ?? '',
      createdByName: map['created_by_name'] ?? '',
      createdAt: _fromTs(map['created_at']) ?? DateTime.now(),
      approvedByUid: map['approved_by_uid'],
      approvedByName: map['approved_by_name'],
      approvedAt: _fromTs(map['approved_at']),
      schedule: (map['schedule'] == 'weekly')
          ? PaymentScheduleType.weekly
          : PaymentScheduleType.monthly,
      periodStart: _fromTs(map['period_start']) ?? DateTime.now(),
      periodEnd: _fromTs(map['period_end']) ?? DateTime.now(),
      dueDate: _fromTs(map['due_date']) ?? DateTime.now(),
      reference: map['reference'],
      notes: map['notes'],
      paymentType: map['payment_type'],
      customerZone: map['customer_zone'],
      customerType: map['customer_type'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customer_id': customerId,
      'amount_paid': amountPaid,
      'currency': currency,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      'status': status.name,
      'created_by_uid': createdByUid,
      'created_by_name': createdByName,
      'created_at': Timestamp.fromDate(createdAt),
      if (approvedByUid != null) 'approved_by_uid': approvedByUid,
      if (approvedByName != null) 'approved_by_name': approvedByName,
      if (approvedAt != null) 'approved_at': Timestamp.fromDate(approvedAt!),
      'schedule': schedule.name,
      'period_start': Timestamp.fromDate(periodStart),
      'period_end': Timestamp.fromDate(periodEnd),
      'due_date': Timestamp.fromDate(dueDate),
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
      if (paymentType != null) 'payment_type': paymentType,
      if (customerZone != null) 'customer_zone': customerZone,
      if (customerType != null) 'customer_type': customerType,
    };
  }

  static DateTime? _fromTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static PaymentStatus _statusFromString(String? s) {
    switch (s) {
      case 'approved':
        return PaymentStatus.approved;
      case 'rejected':
        return PaymentStatus.rejected;
      case 'pendingApproval':
      default:
        return PaymentStatus.pendingApproval;
    }
  }
}
