import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../controllers/ApiService.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class VoucherManagementScreen extends StatefulWidget {
  const VoucherManagementScreen({super.key});

  @override
  State<VoucherManagementScreen> createState() => _VoucherManagementScreenState();
}

class _VoucherManagementScreenState extends State<VoucherManagementScreen> {
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  DateTime? _parseDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) {
      debugPrint('Date string is null or empty');
      return null;
    }
    try {
      // Try HTTP date format first
      return _httpDateFormat.parse(dateTimeStr, true);
    } catch (e) {
      debugPrint('Error parsing date "$dateTimeStr" with format E, dd MMM yyyy HH:mm:ss GMT: $e');
      try {
        // Try MySQL DATETIME format
        return _mysqlDateFormat.parse(dateTimeStr);
      } catch (e2) {
        debugPrint('Error parsing date "$dateTimeStr" with format yyyy-MM-dd HH:mm:ss: $e2');
        try {
          // Try ISO 8601 fallback
          return DateTime.parse(dateTimeStr);
        } catch (e3) {
          debugPrint('Error parsing date "$dateTimeStr" with ISO format: $e3');
          return null;
        }
      }
    }
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'N/A';
    final dateTime = _parseDateTime(dateTimeStr);
    if (dateTime == null) {
      debugPrint('Failed to format date: $dateTimeStr');
      return 'Invalid Date';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  final TextEditingController _macAddressController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedExpireTime;
  List<dynamic> _vouchers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  Future<void> _loadVouchers() async {
    setState(() => _isLoading = true);
    try {
      final vouchers = await ApiService.fetchVouchersByName();
      setState(() {
        _vouchers = List.from(vouchers);
      });
    } catch (e) {
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      Get.snackbar('Error', errorMessage);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectExpireTime(BuildContext context, [StateSetter? dialogSetState]) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpireTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2099),
      helpText: 'SELECT EXPIRE DATE',
    );

    if (picked != null) {
      final TimeOfDay? timePicked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedExpireTime ?? DateTime.now()),
        helpText: 'SELECT EXPIRE TIME',
      );

      if (timePicked != null) {
        final selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          timePicked.hour,
          timePicked.minute,
        );

        if (dialogSetState != null) {
          dialogSetState(() {
            _selectedExpireTime = selectedDateTime;
          });
        } else {
          setState(() {
            _selectedExpireTime = selectedDateTime;
          });
        }
      }
    }
  }

  String _formatSelectedExpireTime() {
    if (_selectedExpireTime == null) return 'Select expiration time';
    return DateFormat('yyyy-MM-dd HH:mm').format(_selectedExpireTime!);
  }

  void _clearForm() {
    _macAddressController.clear();
    _nameController.clear();
    setState(() {
      _selectedExpireTime = null;
    });
  }

  Future<void> _showAddVoucherDialog() async {
    _clearForm();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Voucher'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _macAddressController,
                    decoration: const InputDecoration(
                      labelText: 'MAC Address',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter MAC address';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Expiration Time Selection
                  InkWell(
                    onTap: () => _selectExpireTime(context, setState),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: _selectedExpireTime != null 
                                ? AppTheme.primaryColor 
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatSelectedExpireTime(),
                              style: TextStyle(
                                color: _selectedExpireTime != null 
                                    ? AppTheme.textPrimary 
                                    : Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                if (_selectedExpireTime == null) {
                  Get.snackbar('Error', 'Please select an expiration time');
                  return;
                }

                try {
                  final response = await ApiService.insertVoucher(
                    macAddress: _macAddressController.text,
                    name: _nameController.text.isEmpty ? null : _nameController.text,
                    expireTime: _selectedExpireTime,
                  );

                  if (response['success'] == true) {
                    Get.snackbar('Success', 'Voucher inserted successfully');
                    Navigator.pop(context);
                    _clearForm();
                    _loadVouchers();
                  } else {
                    Get.snackbar('Error', response['error'] ?? 'Failed to insert voucher');
                  }
                } catch (e) {
                  Get.snackbar('Error', 'Network error occurred: $e');
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateVoucherDialog(Map<String, dynamic> voucher) async {
    setState(() {
      _macAddressController.text = voucher['mac_address'];
      _nameController.text = voucher['name'];
      // Parse existing expiration time if available
      _selectedExpireTime = _parseDateTime(voucher['expire_time']?.toString());
    });

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Voucher'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _macAddressController,
                    decoration: const InputDecoration(
                      labelText: 'MAC Address',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter MAC address';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Expiration Time Selection
                  InkWell(
                    onTap: () => _selectExpireTime(context, setState),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: _selectedExpireTime != null 
                                ? AppTheme.primaryColor 
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatSelectedExpireTime(),
                              style: TextStyle(
                                color: _selectedExpireTime != null 
                                    ? AppTheme.textPrimary 
                                    : Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                if (_selectedExpireTime == null) {
                  Get.snackbar('Error', 'Please select an expiration time');
                  return;
                }

                try {
                  final response = await ApiService.updateVoucher(
                    username: voucher['username'],
                    newMacAddress: _macAddressController.text != voucher['mac_address'] ? _macAddressController.text : null,
                    name: _nameController.text.isEmpty || _nameController.text == voucher['name'] ? null : _nameController.text,
                    expireTime: _selectedExpireTime,
                  );

                  if (response['success'] == true) {
                    Get.snackbar('Success', 'Voucher updated successfully');
                    Navigator.pop(context);
                    _clearForm();
                    _loadVouchers();
                  } else {
                    Get.snackbar('Error', response['error'] ?? 'Failed to update voucher');
                  }
                } catch (e) {
                  Get.snackbar('Error', 'Network error occurred: $e');
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(Map<String, dynamic> voucher) async {
    final shouldDelete = await Get.dialog(
      AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete voucher "${voucher['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete ?? false) {
      try {
        final response = await ApiService.deleteVoucherByUsername(voucher['username']);
        if (response['success'] == true) {
          Get.snackbar('Success', 'Voucher deleted successfully');
          _loadVouchers();
        } else {
          Get.snackbar('Error', response['error'] ?? 'Failed to delete voucher');
        }
      } catch (e) {
        Get.snackbar('Error', 'Network error occurred: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Voucher Management',
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
      floatingActionButton: ModernFAB(
        onPressed: _showAddVoucherDialog,
        icon: Icons.add_rounded,
        label: 'Add Voucher',
        extended: true,
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
                    Icons.vpn_key_rounded,
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
                        'MAC Address Vouchers',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage device-specific vouchers',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                ModernBadge(
                  text: '${_vouchers.length}',
                  backgroundColor: Colors.white.withOpacity(0.2),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),
          
          // Content Section
          Expanded(
            child: _isLoading
                ? const ModernLoading(
                    message: 'Loading vouchers...',
                  )
                : _vouchers.isEmpty
                    ? EmptyState(
                        icon: Icons.vpn_key_outlined,
                        title: 'No Vouchers Found',
                        subtitle: 'Create your first MAC address voucher to get started',
                        action: ElevatedButton.icon(
                          onPressed: _showAddVoucherDialog,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add Voucher'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadVouchers,
                        color: AppTheme.primaryColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _vouchers.length,
                          itemBuilder: (context, index) {
                            final voucher = _vouchers[index];
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
    final isExpired = _isVoucherExpired(voucher['expire_time']?.toString());
    final hasMAC = voucher['mac_address']?.toString().isNotEmpty == true;
    
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
                  color: (isExpired ? AppTheme.errorColor : AppTheme.primaryColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isExpired ? Icons.error_outline_rounded : Icons.vpn_key_rounded,
                  color: isExpired ? AppTheme.errorColor : AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voucher['name']?.toString() ?? 'Unnamed Voucher',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isExpired ? AppTheme.textSecondary : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Code: ${voucher['username']?.toString() ?? 'N/A'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // Status Badge
              ModernBadge(
                text: isExpired ? 'EXPIRED' : 'ACTIVE',
                backgroundColor: isExpired ? AppTheme.errorColor : AppTheme.successColor,
                textColor: Colors.white,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Details Section
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
                // Expiry Row
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
                        _formatDateTime(voucher['expire_time']?.toString()),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isExpired ? AppTheme.errorColor : AppTheme.textPrimary,
                          fontWeight: isExpired ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showUpdateVoucherDialog(voucher),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.5)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDeleteConfirmation(voucher),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: BorderSide(color: AppTheme.errorColor.withOpacity(0.5)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  bool _isVoucherExpired(String? expireTimeStr) {
    if (expireTimeStr == null || expireTimeStr.isEmpty) return false;
    final expireTime = _parseDateTime(expireTimeStr);
    if (expireTime == null) return false;
    return DateTime.now().isAfter(expireTime);
  }
  @override
  void dispose() {
    _macAddressController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
