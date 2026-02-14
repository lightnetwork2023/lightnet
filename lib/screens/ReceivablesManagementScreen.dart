import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/DebtService.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class ReceivablesManagementScreen extends StatefulWidget {
  const ReceivablesManagementScreen({super.key});

  @override
  State<ReceivablesManagementScreen> createState() => _ReceivablesManagementScreenState();
}

class _ReceivablesManagementScreenState extends State<ReceivablesManagementScreen> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Receivables (They Owe Us)'),
        actions: [
          PopupMenuButton<String>(
            initialValue: _filterStatus,
            onSelected: (value) => setState(() => _filterStatus = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Debts')),
              const PopupMenuItem(value: 'unpaid', child: Text('Unpaid')),
              const PopupMenuItem(value: 'partial', child: Text('Partial Payment')),
              const PopupMenuItem(value: 'paid', child: Text('Paid')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryCard(),
          Expanded(child: _buildDebtsList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDebtDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Debt'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  Widget _buildSummaryCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: DebtService.receivables.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        double totalOwed = 0;
        double totalReceived = 0;
        double balance = 0;

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          totalOwed += (data['totalAmount'] ?? 0.0).toDouble();
          totalReceived += (data['amountPaid'] ?? 0.0).toDouble();
          balance += (data['balance'] ?? 0.0).toDouble();
        }

        return ModernCard(
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryItem('Total Owed to Us', totalOwed, AppTheme.successColor),
                  ),
                  Expanded(
                    child: _buildSummaryItem('Received', totalReceived, AppTheme.primaryColor),
                  ),
                  Expanded(
                    child: _buildSummaryItem('Outstanding', balance, AppTheme.warningColor),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(
          NumberFormat.currency(symbol: 'TZS ', decimalDigits: 0).format(amount),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildDebtsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: DebtService.receivables.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var debts = snapshot.data!.docs.where((doc) {
          if (_filterStatus == 'all') return true;
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == _filterStatus;
        }).toList();

        if (debts.isEmpty) {
          return const Center(child: Text('No receivables found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: debts.length,
          itemBuilder: (context, index) {
            final doc = debts[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildDebtCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildDebtCard(String debtId, Map<String, dynamic> data) {
    final debtorName = data['debtorName'] ?? 'Unknown';
    final phone = data['phone'] ?? '';
    final totalAmount = (data['totalAmount'] ?? 0.0).toDouble();
    final amountPaid = (data['amountPaid'] ?? 0.0).toDouble();
    final balance = (data['balance'] ?? 0.0).toDouble();
    final description = data['description'] ?? '';
    final status = data['status'] ?? 'unpaid';
    final dueDate = data['dueDate'];
    final category = data['category'] ?? 'General';

    Color statusColor;
    switch (status) {
      case 'paid':
        statusColor = AppTheme.successColor;
        break;
      case 'partial':
        statusColor = AppTheme.warningColor;
        break;
      default:
        statusColor = AppTheme.errorColor;
    }

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debtorName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (phone.isNotEmpty)
                      Text(phone, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text(category, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildAmountDetail('Total', totalAmount, AppTheme.textPrimary),
              ),
              Expanded(
                child: _buildAmountDetail('Received', amountPaid, AppTheme.successColor),
              ),
              Expanded(
                child: _buildAmountDetail('Balance', balance, AppTheme.warningColor),
              ),
            ],
          ),
          if (dueDate != null) ...[
            const SizedBox(height: 8),
            Text(
              'Due: $dueDate',
              style: const TextStyle(fontSize: 12, color: AppTheme.warningColor),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'receive':
                      _showRecordPaymentDialog(debtId, debtorName, balance);
                      break;
                    case 'history':
                      _showPaymentHistoryDialog(debtId, debtorName);
                      break;
                    case 'edit':
                      _showEditDialog(debtId, data);
                      break;
                    case 'delete':
                      _confirmDelete(debtId, debtorName);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (balance > 0)
                    const PopupMenuItem(
                      value: 'receive',
                      child: Row(
                        children: [
                          Icon(Icons.payment, size: 20),
                          SizedBox(width: 12),
                          Text('Record Payment'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 20),
                        SizedBox(width: 12),
                        Text('Payment History'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 12),
                        Text('Edit Debt'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: AppTheme.errorColor),
                        SizedBox(width: 12),
                        Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountDetail(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        Text(
          NumberFormat.currency(symbol: '', decimalDigits: 0).format(amount),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  void _showAddDebtDialog() {
    final debtorCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'General';
    DateTime? selectedDueDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Receivable (They Owe Us)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: debtorCtrl,
                  decoration: const InputDecoration(labelText: 'Debtor Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total Amount (TZS) *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['General', 'Customer', 'Staff Loan', 'Agent', 'Service', 'Other']
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (val) => setState(() => category = val!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDueDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) {
                      setState(() => selectedDueDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Due Date (Optional)',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      selectedDueDate != null
                          ? DateFormat('yyyy-MM-dd').format(selectedDueDate!)
                          : 'Select date',
                      style: TextStyle(
                        color: selectedDueDate != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (debtorCtrl.text.isEmpty || amountCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill required fields')),
                  );
                  return;
                }

                try {
                  await DebtService.addReceivable(
                    debtorName: debtorCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    totalAmount: double.parse(amountCtrl.text.trim()),
                    description: descCtrl.text.trim(),
                    dueDate: selectedDueDate != null ? DateFormat('yyyy-MM-dd').format(selectedDueDate!) : null,
                    category: category,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Receivable added successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecordPaymentDialog(String debtId, String debtorName, double balance) {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String paymentMethod = 'Cash';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Record Payment from $debtorName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Balance: ${NumberFormat.currency(symbol: 'TZS ', decimalDigits: 0).format(balance)}'),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Payment Amount *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: ['Cash', 'Bank Transfer', 'Mobile Money', 'Cheque', 'Other']
                    .map((method) => DropdownMenuItem(value: method, child: Text(method)))
                    .toList(),
                onChanged: (val) => setState(() => paymentMethod = val!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (Optional)'),
                maxLines: 2,
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
                if (amountCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter payment amount')),
                  );
                  return;
                }

                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid amount')),
                  );
                  return;
                }

                try {
                  await DebtService.recordReceivablePayment(
                    debtId: debtId,
                    amount: amount,
                    paymentMethod: paymentMethod,
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment recorded successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentHistoryDialog(String debtId, String debtorName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Payment History - $debtorName'),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: DebtService.getPaymentHistory(debtId, false),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final payments = snapshot.data!.docs;
              if (payments.isEmpty) {
                return const Center(child: Text('No payments yet'));
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: payments.length,
                itemBuilder: (context, index) {
                  final payment = payments[index].data() as Map<String, dynamic>;
                  final amount = (payment['amount'] ?? 0.0).toDouble();
                  final method = payment['paymentMethod'] ?? 'Unknown';
                  final notes = payment['notes'] ?? '';
                  final timestamp = payment['timestamp'] as Timestamp?;

                  return ListTile(
                    leading: const Icon(Icons.payment, color: AppTheme.successColor),
                    title: Text(NumberFormat.currency(symbol: 'TZS ', decimalDigits: 0).format(amount)),
                    subtitle: Text('$method${notes.isNotEmpty ? ' - $notes' : ''}'),
                    trailing: timestamp != null
                        ? Text(
                            DateFormat('dd/MM/yyyy').format(timestamp.toDate()),
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(String debtId, Map<String, dynamic> data) {
    final debtorCtrl = TextEditingController(text: data['debtorName']);
    final phoneCtrl = TextEditingController(text: data['phone'] ?? '');
    final amountCtrl = TextEditingController(text: data['totalAmount'].toString());
    final descCtrl = TextEditingController(text: data['description']);
    String category = data['category'] ?? 'General';
    DateTime? selectedDueDate;
    
    if (data['dueDate'] != null && data['dueDate'].toString().isNotEmpty) {
      try {
        selectedDueDate = DateTime.parse(data['dueDate']);
      } catch (e) {
        selectedDueDate = null;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Receivable'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: debtorCtrl,
                  decoration: const InputDecoration(labelText: 'Debtor Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total Amount (TZS)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['General', 'Customer', 'Staff Loan', 'Agent', 'Service', 'Other']
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                      .toList(),
                  onChanged: (val) => setState(() => category = val!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDueDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) {
                      setState(() => selectedDueDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Due Date (Optional)',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      selectedDueDate != null
                          ? DateFormat('yyyy-MM-dd').format(selectedDueDate!)
                          : 'Select date',
                      style: TextStyle(
                        color: selectedDueDate != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await DebtService.updateReceivable(
                    debtId: debtId,
                    debtorName: debtorCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    totalAmount: double.tryParse(amountCtrl.text.trim()),
                    description: descCtrl.text.trim(),
                    dueDate: selectedDueDate != null ? DateFormat('yyyy-MM-dd').format(selectedDueDate!) : null,
                    category: category,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Receivable updated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String debtId, String debtorName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Receivable'),
        content: Text('Are you sure you want to delete receivable from $debtorName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await DebtService.deleteReceivable(debtId);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Receivable deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
