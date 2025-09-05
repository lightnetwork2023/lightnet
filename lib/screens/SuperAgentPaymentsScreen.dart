import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:async';
import '../controllers/ApiService.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class SuperAgentPaymentsScreen extends StatefulWidget {
  const SuperAgentPaymentsScreen({super.key});

  @override
  State<SuperAgentPaymentsScreen> createState() => _SuperAgentPaymentsScreenState();
}

class _SuperAgentPaymentsScreenState extends State<SuperAgentPaymentsScreen> {
  final AuthController _authController = Get.find<AuthController>();
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _allPayments = [];
  List<dynamic> _filteredPayments = [];
  bool _isLoading = true;
  bool _searching = false;
  Timer? _searchTimer;
  double _totalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    
    try {
      final locations = List<String>.from(_authController.userLocations);
      if (locations.isEmpty) {
        setState(() {
          _allPayments = [];
          _filteredPayments = [];
          _totalAmount = 0.0;
          _isLoading = false;
        });
        return;
      }

      print('DEBUG: Calling fetchSuperAgentPayments with locations: $locations');
      final response = await ApiService.fetchSuperAgentPayments(locations);
      print('DEBUG: Response received: $response');
      
      setState(() {
        _allPayments = response['payments'] ?? [];
        _filteredPayments = List.from(_allPayments);
        _totalAmount = (response['total_amount'] ?? 0.0).toDouble();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to load payments: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppTheme.errorColor,
          colorText: Colors.white,
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _filterPayments(String query) {
    _searchTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _filteredPayments = List.from(_allPayments);
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);

    _searchTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final searchResults = await ApiService.searchPayments(query);
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
          Get.snackbar(
            'Search Failed',
            'Search failed: $e',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: AppTheme.errorColor,
            colorText: Colors.white,
          );
        }
      }
    });
  }

  Future<void> _copyToClipboard(String text, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      Get.snackbar(
        'Copied!',
        '$label copied to clipboard',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppTheme.successColor,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to copy $label',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppTheme.errorColor,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
      );
    }
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return 'N/A';
    final duration = Duration(seconds: seconds);
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    
    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Recent Payments',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.primaryGradient,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadPayments,
            tooltip: 'Refresh Payments',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Header Section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.payment_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Overview',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last 24 hours across your locations',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: ${_totalAmount.toStringAsFixed(0)} TZS',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ModernBadge(
                  text: '${_filteredPayments.length}',
                  backgroundColor: Colors.white.withOpacity(0.2),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ModernSearchBar(
              controller: _searchController,
              hintText: 'Search by phone number (searches all payments)...',
              onChanged: _filterPayments,
            ),
          ),

          const SizedBox(height: 16),

          // Results Count
          if (_searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    _searching 
                        ? 'Searching all payments...'
                        : 'Found ${_filteredPayments.length} payments matching "${_searchController.text}"',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Content Section
          Expanded(
            child: _isLoading
                ? const ModernLoading(
                    message: 'Loading payments...',
                  )
                : _filteredPayments.isEmpty
                        ? EmptyState(
                            icon: Icons.payment_outlined,
                            title: _searchController.text.isNotEmpty 
                                ? 'No Payments Found' 
                                : 'No Recent Payments',
                            subtitle: _searchController.text.isNotEmpty 
                                ? 'No payments found matching "${_searchController.text}".'
                                : 'No payments have been made in the last 24 hours.',
                          )
                        : RefreshIndicator(
                        onRefresh: _loadPayments,
                        color: AppTheme.primaryColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _filteredPayments.length,
                          itemBuilder: (context, index) {
                            final payment = _filteredPayments[index];
                            return _buildPaymentCard(payment);
                          },
                        ),
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
        formattedTime = '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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
                const SizedBox(height: 8),
                // Timestamp Row
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Time:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formattedTime,
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
        ],
      ),
    );
  }
}
