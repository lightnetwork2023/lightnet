import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_logger.dart';

class DebtService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Payables - Money company owes to others
  static CollectionReference get payables => _firestore.collection('debt_payables');
  
  // Receivables - Money owed to company
  static CollectionReference get receivables => _firestore.collection('debt_receivables');

  // Add new payable (company owes money)
  static Future<String> addPayable({
    required String creditorName,
    required double totalAmount,
    required String description,
    String? dueDate,
    String? category,
  }) async {
    final doc = await payables.add({
      'creditorName': creditorName,
      'totalAmount': totalAmount,
      'amountPaid': 0.0,
      'balance': totalAmount,
      'description': description,
      'dueDate': dueDate,
      'category': category ?? 'General',
      'status': 'unpaid',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AppLogger.logPayableAdded(docId: doc.id, amount: totalAmount, creditorName: creditorName);
    return doc.id;
  }

  // Add new receivable (someone owes company)
  static Future<String> addReceivable({
    required String debtorName,
    required double totalAmount,
    required String description,
    String? dueDate,
    String? category,
    String? phone,
  }) async {
    final doc = await receivables.add({
      'debtorName': debtorName,
      'phone': phone,
      'totalAmount': totalAmount,
      'amountPaid': 0.0,
      'balance': totalAmount,
      'description': description,
      'dueDate': dueDate,
      'category': category ?? 'General',
      'status': 'unpaid',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AppLogger.logReceivableAdded(docId: doc.id, amount: totalAmount, debtorName: debtorName);
    return doc.id;
  }

  // Record payment for payable
  static Future<void> recordPayablePayment({
    required String debtId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) async {
    final debtDoc = payables.doc(debtId);
    final debtSnapshot = await debtDoc.get();
    
    if (!debtSnapshot.exists) {
      throw Exception('Debt not found');
    }

    final data = debtSnapshot.data() as Map<String, dynamic>;
    final currentPaid = (data['amountPaid'] ?? 0.0).toDouble();
    final totalAmount = (data['totalAmount'] ?? 0.0).toDouble();
    final newPaid = currentPaid + amount;
    final newBalance = totalAmount - newPaid;

    // Add payment to sub-collection
    await debtDoc.collection('payments').add({
      'amount': amount,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update debt status
    String status;
    if (newBalance <= 0) {
      status = 'paid';
    } else if (newPaid > 0) {
      status = 'partial';
    } else {
      status = 'unpaid';
    }

    await debtDoc.update({
      'amountPaid': newPaid,
      'balance': newBalance,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AppLogger.logDebtPaymentRecorded(debtId: debtId, amount: amount, isPayable: true);
  }

  // Record payment for receivable
  static Future<void> recordReceivablePayment({
    required String debtId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) async {
    final debtDoc = receivables.doc(debtId);
    final debtSnapshot = await debtDoc.get();
    
    if (!debtSnapshot.exists) {
      throw Exception('Debt not found');
    }

    final data = debtSnapshot.data() as Map<String, dynamic>;
    final currentPaid = (data['amountPaid'] ?? 0.0).toDouble();
    final totalAmount = (data['totalAmount'] ?? 0.0).toDouble();
    final newPaid = currentPaid + amount;
    final newBalance = totalAmount - newPaid;

    // Add payment to sub-collection
    await debtDoc.collection('payments').add({
      'amount': amount,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Update debt status
    String status;
    if (newBalance <= 0) {
      status = 'paid';
    } else if (newPaid > 0) {
      status = 'partial';
    } else {
      status = 'unpaid';
    }

    await debtDoc.update({
      'amountPaid': newPaid,
      'balance': newBalance,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    AppLogger.logDebtPaymentRecorded(debtId: debtId, amount: amount, isPayable: false);
  }

  // Get payment history for a debt
  static Stream<QuerySnapshot> getPaymentHistory(String debtId, bool isPayable) {
    final collection = isPayable ? payables : receivables;
    return collection.doc(debtId).collection('payments')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Delete payable
  static Future<void> deletePayable(String debtId) async {
    await payables.doc(debtId).delete();
    AppLogger.logDebtDeleted(debtId: debtId, isPayable: true);
  }

  // Delete receivable
  static Future<void> deleteReceivable(String debtId) async {
    await receivables.doc(debtId).delete();
    AppLogger.logDebtDeleted(debtId: debtId, isPayable: false);
  }

  // Update payable
  static Future<void> updatePayable({
    required String debtId,
    String? creditorName,
    double? totalAmount,
    String? description,
    String? dueDate,
    String? category,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    
    if (creditorName != null) updates['creditorName'] = creditorName;
    if (description != null) updates['description'] = description;
    if (dueDate != null) updates['dueDate'] = dueDate;
    if (category != null) updates['category'] = category;
    
    if (totalAmount != null) {
      final doc = await payables.doc(debtId).get();
      final data = doc.data() as Map<String, dynamic>;
      final amountPaid = (data['amountPaid'] ?? 0.0).toDouble();
      updates['totalAmount'] = totalAmount;
      updates['balance'] = totalAmount - amountPaid;
    }

    await payables.doc(debtId).update(updates);
  }

  // Update receivable
  static Future<void> updateReceivable({
    required String debtId,
    String? debtorName,
    String? phone,
    double? totalAmount,
    String? description,
    String? dueDate,
    String? category,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    
    if (debtorName != null) updates['debtorName'] = debtorName;
    if (phone != null) updates['phone'] = phone;
    if (description != null) updates['description'] = description;
    if (dueDate != null) updates['dueDate'] = dueDate;
    if (category != null) updates['category'] = category;
    
    if (totalAmount != null) {
      final doc = await receivables.doc(debtId).get();
      final data = doc.data() as Map<String, dynamic>;
      final amountPaid = (data['amountPaid'] ?? 0.0).toDouble();
      updates['totalAmount'] = totalAmount;
      updates['balance'] = totalAmount - amountPaid;
    }

    await receivables.doc(debtId).update(updates);
  }
}
