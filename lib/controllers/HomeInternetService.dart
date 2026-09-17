import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:lightnetwork/controllers/ApiService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/attachment_ref.dart';
import 'package:lightnetwork/models/attachment_upload.dart';
import 'package:lightnetwork/models/home_customer.dart';
import 'package:lightnetwork/models/payment_record.dart';
import 'package:lightnetwork/models/plan_snapshot.dart';
import 'package:lightnetwork/utils/flex_date.dart';

class HomeInternetService {
  static final _storage = FirebaseStorage.instance;
  static final _auth = Get.find<AuthController>();
  static const String _base = '${ApiService.baseUrl}/api/hi';

  static Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _decode(http.Response res) async {
    final raw = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (raw is! Map) {
      throw Exception('Unexpected server response');
    }
    final map = Map<String, dynamic>.from(raw);
    if (res.statusCode >= 400) {
      throw Exception(map['error']?.toString() ?? 'Request failed (${res.statusCode})');
    }
    return map;
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$_base$path'), headers: await _headers());
    return _decode(res);
  }

  static Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$_base$path');
    final headers = await _headers();
    final encoded = body == null ? null : jsonEncode(body);
    late http.Response res;
    switch (method) {
      case 'POST':
        res = await http.post(uri, headers: headers, body: encoded);
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: encoded);
        break;
      case 'PATCH':
        res = await http.patch(uri, headers: headers, body: encoded);
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
      default:
        throw Exception('Unsupported method $method');
    }
    return _decode(res);
  }

  static Stream<T> _once<T>(Future<T> Function() load) {
    return Stream.fromFuture(load());
  }

  static HomeCustomer _customer(Map<String, dynamic> map) {
    return HomeCustomer.fromMap(map, '${map['id'] ?? ''}');
  }

  static PaymentRecord _payment(Map<String, dynamic> map) {
    return PaymentRecord.fromMap(map, '${map['id'] ?? ''}');
  }

  static Future<List<String>> fetchZones() async {
    final data = await _get('/config');
    return (data['zones'] as List?)?.map((e) => '$e').toList() ?? <String>[];
  }

  static Future<List<String>> fetchCustomerTypes() async {
    final data = await _get('/config');
    return (data['customer_types'] as List?)?.map((e) => '$e').toList() ?? <String>[];
  }

  static Future<void> setDropdownOptions({
    required List<String> zones,
    required List<String> customerTypes,
  }) async {
    await _send('PUT', '/config', {
      'zones': zones,
      'customer_types': customerTypes,
    });
  }

  static Future<void> archiveCustomer({required String id}) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can archive customer');
    }
    await _send('POST', '/customers/$id/archive');
  }

  static Future<void> restoreCustomer({required String id}) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can restore customer');
    }
    await _send('POST', '/customers/$id/restore');
  }

  static Future<List<HomeCustomer>> fetchArchivedCustomers() async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can view archived customers');
    }
    final data = await _get('/customers?archived=1');
    return (data['customers'] as List? ?? [])
        .map((e) => _customer(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> createHomeUserAccount({
    required String customerId,
    required String email,
    required String password,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can create home user accounts');
    }
    final customer = await getCustomer(customerId);
    if (customer == null) {
      throw Exception('Customer not found');
    }
    await _auth.createNewAccount(
      email,
      password,
      'homeuser',
      name: customer.name,
      location: null,
      locations: null,
      homeCustomerId: customerId,
    );
    await _send('POST', '/customers/$customerId/login-email', {'email': email});
  }

  static Future<String?> getHomeUserEmail(String customerId) async {
    try {
      final customer = await getCustomer(customerId);
      final email = customer?.loginEmail;
      if (email != null && email.isNotEmpty) return email;
      return null;
    } catch (e) {
      print('Error fetching home user email: $e');
      return null;
    }
  }

  static Stream<List<HomeCustomer>> streamCustomers() {
    return _once(() async {
      final data = await _get('/customers');
      return (data['customers'] as List? ?? [])
          .map((e) => _customer(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  static Stream<HomeCustomer?> streamCustomer(String id) {
    return _once(() => getCustomer(id));
  }

  static Stream<List<HomeCustomer>> streamArchivedCustomers() {
    if (!_auth.isBoss) {
      return Stream.error(Exception('Only boss can view archived customers'));
    }
    return _once(fetchArchivedCustomers);
  }

  static Future<List<PaymentRecord>> fetchPayments(String customerId, {int limit = 50, String? status}) async {
    final q = StringBuffer('/customers/$customerId/payments?limit=$limit');
    if (status != null && status.isNotEmpty) {
      q.write('&status=$status');
    }
    final data = await _get(q.toString());
    return (data['payments'] as List? ?? [])
        .map((e) => _payment(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Stream<List<PaymentRecord>> streamPayments(String customerId) {
    return _once(() => fetchPayments(customerId));
  }

  static Future<List<PaymentRecord>> fetchPendingApprovals() async {
    final data = await _get('/pending');
    return (data['payments'] as List? ?? [])
        .map((e) => _payment(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Stream<List<PaymentRecord>> streamPendingApprovalGroup() {
    return _once(fetchPendingApprovals);
  }

  static Future<List<PaymentRecord>> fetchPendingApprovalsFromCustomers() {
    return fetchPendingApprovals();
  }

  static Stream<List<PaymentRecord>> streamPendingPayments(String customerId) {
    return _once(() => fetchPayments(customerId, status: PaymentStatus.pendingApproval.name));
  }

  static Future<String> generateCustomerId({int maxAttempts = 50}) async {
    final data = await _get('/new-id');
    final id = '${data['id'] ?? ''}';
    if (id.isEmpty) {
      throw Exception('Failed to generate unique 5-digit customer ID after $maxAttempts attempts');
    }
    return id;
  }

  static Future<HomeCustomer> createCustomer({
    required String name,
    required String phone,
    required String location,
    required String zone,
    required int speedMbps,
    required String customerType,
    required double planAmount,
    String currency = 'TZS',
    required PaymentScheduleType schedule,
    required DateTime startDate,
    int? billingDayOfMonth,
    int? billingWeekday,
    String? address,
    String? notes,
  }) async {
    final data = await _send('POST', '/customers', {
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
    });
    return _customer(Map<String, dynamic>.from(data['customer'] as Map));
  }

  static Future<HomeCustomer?> getCustomer(String id) async {
    try {
      final data = await _get('/customers/$id');
      final raw = data['customer'];
      if (raw is! Map) return null;
      return _customer(Map<String, dynamic>.from(raw));
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('not found')) return null;
      rethrow;
    }
  }

  static Future<int> backfillPlanSnapshots() async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can backfill plan snapshots');
    }
    final data = await _get('/customers');
    int created = 0;
    for (final raw in data['customers'] as List? ?? []) {
      final c = _customer(Map<String, dynamic>.from(raw));
      final plans = await _fetchPlans(c.id);
      if (plans.isEmpty) {
        await _send('POST', '/customers/${c.id}/plans', {
          'amount': c.planAmount,
          'currency': c.currency,
          'effective_from': c.startDate.toIso8601String(),
        });
        created++;
      }
    }
    return created;
  }

  static Future<void> updateCustomer({
    required String id,
    String? name,
    String? phone,
    String? location,
    String? zone,
    int? speedMbps,
    String? customerType,
    double? planAmount,
    String? currency,
    PaymentScheduleType? schedule,
    int? billingDayOfMonth,
    int? billingWeekday,
    String? address,
    String? notes,
    bool? active,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can update customer');
    }
    final updates = <String, dynamic>{};
    void setIf(String key, dynamic v) {
      if (v != null) updates[key] = v;
    }
    setIf('name', name);
    setIf('phone', phone);
    setIf('location', location);
    setIf('zone', zone);
    setIf('speed_mbps', speedMbps);
    setIf('customer_type', customerType);
    setIf('plan_amount', planAmount);
    setIf('currency', currency);
    if (schedule != null) updates['schedule'] = schedule.name;
    setIf('billing_day_of_month', billingDayOfMonth);
    setIf('billing_weekday', billingWeekday);
    setIf('address', address);
    setIf('notes', notes);
    setIf('active', active);
    await _send('PATCH', '/customers/$id', updates);
  }

  static Future<void> deleteCustomer({required String id}) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can delete customer');
    }
    try {
      final payments = await fetchPayments(id, limit: 300);
      for (final pr in payments) {
        for (final a in pr.attachments) {
          if (a.storagePath.isEmpty) continue;
          try {
            await _storage.ref().child(a.storagePath).delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    await _send('DELETE', '/customers/$id');
  }

  static Future<Map<String, dynamic>> fetchPaymentsTotal({
    required DateTime start,
    required DateTime end,
    String? zone,
    String? customerType,
  }) async {
    final q = StringBuffer(
      '/analytics/payments?start=${Uri.encodeQueryComponent(start.toIso8601String())}'
      '&end=${Uri.encodeQueryComponent(end.toIso8601String())}',
    );
    if (zone != null && zone.isNotEmpty) {
      q.write('&zone=${Uri.encodeQueryComponent(zone)}');
    }
    if (customerType != null && customerType.isNotEmpty) {
      q.write('&customer_type=${Uri.encodeQueryComponent(customerType)}');
    }
    final data = await _get(q.toString());
    return {
      'total_amount': (data['total_amount'] is num)
          ? (data['total_amount'] as num).toDouble()
          : 0.0,
      'count': data['count'] ?? 0,
    };
  }

  static Future<AttachmentRef> _uploadAttachment({
    required String customerId,
    required String paymentId,
    required AttachmentUpload file,
  }) async {
    final path = 'home_internet_receipts/$customerId/$paymentId/${file.name}';
    final ref = _storage.ref().child(path);
    final meta = SettableMetadata(contentType: file.contentType);
    final task = await ref.putData(file.bytes, meta);
    final url = await task.ref.getDownloadURL();
    return AttachmentRef(
      url: url,
      name: file.name,
      contentType: file.contentType,
      sizeBytes: file.bytes.lengthInBytes,
      storagePath: path,
      uploaderUid: _auth.user?.uid ?? '',
      uploaderName: _auth.userName,
      uploadedAt: DateTime.now(),
    );
  }

  static Future<PaymentRecord> addPayment({
    required String customerId,
    required double amountPaid,
    List<AttachmentUpload> attachments = const [],
    String currency = 'TZS',
    String? reference,
    String? notes,
    String? paymentType,
  }) async {
    final customer = await getCustomer(customerId);
    if (customer == null) {
      throw Exception('Customer not found');
    }
    final now = DateTime.now();
    final period = _currentDuePeriod(customer, now);
    final paymentId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final uploaded = <AttachmentRef>[];
    for (final a in attachments) {
      uploaded.add(await _uploadAttachment(
        customerId: customerId,
        paymentId: paymentId,
        file: a,
      ));
    }
    final data = await _send('POST', '/customers/$customerId/payments', {
      'id': paymentId,
      'amount_paid': amountPaid,
      'currency': currency,
      'attachments': uploaded.map((a) => a.toMap()).toList(),
      'status': PaymentStatus.pendingApproval.name,
      'schedule': customer.schedule.name,
      'period_start': period.start.toIso8601String(),
      'period_end': period.end.toIso8601String(),
      'due_date': period.due.toIso8601String(),
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
      if (paymentType != null) 'payment_type': paymentType,
      'customer_zone': customer.zone,
      'customer_type': customer.customerType,
    });
    return _payment(Map<String, dynamic>.from(data['payment'] as Map));
  }

  static Future<void> approvePayment({
    required String customerId,
    required String paymentId,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can approve payments');
    }
    await _send('POST', '/customers/$customerId/payments/$paymentId/approve');
  }

  static Future<void> rejectPayment({
    required String customerId,
    required String paymentId,
    String? reason,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can reject payments');
    }
    await _send('POST', '/customers/$customerId/payments/$paymentId/reject', {
      if (reason != null) 'reason': reason,
    });
  }

  static Future<List<PlanSnapshot>> _fetchPlans(String customerId) async {
    final data = await _get('/customers/$customerId/plans');
    return (data['plans'] as List? ?? [])
        .map((e) => PlanSnapshot.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static double asMoney(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static Map<String, dynamic> normalizeStatement(Map<String, dynamic> raw) {
    final status = Map<String, dynamic>.from(raw);
    for (final key in const ['next_due_date', 'last_paid_at', 'as_of']) {
      final parsed = parseFlexDate(status[key]);
      if (parsed != null) status[key] = parsed;
    }
    for (final key in const [
      'this_month_bill',
      'this_month_paid',
      'this_month_balance',
      'arrears',
      'credit',
      'pay_now',
      'outstanding_amount',
      'total_due_amount',
      'total_paid_amount',
    ]) {
      if (status.containsKey(key)) status[key] = asMoney(status[key]);
    }
    if (status['aging'] is Map) {
      final aging = Map<String, dynamic>.from(status['aging'] as Map);
      for (final key in aging.keys.toList()) {
        aging[key] = asMoney(aging[key]);
      }
      status['aging'] = aging;
    }
    return status;
  }

  static PeriodPaymentStatus periodFromMap(Map<String, dynamic> map) {
    final stateName = '${map['state'] ?? map['status'] ?? 'unpaid'}'.toLowerCase();
    final state = stateName == 'paid'
        ? PeriodPayState.paid
        : (stateName == 'partial' ? PeriodPayState.partial : PeriodPayState.unpaid);
    final start = parseFlexDate(map['start'] ?? map['period_start']) ?? DateTime.now();
    final end = parseFlexDate(map['end'] ?? map['period_end']) ?? start;
    final due = parseFlexDate(map['due'] ?? map['due_date']) ?? start;
    final required = asMoney(map['required_amount'] ?? map['amount']);
    final paid = asMoney(map['paid_amount'] ?? map['amount_paid']);
    return PeriodPaymentStatus(
      start: start,
      end: end,
      due: due,
      requiredAmount: required,
      paidAmount: paid,
      state: state,
      invoiceNo: map['invoice_no']?.toString(),
      balance: asMoney(map['balance'] ?? (required - paid)),
    );
  }

  static Future<Map<String, dynamic>> computeCustomerStatus(String customerId) async {
    final data = await _get('/customers/$customerId/status');
    return normalizeStatement(data);
  }

  static Future<List<PeriodPaymentStatus>> fetchInvoices(String customerId) async {
    final data = await _get('/customers/$customerId/invoices');
    final rows = (data['invoices'] as List?) ?? (data['periods'] as List?) ?? const [];
    return rows
        .map((e) => periodFromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<PeriodPaymentStatus>> listPeriodStatuses(
    String customerId, {
    DateTime? upTo,
  }) async {
    try {
      return await fetchInvoices(customerId);
    } catch (_) {
      // Fall through to the historical client formula if the invoice API is unavailable.
    }
    final customer = await getCustomer(customerId);
    if (customer == null) throw Exception('Customer not found');
    final now = upTo ?? DateTime.now();

    final int periodsDue = _periodsDueUpToNow(customer, now);
    if (periodsDue <= 0) return <PeriodPaymentStatus>[];

    final List<_Period> periods = [];
    if (customer.schedule == PaymentScheduleType.weekly) {
      final int anchorWeekday = customer.billingWeekday ?? customer.startDate.weekday;
      DateTime firstDue = customer.startDate;
      final int diff = (anchorWeekday - firstDue.weekday);
      if (diff > 0) {
        firstDue = firstDue.add(Duration(days: diff));
      } else if (diff < 0) {
        firstDue = firstDue.add(Duration(days: (7 + diff)));
      }
      for (int i = 0; i < periodsDue; i++) {
        final start = firstDue.add(Duration(days: 7 * i));
        final end = start.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
        periods.add(_Period(start: start, end: end, due: start));
      }
    } else {
      final int anchorDay = (customer.billingDayOfMonth ?? customer.startDate.day).clamp(1, 28);
      DateTime firstDue = DateTime(
        customer.startDate.year,
        customer.startDate.month,
        anchorDay,
        customer.startDate.hour,
        customer.startDate.minute,
        customer.startDate.second,
        customer.startDate.millisecond,
        customer.startDate.microsecond,
      );
      if (firstDue.isBefore(customer.startDate)) {
        firstDue = DateTime(
          firstDue.year,
          firstDue.month + 1,
          anchorDay,
          firstDue.hour,
          firstDue.minute,
          firstDue.second,
          firstDue.millisecond,
          firstDue.microsecond,
        );
      }
      for (int i = 0; i < periodsDue; i++) {
        final start = DateTime(
          firstDue.year,
          firstDue.month + i,
          anchorDay,
          firstDue.hour,
          firstDue.minute,
          firstDue.second,
          firstDue.millisecond,
          firstDue.microsecond,
        );
        final end = DateTime(start.year, start.month + 1, anchorDay)
            .subtract(const Duration(seconds: 1));
        periods.add(_Period(start: start, end: end, due: start));
      }
    }

    final snapshots = await _fetchPlans(customerId);
    double requiredFor(DateTime date) {
      if (snapshots.isEmpty) return customer.planAmount;
      PlanSnapshot current = snapshots.first;
      for (final s in snapshots) {
        if (!date.isBefore(s.effectiveFrom)) {
          current = s;
        } else {
          break;
        }
      }
      return current.amount;
    }

    final approved = await fetchPayments(customerId, limit: 500, status: PaymentStatus.approved.name);
    approved.sort((a, b) {
      final atA = a.approvedAt ?? a.createdAt;
      final atB = b.approvedAt ?? b.createdAt;
      return atA.compareTo(atB);
    });
    double remaining = approved.fold(0.0, (s, p) => s + p.amountPaid);

    final results = <PeriodPaymentStatus>[];
    for (final p in periods) {
      final requiredPerPeriod = requiredFor(p.start);
      final allocated = remaining >= requiredPerPeriod
          ? requiredPerPeriod
          : (remaining > 0 ? remaining : 0.0);
      remaining = remaining - allocated;
      final status = allocated >= requiredPerPeriod
          ? PeriodPayState.paid
          : (allocated > 0 ? PeriodPayState.partial : PeriodPayState.unpaid);
      results.add(PeriodPaymentStatus(
        start: p.start,
        end: p.end,
        due: p.due,
        requiredAmount: requiredPerPeriod,
        paidAmount: allocated,
        state: status,
      ));
    }
    return results;
  }

  static _Period _currentDuePeriod(HomeCustomer c, DateTime now) {
    if (c.schedule == PaymentScheduleType.weekly) {
      return _weekPeriod(c, now);
    }
    return _monthPeriod(c, now);
  }

  static int _periodsDueUpToNow(HomeCustomer c, DateTime now) {
    if (c.schedule == PaymentScheduleType.weekly) {
      return _weeksDueUpTo(c, now);
    }
    return _monthsDueUpTo(c, now);
  }

  static _Period _weekPeriod(HomeCustomer c, DateTime ref) {
    final int anchorWeekday = c.billingWeekday ?? c.startDate.weekday;
    DateTime firstDue = c.startDate;
    final int diff = (anchorWeekday - firstDue.weekday);
    if (diff > 0) {
      firstDue = firstDue.add(Duration(days: diff));
    } else if (diff < 0) {
      firstDue = firstDue.add(Duration(days: (7 + diff)));
    } else {
      firstDue = firstDue.add(const Duration(days: 7));
    }
    if (ref.isBefore(firstDue)) {
      final end = firstDue.subtract(const Duration(seconds: 1));
      return _Period(start: c.startDate, end: end, due: firstDue);
    }
    int weeks = ((ref.difference(firstDue).inDays) ~/ 7) + 1;
    final start = firstDue.add(Duration(days: 7 * (weeks - 1)));
    final end = start.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
    return _Period(start: start, end: end, due: start);
  }

  static int _weeksDueUpTo(HomeCustomer c, DateTime ref) {
    final int anchorWeekday = c.billingWeekday ?? c.startDate.weekday;
    DateTime firstDue = c.startDate;
    final int diff = (anchorWeekday - firstDue.weekday);
    if (diff > 0) {
      firstDue = firstDue.add(Duration(days: diff));
    } else if (diff < 0) {
      firstDue = firstDue.add(Duration(days: (7 + diff)));
    } else {
      firstDue = firstDue.add(const Duration(days: 7));
    }
    if (ref.isBefore(firstDue)) return 0;
    final int daysDiff = ref.difference(firstDue).inDays;
    final int weeksDiff = daysDiff ~/ 7;
    final DateTime dueThisWeek = firstDue.add(Duration(days: 7 * weeksDiff));
    return ref.isBefore(dueThisWeek) ? weeksDiff : (weeksDiff + 1);
  }

  static _Period _monthPeriod(HomeCustomer c, DateTime ref) {
    final int anchorDay = (c.billingDayOfMonth ?? c.startDate.day).clamp(1, 28);
    DateTime firstDue = DateTime(
      c.startDate.year,
      c.startDate.month,
      anchorDay,
      c.startDate.hour,
      c.startDate.minute,
      c.startDate.second,
      c.startDate.millisecond,
      c.startDate.microsecond,
    );
    if (!firstDue.isAfter(c.startDate)) {
      firstDue = DateTime(firstDue.year, firstDue.month + 1, anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    }
    if (ref.isBefore(firstDue)) {
      final end = firstDue.subtract(const Duration(seconds: 1));
      return _Period(start: c.startDate, end: end, due: firstDue);
    }
    int months = (ref.year - firstDue.year) * 12 + (ref.month - firstDue.month) + 1;
    final start = DateTime(firstDue.year, firstDue.month + (months - 1), anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    final end = DateTime(start.year, start.month + 1, anchorDay).subtract(const Duration(seconds: 1));
    return _Period(start: start, end: end, due: start);
  }

  static int _monthsDueUpTo(HomeCustomer c, DateTime ref) {
    final int anchorDay = (c.billingDayOfMonth ?? c.startDate.day).clamp(1, 28);
    DateTime firstDue = DateTime(
      c.startDate.year,
      c.startDate.month,
      anchorDay,
      c.startDate.hour,
      c.startDate.minute,
      c.startDate.second,
      c.startDate.millisecond,
      c.startDate.microsecond,
    );
    if (!firstDue.isAfter(c.startDate)) {
      firstDue = DateTime(firstDue.year, firstDue.month + 1, anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    }
    if (ref.isBefore(firstDue)) return 0;
    final int monthsDiff = (ref.year - firstDue.year) * 12 + (ref.month - firstDue.month);
    final DateTime dueThisMonth = DateTime(firstDue.year, firstDue.month + monthsDiff, anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    return ref.isBefore(dueThisMonth) ? monthsDiff : (monthsDiff + 1);
  }
}

class _Period {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  _Period({required this.start, required this.end, required this.due});
}

enum PeriodPayState { paid, partial, unpaid }

class PeriodPaymentStatus {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  final double requiredAmount;
  final double paidAmount;
  final PeriodPayState state;
  final String? invoiceNo;
  final double balance;

  const PeriodPaymentStatus({
    required this.start,
    required this.end,
    required this.due,
    required this.requiredAmount,
    required this.paidAmount,
    required this.state,
    this.invoiceNo,
    this.balance = 0,
  });
}
