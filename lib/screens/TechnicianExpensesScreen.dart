import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'ExpenseCreationScreen.dart';

class TechnicianExpensesScreen extends StatefulWidget {
  const TechnicianExpensesScreen({Key? key}) : super(key: key);

  @override
  _TechnicianExpensesScreenState createState() => _TechnicianExpensesScreenState();
}

class _TechnicianExpensesScreenState extends State<TechnicianExpensesScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _myExpenses = [];
  
  // Filter state
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedStatus = 'all'; // all, pending, approved

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _loadMyExpenses();
  }

  void _initializeDates() {
    // Set default to current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1); // First day of month
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59); // Last day of month
  }

  Future<void> _loadMyExpenses() async {
    setState(() => _isLoading = true);
    
    try {
      final currentUserEmail = _auth.currentUser?.email;
      print('DEBUG: Loading expenses for user: $currentUserEmail');
      print('DEBUG: Date range: $_startDate to $_endDate');
      
      if (currentUserEmail == null) {
        print('DEBUG: No user email found');
        setState(() => _isLoading = false);
        return;
      }

      // Query expenses with date filter
      Query query = _firestore
          .collection('expenses')
          .where('submitted_by', isEqualTo: currentUserEmail);
      
      // Add date range filter
      if (_startDate != null) {
        query = query.where('submitted_at', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
      }
      if (_endDate != null) {
        query = query.where('submitted_at', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!));
      }
      
      final snapshot = await query.get();
      
      print('DEBUG: Found ${snapshot.docs.length} expenses for $currentUserEmail');

      List<Map<String, dynamic>> expenses = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        
        final status = data['status'] ?? 'pending';
        
        // Apply status filter
        if (_selectedStatus != 'all' && status != _selectedStatus) {
          continue;
        }
        
        expenses.add(data);
      }

      // Sort in memory by submitted_at (descending - newest first)
      expenses.sort((a, b) {
        final aTime = a['submitted_at'] as Timestamp?;
        final bTime = b['submitted_at'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending
      });

      setState(() {
        _myExpenses = expenses;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading expenses: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading expenses: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('My Expenses'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.primaryGradient,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMyExpenses,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ExpenseCreationScreen(),
            ),
          ).then((_) => _loadMyExpenses());
        },
        icon: const Icon(Icons.add),
        label: const Text('New Expense'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMyExpenses,
              child: Column(
                children: [
                  // Expenses List
                  Expanded(
                    child: _myExpenses.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No expenses yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + to create your first expense',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _myExpenses.length,
                            itemBuilder: (context, index) {
                              return _buildExpenseCard(_myExpenses[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Expenses'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Filter
            const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _selectedStatus,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedStatus = value ?? 'all';
                });
                Navigator.pop(context);
                _loadMyExpenses();
              },
            ),
            const SizedBox(height: 16),
            
            // Date Range
            const Text('Date Range:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _startDate != null 
                        ? DateFormat('MMM dd').format(_startDate!) 
                        : 'Start',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _endDate != null 
                        ? DateFormat('MMM dd').format(_endDate!) 
                        : 'End',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Quick filters
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('This Month', style: TextStyle(fontSize: 12)),
                  selected: false,
                  onSelected: (selected) {
                    final now = DateTime.now();
                    setState(() {
                      _startDate = DateTime(now.year, now.month, 1);
                      _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
                    });
                    Navigator.pop(context);
                    _loadMyExpenses();
                  },
                ),
                FilterChip(
                  label: const Text('Last Month', style: TextStyle(fontSize: 12)),
                  selected: false,
                  onSelected: (selected) {
                    final now = DateTime.now();
                    setState(() {
                      _startDate = DateTime(now.year, now.month - 1, 1);
                      _endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
                    });
                    Navigator.pop(context);
                    _loadMyExpenses();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _initializeDates(); // Reset to default (current month)
                _selectedStatus = 'all';
              });
              Navigator.pop(context);
              _loadMyExpenses();
            },
            child: const Text('Reset'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadMyExpenses();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense) {
    final status = expense['status'] ?? 'pending';
    final amount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final title = expense['title'] ?? 'Untitled';
    final submittedAt = expense['submitted_at'] as Timestamp?;
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    
    Color statusColor;
    IconData statusIcon;
    String statusText;
    bool canEdit = status == 'pending';
    
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        statusText = 'Pending';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showExpenseDetails(expense),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TZS ${NumberFormat('#,###').format(amount)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  if (submittedAt != null)
                    Text(
                      DateFormat('MMM dd, yyyy').format(submittedAt.toDate()),
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
      ),
    );
  }

  void _showExpenseDetails(Map<String, dynamic> expense) {
    final expenseId = expense['id'] ?? expense['expense_id'];
    final status = expense['status'] ?? 'pending';
    final amount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final title = expense['title'] ?? 'Untitled';
    final description = expense['description'] ?? '';
    final submittedAt = expense['submitted_at'] as Timestamp?;
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    final items = expense['items'] as List<dynamic>? ?? [];
    final attachments = expense['attachments'] as List<dynamic>? ?? [];
    
    final canEdit = status == 'pending';
    
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        statusText = 'Pending Approval';
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusColor.withOpacity(0.8), statusColor],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(statusIcon, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Info Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[50],
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 18, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  location,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 18, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  submittedAt != null
                                      ? DateFormat('MMM dd, yyyy - HH:mm').format(submittedAt.toDate())
                                      : 'Unknown',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    if (description.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Description',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const Divider(height: 1),
                    
                    // Items
                    if (items.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'ITEMS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      ...items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final itemData = item as Map<String, dynamic>;
                        final itemName = itemData['name'] ?? 'Unnamed Item';
                        final itemAmount = (itemData['total_price'] as num?)?.toDouble() ?? 0;
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  itemName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                'TZS ${NumberFormat('#,###').format(itemAmount)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                    
                    if (attachments.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.attach_file, color: Colors.blue[700], size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${attachments.length} attachment${attachments.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              // Total Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'Amount',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'TZS ${NumberFormat('#,###').format(amount)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Edit Button (only for pending)
              if (canEdit)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ExpenseCreationScreen(
                              expenseId: expenseId,
                              existingExpense: expense,
                            ),
                          ),
                        ).then((_) => _loadMyExpenses());
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('EDIT EXPENSE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
