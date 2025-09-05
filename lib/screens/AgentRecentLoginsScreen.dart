import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/ApiService.dart';
import '../widgets/modern_components.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class AgentRecentLoginsScreen extends StatefulWidget {
  final String location;

  const AgentRecentLoginsScreen({
    super.key,
    required this.location,
  });

  @override
  State<AgentRecentLoginsScreen> createState() => _AgentRecentLoginsScreenState();
}

class _AgentRecentLoginsScreenState extends State<AgentRecentLoginsScreen> {
  List<Map<String, dynamic>> _vouchers = [];
  List<Map<String, dynamic>> _filteredVouchers = [];
  bool _isLoading = true;
  bool _searching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _loadRecentLogins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentLogins() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await ApiService.fetchSuperAgentRecentVouchers(
        locations: widget.location, // Pass single location
        searchTerm: '', // Load all recent logins without search
      );
      
      if (response['vouchers'] != null) {
        setState(() {
          _vouchers = List<Map<String, dynamic>>.from(response['vouchers']);
          _filteredVouchers = _vouchers;
          _isLoading = false;
        });
      } else {
        setState(() {
          _vouchers = [];
          _filteredVouchers = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _vouchers = [];
        _filteredVouchers = [];
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading recent logins: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterVouchers(String query) {
    // Cancel any existing timer
    _searchTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _searchQuery = query;
        _filteredVouchers = List.from(_vouchers);
        _searching = false;
      });
      return;
    }
    
    // Set searching state immediately
    setState(() {
      _searchQuery = query;
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
          final voucherInfo = result['voucher_info'];
          // Check if this voucher belongs to the agent's location
          final voucherLocation = voucherInfo['location']?.toString() ?? '';
          if (voucherLocation == widget.location) {
            _filteredVouchers = [voucherInfo];
          } else {
            // User found but not in agent's location
            _filteredVouchers = [];
          }
        } else {
          // User not found
          _filteredVouchers = [];
        }
      });
    } catch (e) {
      setState(() {
        _searching = false;
        // On error, fall back to local filtering
        _filteredVouchers = _vouchers.where((voucher) {
          final voucherUsername = voucher['username']?.toString().toLowerCase() ?? '';
          final macAddress = voucher['mac_address']?.toString().toLowerCase() ?? '';
          return voucherUsername.contains(username.toLowerCase()) ||
                 macAddress.contains(username.toLowerCase());
        }).toList();
      });
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Search failed, showing local results: ${e.toString().replaceFirst('Exception: ', '')}'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
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

  Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied "$text" to clipboard'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return 'N/A';
    
    if (seconds < 3600) {
      return '${(seconds / 60).round()} min';
    } else if (seconds < 86400) {
      return '${(seconds / 3600).round()} hr';
    } else {
      return '${(seconds / 86400).round()} days';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent Logins'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green, Colors.lightGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadRecentLogins,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ModernSearchBar(
              controller: _searchController,
              hintText: 'Search by username...',
              onChanged: _filterVouchers,
              onClear: () {
                _searchController.clear();
                _filterVouchers('');
              },
            ),
          ),
          
          // Results Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  '${_filteredVouchers.length} recent logins found',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.location,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? const ModernLoading(message: 'Loading recent logins...')
                : _searching
                    ? const ModernLoading(message: 'Searching for user...')
                    : _filteredVouchers.isEmpty
                        ? EmptyState(
                            icon: Icons.login,
                            title: _searchQuery.isEmpty 
                                ? 'No Recent Logins' 
                                : 'User Not Found',
                            subtitle: _searchQuery.isEmpty
                                ? 'No login activity in the last 24 hours in ${widget.location}.'
                                : _searchController.text.isNotEmpty
                                    ? 'No user found with username "${_searchController.text}" in ${widget.location}'
                                    : 'Try adjusting your search terms.',
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
                                    onPressed: _loadRecentLogins,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Refresh'),
                                  ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadRecentLogins,
                            color: Colors.green,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
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
    final username = voucher['username']?.toString() ?? 'N/A';
    final macAddress = voucher['mac_address']?.toString() ?? 'N/A';
    final location = voucher['location']?.toString() ?? 'N/A';
    final speedLimit = voucher['speed_limit']?.toString() ?? 'N/A';
    final sessionTimeout = voucher['session_timeout'];
    final firstLoginTime = voucher['first_login_time']?.toString();
    final expireTime = voucher['expire_time']?.toString();
    final isUsed = voucher['used'] == 1;

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isUsed ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUsed ? Icons.check_circle : Icons.pending,
                      size: 14,
                      color: isUsed ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUsed ? 'Active' : 'Pending',
                      style: TextStyle(
                        color: isUsed ? Colors.green : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  location,
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Username Row
          Row(
            children: [
              const Icon(Icons.person, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _copyToClipboard(username),
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy Username',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // MAC Address Row
          if (macAddress != 'N/A') ...[
            Row(
              children: [
                const Icon(Icons.device_hub, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    macAddress,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _copyToClipboard(macAddress),
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy MAC Address',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // Details Grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailItem(
                        'Speed Limit',
                        speedLimit,
                        Icons.speed,
                      ),
                    ),
                    Expanded(
                      child: _buildDetailItem(
                        'Duration',
                        _formatDuration(sessionTimeout),
                        Icons.timer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailItem(
                        'First Login',
                        _formatDateTime(firstLoginTime),
                        Icons.login,
                      ),
                    ),
                  ],
                ),
                if (expireTime != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailItem(
                          'Expires',
                          _formatDateTime(expireTime),
                          Icons.schedule,
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
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
