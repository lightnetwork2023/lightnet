import 'package:lightnetwork/utils/flex_date.dart';
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

  factory PaymentRecord.fromMap(Map<String, dynamic> map, String id, {String? path}) {
    var customerId = (map['customer_id'] ?? '').toString();
    if (customerId.isEmpty && path != null) {
      final segs = path.split('/');
      final i = segs.indexOf('home_customers');
      if (i >= 0 && i + 1 < segs.length) {
        customerId = segs[i + 1];
      }
    }
    return PaymentRecord(
      id: id,
      customerId: customerId,
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
      createdAt: parseFlexDate(map['created_at']) ?? DateTime.now(),
      approvedByUid: map['approved_by_uid']?.toString(),
      approvedByName: map['approved_by_name']?.toString(),
      approvedAt: parseFlexDate(map['approved_at']),
      schedule: (map['schedule'] == 'weekly')
          ? PaymentScheduleType.weekly
          : PaymentScheduleType.monthly,
      periodStart: parseFlexDate(map['period_start']) ?? DateTime.now(),
      periodEnd: parseFlexDate(map['period_end']) ?? DateTime.now(),
      dueDate: parseFlexDate(map['due_date']) ?? DateTime.now(),
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
      'created_at': createdAt.toIso8601String(),
      if (approvedByUid != null) 'approved_by_uid': approvedByUid,
      if (approvedByName != null) 'approved_by_name': approvedByName,
      if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
      'schedule': schedule.name,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
      if (paymentType != null) 'payment_type': paymentType,
      if (customerZone != null) 'customer_zone': customerZone,
      if (customerType != null) 'customer_type': customerType,
    };
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
