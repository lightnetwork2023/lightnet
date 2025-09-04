import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'dart:async';

class VouchersScreen extends StatefulWidget {
  final bool showOnlyUsed;
  const VouchersScreen({super.key, this.showOnlyUsed = false});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  List<dynamic> _vouchers = [];
  List<dynamic> _filteredVouchers = [];
  bool _loading = true;
  bool _searching = false;
  int _recentLoginCount = 0;
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _filterVouchers(String query) {
    // Cancel any existing timer
    _searchTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _filteredVouchers = List.from(_vouchers);
        _searching = false;
      });
      return;
    }
    
    // Set searching state immediately
    setState(() {
      _searching = true;
    });
    
    // Debounce the search to avoid too many API calls
    _searchTimer = Timer(const Duration(milliseconds: 500), () {
      _searchUserByUsername(query);
    });
  }
  
  Future<void> _searchUserByUsername(String username) async {
    try {
      final result = await ApiService.getUserInfo(username);
      
      setState(() {
        _searching = false;
        if (result.containsKey('voucher_info') && result['voucher_info'] != null) {
          // Found user, display only this user
          _filteredVouchers = [result['voucher_info']];
        } else {
          // User not found, show empty results
          _filteredVouchers = [];
        }
      });
    } catch (e) {
      setState(() {
        _searching = false;
        // On error, fall back to local filtering
        _filteredVouchers = _vouchers.where((voucher) {
          final voucherUsername = voucher['username']?.toString().toLowerCase() ?? '';
          return voucherUsername.contains(username.toLowerCase());
        }).toList();
      });
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Search failed, showing local results: ${e.toString().replaceFirst('Exception: ', '')}'),
                ),
              ],
            ),
            backgroundColor: AppTheme.warningColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  DateTime? _parseDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) {
      return null;
    }
    
    // Try different date formats commonly used
    final formats = [
      _httpDateFormat, // E, dd MMM yyyy HH:mm:ss 'GMT'
      _mysqlDateFormat, // yyyy-MM-dd HH:mm:ss
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS'), // with milliseconds
      DateFormat('yyyy-MM-ddTHH:mm:ss'), // ISO without Z
      DateFormat('yyyy-MM-ddTHH:mm:ss.SSS'), // ISO with milliseconds
      DateFormat('yyyy-MM-ddTHH:mm:ssZ'), // ISO with timezone
      DateFormat('yyyy-MM-ddTHH:mm:ss.SSSZ'), // ISO with milliseconds and timezone
    ];
    
    for (var format in formats) {
      try {
        return format.parse(dateTimeStr, true);
      } catch (e) {
        // Continue to next format
      }
    }
    
    // Try DateTime.parse as fallback
    try {
      return DateTime.parse(dateTimeStr);
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadVouchers() async {
    setState(() => _loading = true);
    try {
      final vouchers = await ApiService.fetchRecentVouchers();
      // Sort by first_login_time descending (newest first)
      vouchers.sort((a, b) {
        final aTime = _parseDateTime(a['first_login_time']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = _parseDateTime(b['first_login_time']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      setState(() {
        _vouchers = vouchers;
        // Filter vouchers if showOnlyUsed is true
        _filteredVouchers = widget.showOnlyUsed 
            ? vouchers.where((voucher) => voucher['used'] == 1).toList()
            : List.from(vouchers);
        _recentLoginCount = vouchers.length; // All vouchers are from last 24h
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading vouchers: $e');
      setState(() {
        _loading = false;
        _vouchers = [];
        _filteredVouchers = [];
        _recentLoginCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.showOnlyUsed ? 'Used Vouchers' : 'Recent Vouchers',
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
            onPressed: _loadVouchers,
            tooltip: 'Refresh Vouchers',
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
                  child: Icon(
                    widget.showOnlyUsed ? Icons.check_circle_rounded : Icons.access_time_rounded,
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
                        widget.showOnlyUsed ? 'Used Vouchers' : 'Recent Activity',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.showOnlyUsed 
                            ? 'Vouchers that have been used'
                            : 'Last 24 hours voucher activity',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                ModernBadge(
                  text: '${_filteredVouchers.length}',
                  backgroundColor: Colors.white.withOpacity(0.2),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),
          
          // Search Bar
          ModernSearchBar(
            hintText: 'Search by username...',
            controller: _searchController,
            onChanged: _filterVouchers,
            onClear: () {
              _searchController.clear();
              _filterVouchers('');
            },
          ),
          
          // Content Section
          Expanded(
            child: _loading
                ? const ModernLoading(
                    message: 'Loading vouchers...',
                  )
                : _searching
                    ? const ModernLoading(
                        message: 'Searching for user...',
                      )
                    : _filteredVouchers.isEmpty
                        ? EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: _searchController.text.isNotEmpty 
                                ? 'User Not Found'
                                : 'No Vouchers Found',
                            subtitle: _searchController.text.isNotEmpty
                                ? 'No user found with username "${_searchController.text}"'
                                : 'No recent voucher activity found',
                            action: _searchController.text.isNotEmpty
                                ? TextButton.icon(
                                    onPressed: () {
                                      _searchController.clear();
                                      _filterVouchers('');
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                    label: const Text('Clear Search'),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: _loadVouchers,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Refresh'),
                                  ),
                          )
                    : RefreshIndicator(
                        onRefresh: _loadVouchers,
                        color: AppTheme.primaryColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          itemCount: _filteredVouchers.length,
                          itemBuilder: (context, index) {
                            final voucher = _filteredVouchers[index];
                            return _buildVoucherCard(voucher);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildVoucherCard(Map<String, dynamic> voucher) {
    final loginTime = _parseDateTime(voucher['first_login_time']?.toString());
    final expireTime = _parseDateTime(voucher['expire_time']?.toString());
    final isUsed = voucher['used'] == 1;
    final hasMAC = voucher['mac_address']?.toString().isNotEmpty == true;
    
    // Check if voucher is expired
    bool isExpired = false;
    if (expireTime != null) {
      isExpired = DateTime.now().isAfter(expireTime);
    }
    
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getStatusColor(isUsed, isExpired).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getStatusIcon(isUsed, isExpired),
                  color: _getStatusColor(isUsed, isExpired),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voucher['username']?.toString() ?? 'Unknown User',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      voucher['location']?.toString() ?? 'Unknown Location',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Status Badge
              ModernBadge(
                text: _getStatusText(isUsed, isExpired),
                backgroundColor: _getStatusColor(isUsed, isExpired),
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
                // MAC Address Row
                Row(
                  children: [
                    Icon(
                      Icons.devices_other_rounded,
                      size: 16,
                      color: hasMAC ? AppTheme.successColor : AppTheme.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MAC Address:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasMAC ? voucher['mac_address'].toString() : 'Not registered',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: hasMAC ? AppTheme.textPrimary : AppTheme.textTertiary,
                          fontFamily: hasMAC ? 'monospace' : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Speed Limit Row
                Row(
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Speed Limit:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        voucher['speed_limit']?.toString() ?? 'N/A',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Session Timeout Row
                Row(
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Session Timeout:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        voucher['session_timeout']?.toString() ?? 'N/A',
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
          
          if (loginTime != null || expireTime != null) ...[
            const SizedBox(height: 12),
            // Time Information
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isExpired ? AppTheme.errorColor : AppTheme.infoColor).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isExpired ? AppTheme.errorColor : AppTheme.infoColor).withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  if (loginTime != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.login_rounded,
                          size: 16,
                          color: AppTheme.successColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'First Login:',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('MMM dd, yyyy HH:mm').format(loginTime),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (expireTime != null) const SizedBox(height: 8),
                  ],
                  if (expireTime != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: isExpired ? AppTheme.errorColor : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Expires:',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('MMM dd, yyyy HH:mm').format(expireTime),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isExpired ? AppTheme.errorColor : AppTheme.textPrimary,
                              fontWeight: isExpired ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isExpired) ...[
                          const SizedBox(width: 8),
                          ModernBadge(
                            text: 'EXPIRED',
                            backgroundColor: AppTheme.errorColor,
                            textColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // Helper methods for voucher status
  String _getStatusText(bool isUsed, bool isExpired) {
    // Priority: EXPIRED > USED > PENDING
    if (isExpired) {
      return 'EXPIRED';
    } else if (isUsed) {
      return 'USED';
    } else {
      return 'PENDING';
    }
  }
  
  Color _getStatusColor(bool isUsed, bool isExpired) {
    // Priority: EXPIRED > USED > PENDING
    if (isExpired) {
      return AppTheme.errorColor;
    } else if (isUsed) {
      return AppTheme.successColor;
    } else {
      return AppTheme.warningColor;
    }
  }
  
  IconData _getStatusIcon(bool isUsed, bool isExpired) {
    // Priority: EXPIRED > USED > PENDING
    if (isExpired) {
      return Icons.cancel_rounded;
    } else if (isUsed) {
      return Icons.check_circle_rounded;
    } else {
      return Icons.pending_rounded;
    }
  }
}