import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../controllers/auth_controller.dart';

class ExpenseApprovalScreen extends StatefulWidget {
  @override
  _ExpenseApprovalScreenState createState() => _ExpenseApprovalScreenState();
}

class _ExpenseApprovalScreenState extends State<ExpenseApprovalScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  String _selectedFilter = 'pending'; // pending, approved, rejected, all

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Requests Approval',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pending',
                child: Row(
                  children: [
                    Icon(Icons.pending_actions, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Pending'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'approved',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Approved'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'rejected',
                child: Row(
                  children: [
                    Icon(Icons.cancel, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Rejected'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.list, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('All'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getExpensesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }
          
          var expenses = snapshot.data?.docs ?? [];
          
          // Sort client-side when filtering (to avoid composite index)
          if (_selectedFilter != 'all') {
            expenses = expenses.toList()..sort((a, b) {
              final aTime = (a.data() as Map<String, dynamic>)['submitted_at'] as Timestamp?;
              final bTime = (b.data() as Map<String, dynamic>)['submitted_at'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime); // Descending order (newest first)
            });
          }
          
          if (expenses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedFilter == 'pending'
                        ? Icons.check_circle_outline
                        : Icons.inbox_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedFilter == 'pending'
                        ? 'No pending requests'
                        : 'No requests found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final expense = expenses[index].data() as Map<String, dynamic>;
              final expenseId = expenses[index].id;
              return _buildExpenseCard(expense, expenseId);
            },
          );
        },
      ),
    );
  }

  Stream<QuerySnapshot> _getExpensesStream() {
    Query query = _firestore.collection('expenses');
    
    // Only apply where filter OR orderBy to avoid requiring composite index
    if (_selectedFilter != 'all') {
      // When filtering by status, we'll sort client-side
      query = query.where('status', isEqualTo: _selectedFilter);
    } else {
      // When showing all, we can sort server-side
      query = query.orderBy('submitted_at', descending: true);
    }
    
    return query.snapshots();
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense, String expenseId) {
    final status = expense['status'] ?? 'pending';
    final totalAmount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final submittedBy = _resolveSubmittedBy(expense);
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    final title = expense['title'] ?? 'Untitled';
    
    // Status colors
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending_actions;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showExpenseDetails(expense, expenseId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusIcon, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              location,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'TZS ${_formatCurrency(totalAmount)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submitted By',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        submittedBy,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _showRejectDialog(expense, expenseId),
                        icon: const Icon(Icons.cancel),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[700],
                          side: BorderSide(color: Colors.red[700]!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _approveExpense(expense, expenseId),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showExpenseDetails(Map<String, dynamic> expense, String expenseId) {
    final items = (expense['items'] as List<dynamic>?) ?? [];
    final status = expense['status'] ?? 'pending';
    final title = expense['title'] ?? 'Untitled';
    final description = expense['description'] ?? '';
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    final totalAmount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final submittedBy = _resolveSubmittedBy(expense);
    final notes = expense['notes'] ?? '';
    final rejectionReason = expense['rejection_reason'] ?? '';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppTheme.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Request Details',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            
            // Scrollable Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // Title & Description
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Info Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          Icons.location_on,
                          'Location',
                          location,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          Icons.person,
                          'Submitted By',
                          submittedBy,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Items List
                  const Text(
                    'Items',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  ...items.map((item) {
                    final itemName = item['name'] ?? '';
                    final quantity = item['quantity'] ?? 0;
                    final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
                    final totalPrice = (item['total_price'] as num?)?.toDouble() ?? 0;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2),
                        title: Text(itemName),
                        subtitle: Text(
                          'Qty: $quantity × ${_formatCurrency(unitPrice)}',
                        ),
                        trailing: Text(
                          _formatCurrency(totalPrice),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  
                  // Total
                  const SizedBox(height: 16),
                  Card(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'TZS ${_formatCurrency(totalAmount)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Approval Details
                  if (status == 'approved') ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Builder(builder: (context) {
                        final approvedBy = expense['approved_by_name'] ?? expense['approved_by'] ?? '';
                        final approvalNote = expense['approval_note'] ?? '';
                        final transactionRef = expense['transaction_ref'] ?? '';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                              const SizedBox(width: 8),
                              Text('Approved', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700])),
                              if (approvedBy.isNotEmpty) ...[const SizedBox(width: 6), Text('by $approvedBy', style: TextStyle(fontSize: 12, color: Colors.green[600]))],
                            ]),
                            if (approvalNote.isNotEmpty) ...[const SizedBox(height: 8), Text('Note: $approvalNote', style: const TextStyle(fontSize: 13))],
                            if (transactionRef.isNotEmpty) ...[const SizedBox(height: 6),
                              Row(children: [
                                Icon(Icons.receipt_rounded, size: 14, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text('Ref: $transactionRef', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.green[800])),
                              ])
                            ],
                          ],
                        );
                      }),
                    ),
                  ],

                  // Notes
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(notes),
                    ),
                  ],
                  
                  // Rejection Reason
                  if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.red[700]),
                              const SizedBox(width: 8),
                              Text(
                                'Rejection Reason',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(rejectionReason),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 20),
                  
                  // Action Buttons
                  if (status == 'pending') ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showRejectDialog(expense, expenseId);
                            },
                            icon: const Icon(Icons.cancel),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red[700],
                              side: BorderSide(color: Colors.red[700]!),
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _approveExpense(expense, expenseId);
                            },
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _approveExpense(Map<String, dynamic> expense, String expenseId) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (expense['submitted_by'] == currentUser.email) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ You cannot approve your own request'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final noteController = TextEditingController();
    final transactionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.check_circle, color: Colors.green[700]),
          const SizedBox(width: 10),
          const Text('Approve Request'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Approval Note *',
                hintText: 'e.g., Approved, proceed immediately',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
              maxLines: 3,
              autofocus: true,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: transactionController,
              decoration: const InputDecoration(
                labelText: 'Transaction Reference (optional)',
                hintText: 'e.g., M-Pesa TXN: ABC123',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.receipt_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Please enter an approval note')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final authCtrl = Get.find<AuthController>();
                final isMD = authCtrl.isMD;
                final totalAmount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
                final location = expense['location_name'] ?? expense['location_id'] ?? '';
                final title = expense['title'] ?? '';

                if (isMD && totalAmount > 0) {
                  final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
                  final currentFloat = ((userDoc.data() as Map<String, dynamic>?)?['float_balance'] as num?)?.toDouble() ?? 0;
                  if (totalAmount > currentFloat) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Insufficient float (TZS ${_fmtAmount(currentFloat)}). Ask Owner to top up.'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                    return;
                  }
                  final newBalance = currentFloat - totalAmount;
                  final batch = _firestore.batch();
                  batch.update(_firestore.collection('expenses').doc(expenseId), {
                    'status': 'approved',
                    'approved_by': currentUser.email,
                    'approved_by_name': currentUser.displayName ?? currentUser.email,
                    'approved_at': FieldValue.serverTimestamp(),
                    'approval_note': note,
                    'transaction_ref': transactionController.text.trim(),
                    'updated_at': FieldValue.serverTimestamp(),
                  });
                  batch.update(_firestore.collection('users').doc(currentUser.uid), {
                    'float_balance': newBalance,
                    'updated_at': FieldValue.serverTimestamp(),
                  });
                  batch.set(_firestore.collection('float_transactions').doc(), {
                    'type': 'approval_deduction',
                    'amount': totalAmount,
                    'user_id': currentUser.uid,
                    'user_name': currentUser.displayName ?? currentUser.email,
                    'performed_by': currentUser.email,
                    'performed_by_name': currentUser.displayName ?? currentUser.email,
                    'request_id': expenseId,
                    'request_title': title,
                    'location': location,
                    'balance_after': newBalance,
                    'timestamp': FieldValue.serverTimestamp(),
                  });
                  await batch.commit();
                } else {
                  await _firestore.collection('expenses').doc(expenseId).update({
                    'status': 'approved',
                    'approved_by': currentUser.email,
                    'approved_by_name': currentUser.displayName ?? currentUser.email,
                    'approved_at': FieldValue.serverTimestamp(),
                    'approval_note': note,
                    'transaction_ref': transactionController.text.trim(),
                    'updated_at': FieldValue.serverTimestamp(),
                  });
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Request approved'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('❌ Error: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(Map<String, dynamic> expense, String expenseId) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    // TODO: Re-enable self-rejection restriction after testing
    // Check if trying to reject own expense
    // if (expense['submitted_by'] == currentUser.email) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //       content: Text('⚠️ You cannot reject your own expense'),
    //       backgroundColor: Colors.orange,
    //     ),
    //   );
    //   return;
    // }
    
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cancel, color: Colors.red[700]),
            const SizedBox(width: 12),
            const Text('Reject Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason *',
                border: OutlineInputBorder(),
                hintText: 'e.g., Not business related',
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Please enter a reason')),
                );
                return;
              }
              
              Navigator.pop(context);
              await _rejectExpense(expenseId, reason);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectExpense(String expenseId, String reason) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    try {
      await _firestore.collection('expenses').doc(expenseId).update({
        'status': 'rejected',
        'approved_by': currentUser.email,
        'approved_by_name': currentUser.displayName ?? currentUser.email,
        'approved_at': FieldValue.serverTimestamp(),
        'rejection_reason': reason,
        'updated_at': FieldValue.serverTimestamp(),
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Expense rejected')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error rejecting expense: $e')),
      );
    }
  }

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  String _resolveSubmittedBy(Map<String, dynamic> expense) {
    final candidates = [
      expense['submitted_by_name'],
      expense['submitted_by'],
      expense['submitted_by_email'],
      expense['created_by_name'],
      expense['created_by'],
      expense['requested_by_name'],
      expense['requested_by'],
      expense['user_name'],
      expense['user_email'],
    ];
    for (final c in candidates) {
      final v = (c ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return 'Unknown';
  }

  String _fmtAmount(double amount) => _formatCurrency(amount);
}
