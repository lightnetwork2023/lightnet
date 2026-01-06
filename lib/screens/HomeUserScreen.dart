import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/home_customer.dart';
import 'package:lightnetwork/models/payment_record.dart';
import 'package:lightnetwork/screens/HomeUserPaymentScreen.dart';
import '../theme/app_theme.dart';

class HomeUserScreen extends StatefulWidget {
  const HomeUserScreen({super.key});

  @override
  State<HomeUserScreen> createState() => _HomeUserScreenState();
}

class _HomeUserScreenState extends State<HomeUserScreen> {
  final _auth = Get.find<AuthController>();
  bool _loading = true;
  HomeCustomer? _customer;
  Map<String, dynamic>? _status;
  List<PaymentRecord> _payments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final customerId = _auth.homeCustomerId;
      print('🔍 Loading data for customer ID: $customerId');
      
      if (customerId.isEmpty) {
        throw Exception('No customer ID linked to your account');
      }

      print('📡 Fetching customer data...');
      final customer = await HomeInternetService.getCustomer(customerId);
      if (customer == null) {
        throw Exception('Customer not found with ID: $customerId');
      }
      print('✅ Customer loaded: ${customer.name}');

      Map<String, dynamic>? status;
      if (customer.status != null) {
        final s = Map<String, dynamic>.from(customer.status!);
        final nd = s['next_due_date'];
        if (nd is Timestamp) s['next_due_date'] = nd.toDate();
        final lp = s['last_paid_at'];
        if (lp is Timestamp) s['last_paid_at'] = lp.toDate();
        status = s;
        print('✅ Using server-computed status');
      } else {
        print('⏳ Waiting for server-computed status');
        status = null;
      }

      if (!mounted) return;
      setState(() {
        _customer = customer;
        _status = status;
      });
      print('✅ Data loaded successfully');
    } catch (e, stackTrace) {
      print('❌ Error loading data: $e');
      print('Stack trace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Home Internet'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await _auth.logout();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customer == null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeCard(),
                        const SizedBox(height: 16),
                        _buildPlanCard(),
                        const SizedBox(height: 16),
                        _buildStatusCard(),
                        const SizedBox(height: 16),
                        _buildMakePaymentButton(),
                        const SizedBox(height: 16),
                        _buildPaymentHistory(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildMakePaymentButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const HomeUserPaymentScreen(),
            ),
          );
          if (result == true) {
            _loadData(); // Refresh data after payment
          }
        },
        icon: const Icon(Icons.payment_rounded),
        label: const Text('Make Payment'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            const Text(
              'Unable to load your account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please contact support if this issue persists.',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: AppGradients.primaryGradient,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back,',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              _customer!.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.badge_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  'ID: ${_customer!.id}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.phone_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  _customer!.phone,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard() {
    final fmt = NumberFormat('#,##0');
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.wifi_rounded, color: AppTheme.primaryColor, size: 20),
                SizedBox(width: 8),
                Text(
                  'Your Plan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('Speed', '${_customer!.speedMbps} Mbps'),
            const SizedBox(height: 12),
            _buildInfoRow('Plan Amount', 'TZS ${fmt.format(_customer!.planAmount)}'),
            const SizedBox(height: 12),
            _buildInfoRow('Billing', _customer!.schedule.name.toUpperCase()),
            const SizedBox(height: 12),
            _buildInfoRow('Zone', _customer!.zone),
            if (_customer!.location.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoRow('Location', _customer!.location),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_status == null) return const SizedBox.shrink();
    final fmt = NumberFormat('#,##0');
    final fmtDate = DateFormat('MMM dd, yyyy');
    
    final totalDue = (_status!['total_due_amount'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (_status!['total_paid_amount'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (_status!['outstanding_amount'] as num?)?.toDouble() ?? 0.0;
    final isOverdue = _status!['overdue'] as bool? ?? false;
    final nextDue = _status!['next_due_date'] as DateTime?;
    final lastPaid = _status!['last_paid_at'] as DateTime?;

    Color statusColor = AppTheme.successColor;
    String statusText = 'Paid Up';
    IconData statusIcon = Icons.check_circle_rounded;

    if (outstanding > 0) {
      if (isOverdue) {
        statusColor = AppTheme.errorColor;
        statusText = 'OVERDUE';
        statusIcon = Icons.warning_rounded;
      } else {
        statusColor = AppTheme.warningColor;
        statusText = 'Pending';
        statusIcon = Icons.schedule_rounded;
      }
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Payment Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Total Due', 'TZS ${fmt.format(totalDue)}'),
            const SizedBox(height: 12),
            _buildInfoRow('Total Paid', 'TZS ${fmt.format(totalPaid)}', valueColor: AppTheme.successColor),
            const SizedBox(height: 12),
            _buildInfoRow('Outstanding', 'TZS ${fmt.format(outstanding)}', valueColor: outstanding > 0 ? AppTheme.errorColor : AppTheme.successColor),
            if (nextDue != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow('Next Due Date', fmtDate.format(nextDue)),
            ],
            if (lastPaid != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow('Last Payment', fmtDate.format(lastPaid)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistory() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.history_rounded, color: AppTheme.primaryColor, size: 20),
                SizedBox(width: 8),
                Text(
                  'Payment History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'View your payment history and billing periods in the app.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Contact support for detailed payment records.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
