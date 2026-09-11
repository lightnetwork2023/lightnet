import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'ExpenseCreationScreen.dart';

enum TimePeriod {
  today,
  last24Hours,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

class ExpenseAnalyticsScreen extends StatefulWidget {
  const ExpenseAnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<ExpenseAnalyticsScreen> createState() => _ExpenseAnalyticsScreenState();
}

class _ExpenseAnalyticsScreenState extends State<ExpenseAnalyticsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool _isLoading = true;
  Map<String, Map<String, dynamic>> _locationExpenses = {};
  double _totalExpenses = 0;
  int _totalCount = 0;
  
  // Filtering
  TimePeriod _selectedPeriod = TimePeriod.thisMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _selectedStatus = 'all'; // all, pending, approved (technicians see their own pending, bosses see pending in Approvals tab, rejected are deleted)
  
  // View mode
  String _viewMode = 'analytics'; // analytics, approvals
  bool _isBoss = false;
  bool _roleChecked = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadExpenseAnalytics();
  }

  Future<void> _checkUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>?;
          final userRole = userData?['role'] as String?;
          setState(() {
            _isBoss = userRole?.toLowerCase().trim() == 'boss';
            _roleChecked = true;
          });
        } else {
          setState(() => _roleChecked = true);
        }
      } else {
        setState(() => _roleChecked = true);
      }
    } catch (e) {
      setState(() => _roleChecked = true);
    }
  }

  Future<void> _loadExpenseAnalytics() async {
    setState(() => _isLoading = true);
    
    try {
      final dates = _getDateRange();
      final startDate = dates['start']!;
      final endDate = dates['end']!;
      
      // Query expenses
      Query query = _firestore.collection('expenses')
          .where('submitted_at', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('submitted_at', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .limit(500);
      
      final snapshot = await query.get();
      
      Map<String, Map<String, dynamic>> locationData = {};
      double totalAmount = 0;
      int totalDocs = 0;
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'pending';
        
        // Skip pending expenses - they should only appear in Approvals tab
        if (status == 'pending') {
          continue;
        }
        
        // Apply status filter (only approved now since pending is excluded)
        if (_selectedStatus != 'all' && status != _selectedStatus) {
          continue;
        }
        
        final locationId = data['location_id'] ?? data['location_name'] ?? 'Unknown';
        final amount = (data['total_amount'] as num?)?.toDouble() ?? 0;
        
        if (!locationData.containsKey(locationId)) {
          locationData[locationId] = {
            'location': locationId,
            'total': 0.0,
            'count': 0,
            'pending': 0,
            'approved': 0,
            'rejected': 0,
            'expenses': <Map<String, dynamic>>[],
          };
        }
        
        locationData[locationId]!['total'] += amount;
        locationData[locationId]!['count']++;
        locationData[locationId]![status]++;
        locationData[locationId]!['expenses'].add({
          'id': doc.id,
          ...data,
        });
        
        totalAmount += amount;
        totalDocs++;
      }
      
      setState(() {
        _locationExpenses = locationData;
        _totalExpenses = totalAmount;
        _totalCount = totalDocs;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading expense analytics: $e');
      setState(() => _isLoading = false);
    }
  }

  Map<String, DateTime> _getDateRange() {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    
    switch (_selectedPeriod) {
      case TimePeriod.today:
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case TimePeriod.last24Hours:
        start = now.subtract(const Duration(hours: 24));
        end = now;
        break;
      case TimePeriod.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case TimePeriod.lastMonth:
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0, 23, 59, 59);
        break;
      case TimePeriod.thisYear:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case TimePeriod.custom:
        start = _customStartDate ?? DateTime(now.year, now.month, 1);
        end = _customEndDate ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
    }
    
    return {'start': start, 'end': end};
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Time Period',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildFilterOption('Today', TimePeriod.today, Icons.today),
            _buildFilterOption('Last 24 Hours', TimePeriod.last24Hours, Icons.access_time),
            _buildFilterOption('This Month', TimePeriod.thisMonth, Icons.calendar_today),
            _buildFilterOption('Last Month', TimePeriod.lastMonth, Icons.calendar_month),
            _buildFilterOption('This Year', TimePeriod.thisYear, Icons.date_range),
            _buildFilterOption(
              'Custom Period',
              TimePeriod.custom,
              Icons.date_range_outlined,
              onTap: () async {
                Navigator.pop(context);
                await _selectCustomDateRange();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(
    String title,
    TimePeriod period,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedPeriod == period;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppTheme.primaryColor : Colors.grey,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppTheme.primaryColor : Colors.black,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppTheme.primaryColor)
          : null,
      onTap: onTap ??
          () {
            setState(() {
              _selectedPeriod = period;
            });
            Navigator.pop(context);
            _loadExpenseAnalytics();
          },
    );
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedPeriod = TimePeriod.custom;
      });
      _loadExpenseAnalytics();
    }
  }

  void _showLocationExpenses(String location, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, color: AppTheme.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${data['count']} expense${data['count'] != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 32),
              
              Expanded(
                child: data['expenses'].isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No expenses found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: data['expenses'].length,
                        itemBuilder: (context, index) {
                          final expense = data['expenses'][index];
                          return _buildExpenseListItem(expense);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseListItem(Map<String, dynamic> expense) {
    final status = expense['status'] ?? 'pending';
    final amount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final title = expense['title'] ?? 'Untitled';
    final submittedAt = expense['submitted_at'] as Timestamp?;
    final submittedBy = expense['submitted_by_name'] ?? expense['submitted_by'] ?? 'Unknown';
    
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
        statusIcon = Icons.pending;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => _showExpenseDetails(expense),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              submittedBy,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            Text(
              submittedAt != null
                  ? DateFormat('MMM dd, yyyy').format(submittedAt.toDate())
                  : 'Unknown date',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'TZS ${_formatCurrency(amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showExpenseDetails(Map<String, dynamic> expense) {
    final status = expense['status'] ?? 'pending';
    final amount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final title = expense['title'] ?? 'Untitled';
    final description = expense['description'] ?? '';
    final submittedAt = expense['submitted_at'] as Timestamp?;
    final submittedBy = expense['submitted_by_name'] ?? expense['submitted_by'] ?? 'Unknown';
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    final items = expense['items'] as List<dynamic>? ?? [];
    final attachments = expense['attachments'] as List<dynamic>? ?? [];
    
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
        statusText = 'Pending';
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
          child: Column(
            children: [
              // Header - Cart Style
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryGradient,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.receipt_long,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
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
                              Row(
                                children: [
                                  Icon(statusIcon, color: Colors.white, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
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
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_cart, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${items.length} item${items.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content - Cart Items
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
                              Icon(Icons.person, size: 18, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  submittedBy,
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
                              'Note',
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
                    
                    // Cart Items
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
                              // Item Number Badge
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Item Name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Item ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Item Amount
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'TZS ${NumberFormat('#,###').format(itemAmount)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
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
              
              // Total Section - Cart Style
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
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Expense Analytics'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.primaryGradient,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadExpenseAnalytics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: _viewMode == 'analytics'
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExpenseCreationScreen(),
                  ),
                ).then((_) => _loadExpenseAnalytics());
              },
              icon: const Icon(Icons.add),
              label: const Text('New Expense'),
              backgroundColor: AppTheme.primaryColor,
            )
          : null,
      body: Column(
        children: [
          // View Mode Selector (for boss)
          if (_roleChecked) _buildViewModeSelector(),
          
          // Main Content
          Expanded(
            key: ValueKey(_viewMode),
            child: _viewMode == 'approvals'
                ? _buildApprovalsView()
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadExpenseAnalytics,
                        child: _locationExpenses.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt_long_outlined,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No expenses found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
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
                            : ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    // Summary Header
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        gradient: AppGradients.primaryGradient,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primaryColor.withOpacity(0.3),
                                            blurRadius: 12,
                                            offset: const Offset(0, 6),
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            _getPeriodLabel(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'TZS ${NumberFormat('#,###').format(_totalExpenses)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$_totalCount expense${_totalCount != 1 ? 's' : ''}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.9),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    const SizedBox(height: 24),
                                    
                                    // Location Cards
                                    ..._locationExpenses.entries.map((entry) {
                                      final location = entry.key;
                                      final data = entry.value;
                                      return _buildLocationCard(location, data);
                                    }).toList(),
                                  ],
                                ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeSelector() {
    if (!_roleChecked || !_isBoss) return const SizedBox.shrink();
    
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildModeChip(
                  'Analytics',
                  Icons.analytics_outlined,
                  'analytics',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModeChip(
                  'Approvals',
                  Icons.approval_outlined,
                  'approvals',
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildModeChip(String label, IconData icon, String mode) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: isSelected ? AppGradients.primaryGradient : null,
          color: isSelected ? null : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalsView() {
    // Use a single query that doesn't require composite index
    final query = _firestore
        .collection('expenses')
        .where('status', isEqualTo: 'pending')
        .limit(100);
    
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Handle errors
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading approvals',
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.green[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'No Pending Approvals',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'All expenses are approved!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        // Sort by submitted_at descending (client-side)
        final pendingExpenses = snapshot.data!.docs.toList();
        pendingExpenses.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['submitted_at'] as Timestamp?;
          final bTime = bData['submitted_at'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });

        return ListView.builder(
          key: const ValueKey('approvals_list'),
          padding: const EdgeInsets.all(16),
          itemCount: pendingExpenses.length,
          itemBuilder: (context, index) {
            final doc = pendingExpenses[index];
            final expense = doc.data() as Map<String, dynamic>;
            return _buildApprovalCard(expense, doc.id);
          },
        );
      },
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> expense, String expenseId) {
    final title = expense['title'] ?? 'Untitled';
    final amount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final submittedBy = expense['submitted_by_name'] ?? expense['submitted_by'] ?? 'Unknown';
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    final submittedAt = expense['submitted_at'] as Timestamp?;
    final items = expense['items'] as List<dynamic>? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withOpacity(0.3), width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showExpenseApprovalDialog(expense, expenseId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange[300]!, Colors.orange[500]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.pending_actions,
                      color: Colors.white,
                      size: 24,
                    ),
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
                            Icon(Icons.person, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              submittedBy,
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
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: const Text(
                      'PENDING',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TZS ${NumberFormat('#,###').format(amount)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${items.length} item${items.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              location,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (submittedAt != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM dd, yyyy • hh:mm a').format(submittedAt.toDate()),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
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

  void _showExpenseApprovalDialog(Map<String, dynamic> expense, String expenseId) {
    final status = expense['status'] ?? 'pending';
    final amount = (expense['total_amount'] as num?)?.toDouble() ?? 0;
    final title = expense['title'] ?? 'Untitled';
    final description = expense['description'] ?? '';
    final submittedAt = expense['submitted_at'] as Timestamp?;
    final submittedBy = expense['submitted_by_name'] ?? expense['submitted_by'] ?? 'Unknown';
    final location = expense['location_name'] ?? expense['location_id'] ?? 'Unknown';
    final items = expense['items'] as List<dynamic>? ?? [];
    final attachments = expense['attachments'] as List<dynamic>? ?? [];

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
              // Header - Pending Approval
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange[300]!, Colors.orange[500]!],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.pending_actions,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
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
                              const Text(
                                'PENDING APPROVAL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  letterSpacing: 1,
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
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_cart, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${items.length} item${items.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content - Cart Items
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
                              Icon(Icons.person, size: 18, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  submittedBy,
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
                              'Note',
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
                    
                    // Cart Items
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
                              // Item Number Badge
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Item Name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Item ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Item Amount
                              Text(
                                'TZS ${NumberFormat('#,###').format(itemAmount)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
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
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Action Buttons
              Container(
                padding: const EdgeInsets.all(16),
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
                child: Column(
                  children: [
                    // Edit Button (Full Width)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _editExpense(expense, expenseId),
                        icon: const Icon(Icons.edit),
                        label: const Text('EDIT EXPENSE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Reject and Approve Buttons
                    Row(
                      children: [
                        // Reject Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _rejectExpense(expenseId),
                            icon: const Icon(Icons.cancel),
                            label: const Text('REJECT'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Approve Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _approveExpense(expense, expenseId),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('APPROVE'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveExpense(Map<String, dynamic> expense, String expenseId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    // Check if trying to approve own expense (production mode)
    if (expense['submitted_by'] == currentUser.email) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ You cannot approve your own expense'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      await _firestore.collection('expenses').doc(expenseId).update({
        'status': 'approved',
        'approved_at': FieldValue.serverTimestamp(),
        'approved_by': currentUser.email,
        'approved_by_name': currentUser.displayName ?? currentUser.email,
      });
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Expense approved successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving expense: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectExpense(String expenseId) async {
    try {
      // Delete the expense completely instead of marking as rejected
      await _firestore.collection('expenses').doc(expenseId).delete();
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense rejected and deleted'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting expense: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editExpense(Map<String, dynamic> expense, String expenseId) {
    Navigator.pop(context); // Close the approval dialog
    
    // Navigate to ExpenseCreationScreen with existing expense data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpenseCreationScreen(
          expenseId: expenseId,
          existingExpense: expense,
        ),
      ),
    ).then((_) {
      // Refresh the approvals list after editing
      setState(() {});
    });
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case TimePeriod.today:
        return 'Today\'s Expenses';
      case TimePeriod.last24Hours:
        return 'Last 24 Hours';
      case TimePeriod.thisMonth:
        return 'This Month\'s Expenses';
      case TimePeriod.lastMonth:
        return 'Last Month\'s Expenses';
      case TimePeriod.thisYear:
        return 'This Year\'s Expenses';
      case TimePeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}';
        }
        return 'Custom Period';
    }
  }

  Widget _buildLocationCard(String location, Map<String, dynamic> data) {
    final total = data['total'] as double;
    final count = data['count'] as int;
    final pending = data['pending'] as int;
    final approved = data['approved'] as int;
    final rejected = data['rejected'] as int;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 6,
      shadowColor: AppTheme.primaryColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showLocationExpenses(location, data),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.receipt, size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '$count expense${count != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 18),
              
              // Amount
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withOpacity(0.1),
                      AppTheme.primaryColor.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TZS ${NumberFormat('#,###').format(total)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    if (pending > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.pending, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '$pending',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 14),
              
              // Status badges
              Row(
                children: [
                  if (approved > 0)
                    _buildStatusBadge('$approved Approved', Colors.green, Icons.check_circle),
                  if (approved > 0 && rejected > 0) const SizedBox(width: 8),
                  if (rejected > 0)
                    _buildStatusBadge('$rejected Rejected', Colors.red, Icons.cancel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color, [IconData? icon]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
