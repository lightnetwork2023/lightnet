// screens/payments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/ApiService.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class PaymentsScreen extends StatefulWidget {
  @override
  _PaymentsScreenState createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final AuthController _authController = Get.find<AuthController>();
  List<dynamic> _payments = [];
  List<dynamic> _filteredPayments = [];
  bool _loading = false;
  bool _searching = false;
  String _searchText = '';

  void _fetchPayments() async {
    setState(() => _loading = true);
    final payments = await ApiService.fetchRecentPayments();
    if (payments.isNotEmpty) {
      print('DEBUG: First payment object: ' + payments.first.toString());
    }
    setState(() {
      _payments = payments.reversed.toList(); // Newest at the top
      _filteredPayments = _payments; // Show all recent payments initially
      _loading = false;
    });
  }

  void _performSearch(String searchText) async {
    if (searchText.isEmpty) {
      // If search is cleared, show recent payments
      setState(() {
        _filteredPayments = _payments;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    
    try {
      final searchResults = await ApiService.searchPayments(searchText);
      setState(() {
        _filteredPayments = searchResults; // Backend already orders by timestamp DESC
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _filteredPayments = [];
        _searching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          '💳 Recent Payments (24h)',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryColor, AppTheme.primaryVariant],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _fetchPayments,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          ModernSearchBar(
            hintText: 'Search by phone number (searches all payments)...',
            onChanged: (value) {
              setState(() {
                _searchText = value;
              });
              _performSearch(value);
            },
          ),
          
          // Results Count
          if (!_loading && !_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (!_authController.isTechnician ||
                      _searchText.isNotEmpty)
                    Expanded(
                      child: Text(
                        _authController.isTechnician
                            ? 'Found ${_filteredPayments.length} payments matching "$_searchText"'
                            : (_searchText.isEmpty
                                ? 'Showing ${_filteredPayments.length} recent payments (24h)'
                                : 'Found ${_filteredPayments.length} payments matching "$_searchText"'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          
          const SizedBox(height: 8),
          
          // Content
          Expanded(
            child: _loading
                ? const ModernLoading(message: 'Loading recent payments...')
                : _searching
                    ? const ModernLoading(message: 'Searching all payments...')
                    : _filteredPayments.isEmpty
                        ? EmptyState(
                            icon: Icons.payment_outlined,
                            title: _searchText.isEmpty 
                                ? 'No Recent Payments' 
                                : 'No Payments Found',
                            subtitle: _searchText.isEmpty
                                ? 'No payments have been made in the last 24 hours.'
                                : 'No payments found matching "$_searchText".',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: _filteredPayments.length,
                            itemBuilder: (context, index) {
                              final payment = _filteredPayments[index];
                              return _buildPaymentCard(payment);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final username = payment['username']?.toString() ?? 'Unknown User';
    final phone = payment['phone']?.toString() ?? 'N/A';
    final location = payment['location']?.toString() ?? 'Unknown Location';
    final amount = payment['amount']?.toString() ?? 'N/A';
    final duration = payment['duration']?.toString() ?? 'N/A';
    final timestamp = payment['timestamp']?.toString() ?? '';
    
    // Parse and format timestamp
    String formattedTime = 'N/A';
    if (timestamp.isNotEmpty) {
      try {
        final dateTime = DateTime.parse(timestamp.split('.')[0]);
        formattedTime = DateFormat('MMM dd, HH:mm').format(dateTime);
      } catch (e) {
        formattedTime = timestamp.split('.')[0];
      }
    }
    
    return ModernCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.payment_rounded,
                  color: AppTheme.successColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            username,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        // Copy Button
                        IconButton(
                          onPressed: () => _copyToClipboard(username, 'Username'),
                          icon: const Icon(
                            Icons.copy_rounded,
                            size: 18,
                          ),
                          style: IconButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                            padding: const EdgeInsets.all(8),
                            minimumSize: const Size(32, 32),
                          ),
                          tooltip: 'Copy Username',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Payment Badge
              ModernBadge(
                text: 'PAID',
                backgroundColor: AppTheme.successColor,
                textColor: Colors.white,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Details Grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Phone Row
                Row(
                  children: [
                    Icon(
                      Icons.phone_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Phone:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        phone,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Amount Row
                Row(
                  children: [
                    Icon(
                      Icons.attach_money_rounded,
                      size: 16,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Amount:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        amount,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Duration Row
                Row(
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Duration:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        duration,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Timestamp
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: AppTheme.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                formattedTime,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('$label copied to clipboard'),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('Failed to copy $label'),
              ],
            ),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
