import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/home_customer.dart';
import 'package:lightnetwork/models/payment_record.dart';
import 'package:lightnetwork/models/attachment_ref.dart';
import 'package:lightnetwork/models/attachment_upload.dart';
import 'package:lightnetwork/models/plan_snapshot.dart';

class HomeInternetService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static final _auth = Get.find<AuthController>();

  // Collections & Docs
  static const String customersCol = 'home_customers';
  static const String configCol = 'home_internet_config';
  static const String enumsDoc = 'enums';
  static const String archivedCustomersCol = 'archived_home_customers';

  // ------------------------------
  // Dropdown sources (zones, customer types)
  // ------------------------------
  static Future<List<String>> fetchZones() async {
    final doc = await _db.collection(configCol).doc(enumsDoc).get();
    final data = doc.data() ?? {};
    final zones = (data['zones'] as List?)?.map((e) => '$e').toList();
    return zones == null || zones.isEmpty
        ? <String>[]
        : zones;
  }

  /// Boss-only: Archive a customer and related subcollections under archived_home_customers.
  /// Copies customer doc, payments, and plan_snapshots to archive, then removes originals.
  /// Attachments in Firebase Storage are NOT deleted; pointers remain valid.
  static Future<void> archiveCustomer({required String id}) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can archive customer');
    }
    final custRef = _db.collection(customersCol).doc(id);
    final snap = await custRef.get();
    if (!snap.exists) {
      throw Exception('Customer not found');
    }

    // Do not allow archiving if there are pending approvals
    final pending = await custRef
        .collection('payments')
        .where('status', isEqualTo: PaymentStatus.pendingApproval.name)
        .limit(1)
        .get();
    if (pending.docs.isNotEmpty) {
      throw Exception('Cannot archive: customer has pending approval payments');
    }

    // 1) Copy customer doc to archive
    final data = Map<String, dynamic>.from(snap.data()!);
    data['archived_at'] = FieldValue.serverTimestamp();
    data['archived_by_uid'] = _auth.user?.uid;
    data['archived_by_name'] = _auth.userName;
    final archRef = _db.collection(archivedCustomersCol).doc(id);
    await archRef.set(data);

    // 2) Copy payments to archive
    while (true) {
      final paySnap = await custRef.collection('payments').limit(300).get();
      if (paySnap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in paySnap.docs) {
        final m = d.data();
        m['archived_at'] = FieldValue.serverTimestamp();
        batch.set(archRef.collection('payments').doc(d.id), m, SetOptions(merge: false));
      }
      await batch.commit();

      // After copy, delete originals for this page
      final delBatch = _db.batch();
      for (final d in paySnap.docs) {
        delBatch.delete(d.reference);
      }
      await delBatch.commit();
    }

    // 3) Copy plan snapshots to archive
    while (true) {
      final snaps = await custRef.collection('plan_snapshots').limit(300).get();
      if (snaps.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snaps.docs) {
        final m = d.data();
        m['archived_at'] = FieldValue.serverTimestamp();
        batch.set(archRef.collection('plan_snapshots').doc(d.id), m, SetOptions(merge: false));
      }
      await batch.commit();

      final delBatch = _db.batch();
      for (final d in snaps.docs) {
        delBatch.delete(d.reference);
      }
      await delBatch.commit();
    }

    // 4) Delete customer doc from primary
    await custRef.delete();
  }

  /// Boss-only: Restore an archived customer back to active collection.
  /// Copies customer doc, payments, and plan_snapshots from archive back to home_customers, then removes from archive.
  static Future<void> restoreCustomer({required String id}) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can restore customer');
    }
    final archRef = _db.collection(archivedCustomersCol).doc(id);
    final snap = await archRef.get();
    if (!snap.exists) {
      throw Exception('Archived customer not found');
    }

    // Check if customer already exists in active collection
    final existingActive = await _db.collection(customersCol).doc(id).get();
    if (existingActive.exists) {
      throw Exception('Customer already exists in active collection');
    }

    // 1) Copy customer doc back to active
    final data = Map<String, dynamic>.from(snap.data()!);
    data.remove('archived_at');
    data.remove('archived_by_uid');
    data.remove('archived_by_name');
    data['restored_at'] = FieldValue.serverTimestamp();
    data['restored_by_uid'] = _auth.user?.uid;
    data['restored_by_name'] = _auth.userName;
    final custRef = _db.collection(customersCol).doc(id);
    await custRef.set(data);

    // 2) Copy payments back to active
    while (true) {
      final paySnap = await archRef.collection('payments').limit(300).get();
      if (paySnap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in paySnap.docs) {
        final m = Map<String, dynamic>.from(d.data());
        m.remove('archived_at');
        batch.set(custRef.collection('payments').doc(d.id), m, SetOptions(merge: false));
      }
      await batch.commit();

      // After copy, delete from archive
      final delBatch = _db.batch();
      for (final d in paySnap.docs) {
        delBatch.delete(d.reference);
      }
      await delBatch.commit();
    }

    // 3) Copy plan snapshots back to active
    while (true) {
      final snaps = await archRef.collection('plan_snapshots').limit(300).get();
      if (snaps.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snaps.docs) {
        final m = Map<String, dynamic>.from(d.data());
        m.remove('archived_at');
        batch.set(custRef.collection('plan_snapshots').doc(d.id), m, SetOptions(merge: false));
      }
      await batch.commit();

      final delBatch = _db.batch();
      for (final d in snaps.docs) {
        delBatch.delete(d.reference);
      }
      await delBatch.commit();
    }

    // 4) Delete customer doc from archive
    await archRef.delete();
  }

  /// Fetch archived customers (boss-only)
  static Future<List<HomeCustomer>> fetchArchivedCustomers() async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can view archived customers');
    }
    final snap = await _db.collection(archivedCustomersCol).orderBy('archived_at', descending: true).get();
    return snap.docs.map((d) => HomeCustomer.fromMap(d.data(), d.id)).toList();
  }

  /// Boss-only: Create a home user account linked to a customer ID
  /// This creates a Firebase Auth user with role 'homeuser' and links it to the customer
  static Future<void> createHomeUserAccount({
    required String customerId,
    required String email,
    required String password,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can create home user accounts');
    }

    // Verify customer exists
    final customer = await getCustomer(customerId);
    if (customer == null) {
      throw Exception('Customer not found');
    }

    // Create user account via AuthController with home_customer_id
    // The Cloud Function will store the customer ID immediately
    await _auth.createNewAccount(
      email,
      password,
      'homeuser',
      name: customer.name,
      location: null,
      locations: null,
      homeCustomerId: customerId, // Pass customer ID to Cloud Function
    );
  }

  /// Check if a home user account exists for a given customer ID
  /// Returns the user's email if found, null otherwise
  static Future<String?> getHomeUserEmail(String customerId) async {
    try {
      final usersSnap = await _db
          .collection('users')
          .where('home_customer_id', isEqualTo: customerId)
          .limit(1)
          .get();
      
      if (usersSnap.docs.isEmpty) return null;
      
      final userData = usersSnap.docs.first.data();
      return userData['email'] as String?;
    } catch (e) {
      print('Error fetching home user email: $e');
      return null;
    }
  }

  static Future<List<String>> fetchCustomerTypes() async {
    final doc = await _db.collection(configCol).doc(enumsDoc).get();
    final data = doc.data() ?? {};
    final types = (data['customer_types'] as List?)?.map((e) => '$e').toList();
    return types == null || types.isEmpty
        ? <String>[]
        : types;
  }

  static Future<void> setDropdownOptions({
    required List<String> zones,
    required List<String> customerTypes,
  }) async {
    await _db.collection(configCol).doc(enumsDoc).set({
      'zones': zones,
      'customer_types': customerTypes,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by_uid': _auth.user?.uid,
      'updated_by_name': _auth.userName,
    }, SetOptions(merge: true));
  }

  // ------------------------------
  // Real-time Stream Methods (Offline-First)
  // ------------------------------
  
  /// Stream all active customers in real-time
  /// Data is served from cache first, then synced in background
  static Stream<List<HomeCustomer>> streamCustomers() {
    return _db
        .collection(customersCol)
        .orderBy('status.sort_key', descending: true)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => HomeCustomer.fromMap(d.data(), d.id))
            .toList());
  }

  /// Stream a single customer in real-time
  static Stream<HomeCustomer?> streamCustomer(String id) {
    return _db
        .collection(customersCol)
        .doc(id)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return HomeCustomer.fromMap(snap.data()!, snap.id);
        });
  }

  /// Stream archived customers in real-time (boss-only)
  static Stream<List<HomeCustomer>> streamArchivedCustomers() {
    if (!_auth.isBoss) {
      return Stream.error(Exception('Only boss can view archived customers'));
    }
    return _db
        .collection(archivedCustomersCol)
        .orderBy('archived_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => HomeCustomer.fromMap(d.data(), d.id))
            .toList());
  }

  /// Stream payments for a customer in real-time
  static Stream<List<PaymentRecord>> streamPayments(String customerId) {
    return _paymentsCol(customerId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PaymentRecord.fromMap(d.data(), d.id))
            .toList());
  }

  /// Stream pending approval payments in real-time
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPendingApprovalGroup() {
    return _db
        .collectionGroup('payments')
        .where('status', isEqualTo: PaymentStatus.pendingApproval.name)
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Works when collectionGroup('payments') is blocked by top-level-only rules.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchPendingApprovalsFromCustomers() async {
    final customers = await _db.collection(customersCol).limit(300).get();
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final customer in customers.docs) {
      final pays = await _paymentsCol(customer.id)
          .where('status', isEqualTo: PaymentStatus.pendingApproval.name)
          .limit(20)
          .get();
      out.addAll(pays.docs);
    }
    DateTime? createdAt(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final raw = doc.data()['created_at'];
      if (raw is Timestamp) return raw.toDate();
      return null;
    }
    out.sort((a, b) {
      final at = createdAt(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = createdAt(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    if (out.length <= 100) return out;
    return out.sublist(0, 100);
  }

  static Stream<List<PaymentRecord>> streamPendingPayments(String customerId) {
    return _paymentsCol(customerId)
        .where('status', isEqualTo: PaymentStatus.pendingApproval.name)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PaymentRecord.fromMap(d.data(), d.id))
            .toList());
  }

  // ------------------------------
  // Customer Management
  // ------------------------------
  static String _random5Digit() {
    final n = Random.secure().nextInt(100000); // 0..99999
    return n.toString().padLeft(5, '0');
  }

  static Future<String> generateCustomerId({int maxAttempts = 50}) async {
    for (int i = 0; i < maxAttempts; i++) {
      final id = _random5Digit();
      final exists = await _db.collection(customersCol).doc(id).get();
      if (!exists.exists) return id;
    }
    throw Exception('Failed to generate unique 5-digit customer ID after $maxAttempts attempts');
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
    final id = await generateCustomerId();
    final now = DateTime.now();
    final createdByUid = _auth.user?.uid ?? '';
    final createdByName = _auth.userName;

    final customer = HomeCustomer(
      id: id,
      name: name,
      phone: phone,
      location: location,
      zone: zone,
      speedMbps: speedMbps,
      customerType: customerType,
      planAmount: planAmount,
      currency: currency,
      schedule: schedule,
      startDate: startDate,
      billingDayOfMonth: billingDayOfMonth,
      billingWeekday: billingWeekday,
      address: address,
      notes: notes,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: now,
      updatedAt: null,
      active: true,
    );

    await _db.collection(customersCol).doc(id).set(customer.toMap());
    // record initial plan snapshot so historical periods stick to their price
    final initialPlan = PlanSnapshot(
      amount: planAmount,
      currency: currency,
      effectiveFrom: startDate,
    );
    await _plansCol(id).add(initialPlan.toMap());
    return customer;
  }

  static Future<HomeCustomer?> getCustomer(String id) async {
    final snap = await _db.collection(customersCol).doc(id).get();
    if (!snap.exists) return null;
    return HomeCustomer.fromMap(snap.data()!, snap.id);
  }

  /// Boss-only: backfill initial plan snapshots for existing customers
  /// Returns the number of customers for which a snapshot was created
  static Future<int> backfillPlanSnapshots() async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can backfill plan snapshots');
    }
    final customersSnap = await _db.collection(customersCol).get();
    int created = 0;
    for (final doc in customersSnap.docs) {
      final c = HomeCustomer.fromMap(doc.data(), doc.id);
      final plans = await _plansCol(c.id).limit(1).get();
      if (plans.docs.isEmpty) {
        final snap = PlanSnapshot(
          amount: c.planAmount,
          currency: c.currency,
          effectiveFrom: c.startDate,
        );
        await _plansCol(c.id).add(snap.toMap());
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
    final existing = await getCustomer(id);
    final Map<String, dynamic> updates = {
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by_uid': _auth.user?.uid,
      'updated_by_name': _auth.userName,
    };
    void setIf<T>(String key, T? v) { if (v != null) updates[key] = v; }
    setIf<String>('name', name);
    setIf<String>('phone', phone);
    setIf<String>('location', location);
    setIf<String>('zone', zone);
    setIf<int>('speed_mbps', speedMbps);
    setIf<String>('customer_type', customerType);
    setIf<double>('plan_amount', planAmount);
    setIf<String>('currency', currency);
    if (schedule != null) updates['schedule'] = schedule.name;
    setIf<int>('billing_day_of_month', billingDayOfMonth);
    setIf<int>('billing_weekday', billingWeekday);
    setIf<String>('address', address);
    setIf<String>('notes', notes);
    setIf<bool>('active', active);

    await _db.collection(customersCol).doc(id).set(updates, SetOptions(merge: true));

    // If plan amount or currency changed, append a new snapshot effective now
    if (existing != null) {
      final newAmount = planAmount ?? existing.planAmount;
      final newCurrency = currency ?? existing.currency;
      final changed = (newAmount != existing.planAmount) || (newCurrency != existing.currency);
      if (changed) {
        final snap = PlanSnapshot(
          amount: newAmount,
          currency: newCurrency,
          effectiveFrom: DateTime.now(),
        );
        await _plansCol(id).add(snap.toMap());
      }
    }
  }

  /// Boss-only: Permanently delete a customer and all related data.
  /// This will delete:
  /// - all payment documents under `home_customers/{id}/payments` and their storage attachments
  /// - all plan snapshots under `home_customers/{id}/plan_snapshots`
  /// - the customer document itself
  static Future<void> deleteCustomer({required String id}) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can delete customer');
    }

    // 1) Delete payments and attachments
    while (true) {
      final paySnap = await _paymentsCol(id).limit(300).get();
      if (paySnap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in paySnap.docs) {
        final data = d.data();
        // delete storage attachments if present
        final atts = (data['attachments'] as List?) ?? const [];
        for (final a in atts) {
          try {
            final m = (a is Map) ? a : null;
            final path = m?['storage_path'] as String?;
            if (path != null && path.isNotEmpty) {
              await _storage.ref().child(path).delete();
            }
          } catch (_) {
            // ignore individual storage delete errors
          }
        }
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    // 2) Delete plan snapshots
    while (true) {
      final snaps = await _plansCol(id).limit(300).get();
      if (snaps.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snaps.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    // 3) Delete the customer document
    await _db.collection(customersCol).doc(id).delete();
  }

  // ------------------------------
  // Payments
  // ------------------------------
  static CollectionReference<Map<String, dynamic>> _paymentsCol(String customerId) =>
      _db.collection(customersCol).doc(customerId).collection('payments');

  static CollectionReference<Map<String, dynamic>> _plansCol(String customerId) =>
      _db.collection(customersCol).doc(customerId).collection('plan_snapshots');

  // ------------------------------
  // Analytics helpers
  // ------------------------------
  static DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime _nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1, 1);

  /// Returns { total_amount: double, count: int }
  /// Counts approved payments in [start, end) time window by approved_at.
  /// Optional client-side filters by zone and customerType.
  static Future<Map<String, dynamic>> fetchPaymentsTotal({
    required DateTime start,
    required DateTime end,
    String? zone,
    String? customerType,
  }) async {
    // Aggregate per-customer to avoid composite index requirements entirely
    // Build customers query using at most one where to avoid composite index
    Query<Map<String, dynamic>> cq = _db.collection(customersCol);
    if (zone != null && zone.isNotEmpty && (customerType == null || customerType.isEmpty)) {
      cq = cq.where('zone', isEqualTo: zone);
    } else if (customerType != null && customerType.isNotEmpty && (zone == null || zone.isEmpty)) {
      cq = cq.where('customer_type', isEqualTo: customerType);
    }

    final custSnap = await cq.get();
    double total = 0.0;
    int count = 0;
    for (final c in custSnap.docs) {
      final data = c.data();
      if (zone != null && zone.isNotEmpty && data['zone'] != zone) continue;
      if (customerType != null && customerType.isNotEmpty && data['customer_type'] != customerType) continue;

      // Date-bounded query — do not download every historical payment.
      final allSnap = await _db
          .collection(customersCol)
          .doc(c.id)
          .collection('payments')
          .where('approved_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('approved_at', isLessThan: Timestamp.fromDate(end))
          .limit(100)
          .get();
      for (final p in allSnap.docs) {
        final m = p.data();
        if (m['status'] != PaymentStatus.approved.name) continue;
        final ts = m['approved_at'];
        DateTime? at;
        if (ts is Timestamp) {
          at = ts.toDate();
        } else if (ts is DateTime) {
          at = ts;
        }
        if (at == null) continue;
        if (at.isBefore(start) || !at.isBefore(end)) continue;
        final amt = (m['amount_paid'] is num) ? (m['amount_paid'] as num).toDouble() : 0.0;
        total += amt;
        count++;
      }
    }
    return {
      'total_amount': total,
      'count': count,
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

    // Determine current due period based on schedule
    final now = DateTime.now();
    final period = _currentDuePeriod(customer, now);

    final payDoc = _paymentsCol(customerId).doc();
    final createdByUid = _auth.user?.uid ?? '';
    final createdByName = _auth.userName;

    // Upload attachments first
    final List<AttachmentRef> uploaded = [];
    for (final a in attachments) {
      uploaded.add(await _uploadAttachment(
        customerId: customerId,
        paymentId: payDoc.id,
        file: a,
      ));
    }

    final record = PaymentRecord(
      id: payDoc.id,
      customerId: customerId,
      amountPaid: amountPaid,
      currency: currency,
      attachments: uploaded,
      status: PaymentStatus.pendingApproval,
      createdByUid: createdByUid,
      createdByName: createdByName,
      createdAt: now,
      approvedByUid: null,
      approvedByName: null,
      approvedAt: null,
      schedule: customer.schedule,
      periodStart: period.start,
      periodEnd: period.end,
      dueDate: period.due,
      reference: reference,
      notes: notes,
      paymentType: paymentType,
      customerZone: customer.zone,
      customerType: customer.customerType,
    );

    await payDoc.set(record.toMap());
    return record;
  }

  static Future<void> approvePayment({
    required String customerId,
    required String paymentId,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can approve payments');
    }
    final payRef = _paymentsCol(customerId).doc(paymentId);
    final snap = await payRef.get();
    if (!snap.exists) {
      throw Exception('Payment not found');
    }
    final data = snap.data()!;
    final createdByUid = data['created_by_uid'] as String? ?? '';
    final approverUid = _auth.user?.uid ?? '';

    if (createdByUid.isNotEmpty && createdByUid == approverUid) {
      throw Exception('You cannot approve your own entry');
    }

    await payRef.update({
      'status': PaymentStatus.approved.name,
      'approved_by_uid': approverUid,
      'approved_by_name': _auth.userName,
      'approved_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> rejectPayment({
    required String customerId,
    required String paymentId,
    String? reason,
  }) async {
    if (!_auth.isBoss) {
      throw Exception('Only boss can reject payments');
    }
    final payRef = _paymentsCol(customerId).doc(paymentId);
    final snap = await payRef.get();
    if (!snap.exists) {
      throw Exception('Payment not found');
    }
    final data = snap.data()!;
    final createdByUid = data['created_by_uid'] as String? ?? '';
    final approverUid = _auth.user?.uid ?? '';

    if (createdByUid.isNotEmpty && createdByUid == approverUid) {
      throw Exception('You cannot reject your own entry');
    }

    await payRef.update({
      'status': PaymentStatus.rejected.name,
      'approved_by_uid': approverUid,
      'approved_by_name': _auth.userName,
      'approved_at': FieldValue.serverTimestamp(),
      if (reason != null) 'notes': 'Rejected: $reason',
    });
  }

  // ------------------------------
  // Status computation
  // ------------------------------
  static Future<Map<String, dynamic>> computeCustomerStatus(String customerId) async {
    final customer = await getCustomer(customerId);
    if (customer == null) throw Exception('Customer not found');

    final now = DateTime.now();
    final periodsDue = _periodsDueUpToNow(customer, now);

    // Sum of approved payments
    final approved = await _paymentsCol(customerId)
        .where('status', isEqualTo: PaymentStatus.approved.name)
        .get();
    double totalPaid = 0.0;
    DateTime? lastPaidAt;
    for (final d in approved.docs) {
      final m = d.data();
      final amt = (m['amount_paid'] is num) ? (m['amount_paid'] as num).toDouble() : 0.0;
      totalPaid += amt;
      final paidAt = _fromTs(m['approved_at']) ?? _fromTs(m['created_at']);
      if (paidAt != null) {
        if (lastPaidAt == null || paidAt.isAfter(lastPaidAt!)) lastPaidAt = paidAt;
      }
    }

    // Use dynamic required amounts from period statuses (respects plan snapshots)
    final periodStatuses = await listPeriodStatuses(customerId, upTo: now);
    final double totalDueAmount = periodStatuses.fold(0.0, (s, p) => s + p.requiredAmount);
    final outstanding = (totalDueAmount - totalPaid);
    final latestPeriod = _currentDuePeriod(customer, now);
    final isOverdue = outstanding > 0 && now.isAfter(latestPeriod.due);

    return {
      'periods_due': periodsDue,
      'total_due_amount': totalDueAmount,
      'total_paid_amount': totalPaid,
      'outstanding_amount': outstanding,
      'overdue': isOverdue,
      'next_due_date': latestPeriod.due,
      'last_paid_at': lastPaidAt,
      'currency': customer.currency,
    };
  }

  /// Returns the list of period payment statuses (paid/partial/unpaid) up to [upTo] (default: now)
  /// Each period requires [planAmount] at the time of computation (current plan amount).
  /// Payments are allocated FIFO to the earliest unpaid periods.
  static Future<List<PeriodPaymentStatus>> listPeriodStatuses(
    String customerId, {
    DateTime? upTo,
  }) async {
    final customer = await getCustomer(customerId);
    if (customer == null) throw Exception('Customer not found');
    final now = upTo ?? DateTime.now();

    // Determine first due date and number of periods up to now (inclusive)
    final int periodsDue = _periodsDueUpToNow(customer, now);
    if (periodsDue <= 0) return <PeriodPaymentStatus>[];

    // Build the list of periods
    final List<_Period> periods = [];
    if (customer.schedule == PaymentScheduleType.weekly) {
      // Compute firstDue (same logic as _weekPeriod/_weeksBetween)
      final int anchorWeekday = customer.billingWeekday ?? customer.startDate.weekday; // 1..7
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
        final due = start;
        periods.add(_Period(start: start, end: end, due: due));
      }
    } else {
      // monthly
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
        final due = start;
        periods.add(_Period(start: start, end: end, due: due));
      }
    }

    // Gather plan snapshots for dynamic pricing
    final snapsQuery = await _plansCol(customerId)
        .orderBy('effective_from', descending: false)
        .get();
    final List<PlanSnapshot> snapshots = snapsQuery.docs
        .map((d) => PlanSnapshot.fromMap(d.data()))
        .toList();
    double _requiredFor(DateTime date) {
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

    // Gather approved payments and total amount
    final approvedSnap = await _paymentsCol(customerId)
        .where('status', isEqualTo: PaymentStatus.approved.name)
        .get();
    final List<Map<String, dynamic>> approved = approvedSnap.docs
        .map((d) => d.data())
        .toList();
    // Sort by approval time (fallback to created_at)
    approved.sort((a, b) {
      final atA = _fromTs(a['approved_at']) ?? _fromTs(a['created_at']) ?? DateTime(1970);
      final atB = _fromTs(b['approved_at']) ?? _fromTs(b['created_at']) ?? DateTime(1970);
      return atA.compareTo(atB);
    });
    double totalPaid = 0.0;
    for (final m in approved) {
      final amt = (m['amount_paid'] is num) ? (m['amount_paid'] as num).toDouble() : 0.0;
      totalPaid += amt;
    }

    // Allocate payments FIFO to periods
    double remaining = totalPaid;
    final List<PeriodPaymentStatus> results = [];
    for (final p in periods) {
      final double requiredPerPeriod = _requiredFor(p.start);
      final double allocated = remaining >= requiredPerPeriod
          ? requiredPerPeriod
          : (remaining > 0 ? remaining : 0.0);
      remaining = (remaining - allocated);
      final status = allocated >= requiredPerPeriod
          ? PeriodPayState.paid
          : (allocated > 0 ? PeriodPayState.partial : PeriodPayState.unpaid);
      results.add(
        PeriodPaymentStatus(
          start: p.start,
          end: p.end,
          due: p.due,
          requiredAmount: requiredPerPeriod,
          paidAmount: allocated,
          state: status,
        ),
      );
    }

    return results;
  }

  // ------------------------------
  // Period helpers
  // ------------------------------
  static _Period _currentDuePeriod(HomeCustomer c, DateTime now) {
    if (c.schedule == PaymentScheduleType.weekly) {
      return _weekPeriod(c, now);
    } else {
      return _monthPeriod(c, now);
    }
  }

  static int _periodsDueUpToNow(HomeCustomer c, DateTime now) {
    if (c.schedule == PaymentScheduleType.weekly) {
      return _weeksDueUpTo(c, now);
    } else {
      return _monthsDueUpTo(c, now);
    }
  }

  static _Period _weekPeriod(HomeCustomer c, DateTime ref) {
    final int anchorWeekday = c.billingWeekday ?? c.startDate.weekday; // 1..7
    // First due: first anchor weekday AFTER startDate
    DateTime firstDue = c.startDate;
    final int diff = (anchorWeekday - firstDue.weekday);
    if (diff > 0) {
      firstDue = firstDue.add(Duration(days: diff));
    } else if (diff < 0) {
      firstDue = firstDue.add(Duration(days: (7 + diff)));
    } else {
      firstDue = firstDue.add(const Duration(days: 7));
    }
    
    // If ref is before firstDue, we're still in the first period
    if (ref.isBefore(firstDue)) {
      final end = firstDue.subtract(const Duration(seconds: 1));
      return _Period(start: c.startDate, end: end, due: firstDue);
    }
    
    // Number of weeks from firstDue to ref
    int weeks = ((ref.difference(firstDue).inDays) ~/ 7) + 1; // inclusive
    final start = firstDue.add(Duration(days: 7 * (weeks - 1)));
    final end = start.add(const Duration(days: 7)).subtract(const Duration(seconds: 1));
    final due = start; // due at start of period
    return _Period(start: start, end: end, due: due);
  }

  static int _weeksBetween(HomeCustomer c, DateTime ref) {
    final int anchorWeekday = c.billingWeekday ?? c.startDate.weekday; // 1..7
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
    final weeks = ((ref.difference(firstDue).inDays) ~/ 7) + 1; // inclusive count
    return weeks;
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
    // First due is anchor day in the month AFTER startDate
    DateTime firstDue = DateTime(c.startDate.year, c.startDate.month, anchorDay,
        c.startDate.hour, c.startDate.minute, c.startDate.second, c.startDate.millisecond, c.startDate.microsecond);
    if (!firstDue.isAfter(c.startDate)) {
      firstDue = DateTime(firstDue.year, firstDue.month + 1, anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    }
    
    // If ref is before firstDue, we're still in the first period
    if (ref.isBefore(firstDue)) {
      final end = firstDue.subtract(const Duration(seconds: 1));
      return _Period(start: c.startDate, end: end, due: firstDue);
    }
    
    // Number of months from firstDue to ref
    int months = (ref.year - firstDue.year) * 12 + (ref.month - firstDue.month) + 1; // inclusive
    final start = DateTime(firstDue.year, firstDue.month + (months - 1), anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    final end = DateTime(start.year, start.month + 1, anchorDay).subtract(const Duration(seconds: 1));
    final due = start; // due at period start
    return _Period(start: start, end: end, due: due);
  }

  static int _monthsBetween(HomeCustomer c, DateTime ref) {
    final int anchorDay = (c.billingDayOfMonth ?? c.startDate.day).clamp(1, 28);
    DateTime firstDue = DateTime(c.startDate.year, c.startDate.month, anchorDay,
        c.startDate.hour, c.startDate.minute, c.startDate.second, c.startDate.millisecond, c.startDate.microsecond);
    if (!firstDue.isAfter(c.startDate)) {
      firstDue = DateTime(firstDue.year, firstDue.month + 1, anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    }
    if (ref.isBefore(firstDue)) return 0;
    final months = (ref.year - firstDue.year) * 12 + (ref.month - firstDue.month) + 1; // inclusive count
    return months;
  }
  /// Count only months whose due timestamp has actually occurred (<= ref)
  static int _monthsDueUpTo(HomeCustomer c, DateTime ref) {
    final int anchorDay = (c.billingDayOfMonth ?? c.startDate.day).clamp(1, 28);
    DateTime firstDue = DateTime(c.startDate.year, c.startDate.month, anchorDay,
        c.startDate.hour, c.startDate.minute, c.startDate.second, c.startDate.millisecond, c.startDate.microsecond);
    if (!firstDue.isAfter(c.startDate)) {
      firstDue = DateTime(firstDue.year, firstDue.month + 1, anchorDay, firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    }
    if (ref.isBefore(firstDue)) return 0;
    final int monthsDiff = (ref.year - firstDue.year) * 12 + (ref.month - firstDue.month);
    final DateTime dueThisMonth = DateTime(firstDue.year, firstDue.month + monthsDiff, anchorDay,
        firstDue.hour, firstDue.minute, firstDue.second, firstDue.millisecond, firstDue.microsecond);
    return ref.isBefore(dueThisMonth) ? monthsDiff : (monthsDiff + 1);
  }

  static DateTime? _fromTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

class _Period {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  _Period({required this.start, required this.end, required this.due});
}

// Public types for UI consumption
/// Payment coverage state for a billing period
enum PeriodPayState { paid, partial, unpaid }

/// Status summary for a specific billing period
class PeriodPaymentStatus {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  final double requiredAmount;
  final double paidAmount;
  final PeriodPayState state;

  const PeriodPaymentStatus({
    required this.start,
    required this.end,
    required this.due,
    required this.requiredAmount,
    required this.paidAmount,
    required this.state,
  });
}
