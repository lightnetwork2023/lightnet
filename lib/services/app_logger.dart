import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/auth_controller.dart';

/// Central write-only logger. Stores all app mutations and errors in
/// Firestore collection `app_logs`. Never throws — logging failure must never
/// affect the user-facing flow.
class AppLogger {
  static final _db = FirebaseFirestore.instance;

  static Future<void> log(
    String event, {
    Map<String, dynamic>? data,
    String? error,
    bool isError = false,
  }) async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      String? uid = firebaseUser?.uid;
      String? name;
      String? role;

      try {
        final auth = Get.find<AuthController>();
        uid ??= auth.user?.uid;
        name = auth.userName.isNotEmpty ? auth.userName : null;
        role = auth.userRole.isNotEmpty ? auth.userRole : null;
      } catch (_) {}

      final now = DateTime.now().toUtc();

      final doc = <String, dynamic>{
        'event': event,
        'is_error': isError || error != null,
        'uid': uid,
        'name': name,
        'role': role,
        'timestamp': FieldValue.serverTimestamp(),
        'day': DateFormat('yyyy-MM-dd').format(now),
        'month': DateFormat('yyyy-MM').format(now),
        if (data != null) ...data,
        if (error != null) 'error': error,
      };

      await _db.collection('app_logs').add(doc);
    } catch (_) {
      // Silently swallow — logging must never crash the app
    }
  }

  // ── Convenience helpers ──────────────────────────────────────────────────

  static Future<void> logError(String action, dynamic err) =>
      log('error', isError: true, data: {'action': action}, error: err.toString());

  static Future<void> logSignIn(String role, String name) =>
      log('user_signed_in', data: {'signed_in_role': role, 'signed_in_name': name});

  static Future<void> logSignOut() => log('user_signed_out');

  static Future<void> logUserCreated({
    required String email,
    required String role,
    String? name,
    String? location,
  }) =>
      log('user_created', data: {
        'new_email': email,
        'new_role': role,
        if (name != null) 'new_name': name,
        if (location != null) 'new_location': location,
      });

  static Future<void> logUserDeleted({required String targetUid, String? targetName}) =>
      log('user_deleted', data: {
        'target_uid': targetUid,
        if (targetName != null) 'target_name': targetName,
      });

  static Future<void> logUserRoleUpdated({
    required String targetUid,
    required String newRole,
    String? oldRole,
  }) =>
      log('user_role_updated', data: {
        'target_uid': targetUid,
        'new_role': newRole,
        if (oldRole != null) 'old_role': oldRole,
      });

  static Future<void> logPasswordResetSent(String targetEmail) =>
      log('password_reset_sent', data: {'target_email': targetEmail});

  static Future<void> logVouchersGenerated({
    required int numUsers,
    required double numDays,
    required String location,
    String? speedLimit,
  }) =>
      log('vouchers_generated', data: {
        'num_users': numUsers,
        'num_days': numDays,
        'location': location,
        if (speedLimit != null) 'speed_limit': speedLimit,
      });

  static Future<void> logVoucherGeneratedOne({required String durationKey}) =>
      log('voucher_generated_one', data: {'duration_key': durationKey});

  static Future<void> logUserDeletedRadius(String username) =>
      log('user_deleted_radius', data: {'username': username});

  static Future<void> logPaymentInitiated({
    required String provider,
    required String phone,
    required int amount,
    required int quantity,
    required String location,
    int? days,
  }) =>
      log('payment_initiated', data: {
        'provider': provider,
        'phone': phone,
        'amount': amount,
        'quantity': quantity,
        'location': location,
        if (days != null) 'days': days,
      });

  static Future<void> logVoucherSettingsUpdated({
    String? username,
    String? macAddress,
    String? speedLimit,
    String? expireTime,
  }) =>
      log('voucher_settings_updated', data: {
        if (username != null) 'username': username,
        if (macAddress != null) 'mac_address': macAddress,
        if (speedLimit != null) 'speed_limit': speedLimit,
        if (expireTime != null) 'expire_time': expireTime,
      });

  static Future<void> logVoucherDeleted(String username) =>
      log('voucher_deleted', data: {'username': username});

  static Future<void> logHomeCustomerCreated({
    required String customerId,
    required String name,
    String? location,
  }) =>
      log('home_customer_created', data: {
        'customer_id': customerId,
        'customer_name': name,
        if (location != null) 'location': location,
      });

  static Future<void> logHomeCustomerUpdated(String customerId) =>
      log('home_customer_updated', data: {'customer_id': customerId});

  static Future<void> logHomeCustomerDeleted({required String customerId, String? name}) =>
      log('home_customer_deleted', data: {
        'customer_id': customerId,
        if (name != null) 'customer_name': name,
      });

  static Future<void> logHomeCustomerArchived(String customerId) =>
      log('home_customer_archived', data: {'customer_id': customerId});

  static Future<void> logHomeCustomerRestored(String customerId) =>
      log('home_customer_restored', data: {'customer_id': customerId});

  static Future<void> logHomePaymentAdded({
    required String customerId,
    required double amount,
    String? currency,
  }) =>
      log('home_payment_added', data: {
        'customer_id': customerId,
        'amount': amount,
        if (currency != null) 'currency': currency,
      });

  static Future<void> logHomePaymentApproved({
    required String customerId,
    required String paymentId,
  }) =>
      log('home_payment_approved', data: {
        'customer_id': customerId,
        'payment_id': paymentId,
      });

  static Future<void> logHomePaymentRejected({
    required String customerId,
    required String paymentId,
    String? reason,
  }) =>
      log('home_payment_rejected', data: {
        'customer_id': customerId,
        'payment_id': paymentId,
        if (reason != null) 'reason': reason,
      });

  static Future<void> logExpenseSubmitted({
    required String expenseId,
    required double amount,
    String? title,
    String? location,
    bool isUpdate = false,
  }) =>
      log(isUpdate ? 'expense_updated' : 'expense_submitted', data: {
        'expense_id': expenseId,
        'amount': amount,
        if (title != null) 'title': title,
        if (location != null) 'location': location,
      });

  static Future<void> logExpenseApproved({
    required String expenseId,
    double? amount,
    String? submittedBy,
  }) =>
      log('expense_approved', data: {
        'expense_id': expenseId,
        if (amount != null) 'amount': amount,
        if (submittedBy != null) 'submitted_by': submittedBy,
      });

  static Future<void> logExpenseRejected({
    required String expenseId,
    String? reason,
    double? amount,
  }) =>
      log('expense_rejected', data: {
        'expense_id': expenseId,
        if (reason != null) 'reason': reason,
        if (amount != null) 'amount': amount,
      });

  static Future<void> logSimcardAdded({
    required String msisdn,
    String? location,
    String? type,
  }) =>
      log('simcard_added', data: {
        'msisdn': msisdn,
        if (location != null) 'location': location,
        if (type != null) 'sim_type': type,
      });

  static Future<void> logSimcardUpdated({required String docId, String? msisdn}) =>
      log('simcard_updated', data: {
        'doc_id': docId,
        if (msisdn != null) 'msisdn': msisdn,
      });

  static Future<void> logSimcardDeleted({required String docId, String? msisdn}) =>
      log('simcard_deleted', data: {
        'doc_id': docId,
        if (msisdn != null) 'msisdn': msisdn,
      });

  static Future<void> logPayableAdded({
    required String docId,
    required double amount,
    String? creditorName,
  }) =>
      log('payable_added', data: {
        'doc_id': docId,
        'amount': amount,
        if (creditorName != null) 'creditor_name': creditorName,
      });

  static Future<void> logReceivableAdded({
    required String docId,
    required double amount,
    String? debtorName,
  }) =>
      log('receivable_added', data: {
        'doc_id': docId,
        'amount': amount,
        if (debtorName != null) 'debtor_name': debtorName,
      });

  static Future<void> logDebtPaymentRecorded({
    required String debtId,
    required double amount,
    required bool isPayable,
  }) =>
      log('debt_payment_recorded', data: {
        'debt_id': debtId,
        'amount': amount,
        'type': isPayable ? 'payable' : 'receivable',
      });

  static Future<void> logDebtDeleted({
    required String debtId,
    required bool isPayable,
  }) =>
      log('debt_deleted', data: {
        'debt_id': debtId,
        'type': isPayable ? 'payable' : 'receivable',
      });

  static Future<void> logNetworkDeviceAdded({
    required String name,
    required String location,
    required String macId,
  }) =>
      log('network_device_added', data: {
        'device_name': name,
        'location': location,
        'mac_id': macId,
      });

  static Future<void> logNetworkDeviceDeleted(String macId) =>
      log('network_device_deleted', data: {'mac_id': macId});
}
