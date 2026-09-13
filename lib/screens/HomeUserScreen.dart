import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/home_customer.dart';
import 'package:lightnetwork/models/payment_record.dart';
import 'package:lightnetwork/screens/HomeCustomerPeriodsScreen.dart';
import 'package:lightnetwork/screens/HomeUserPaymentScreen.dart';
import 'package:lightnetwork/widgets/hi_account_statement.dart';
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
  List<PeriodPaymentStatus> _invoices = [];

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

      Map<String, dynamic> status = HomeInternetService.normalizeStatement(
        await HomeInternetService.computeCustomerStatus(customerId),
      );
      final invoices = await HomeInternetService.fetchInvoices(customerId);
      final payments = await HomeInternetService.fetchPayments(customerId, limit: 12);

      if (!mounted) return;
      setState(() {
        _customer = customer;
        _status = status;
        _invoices = invoices.reversed.take(6).toList();
        _payments = payments;
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
                        if (_status != null)
                          HiAccountStatement(
                            statement: _status!,
                            accountName: 'Account ${_customer!.id}',
                            onPayNow: _openPayment,
                          )
                        else
                          _buildStatusCard(),
                        const SizedBox(height: 16),
                        if (_status == null || HomeInternetService.asMoney(_status!['pay_now']) <= 0)
                          _buildMakePaymentButton(),
                        const SizedBox(height: 16),
                        _buildInvoicePreview(),
                        const SizedBox(height: 16),
                        _buildPaymentHistory(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Future<void> _openPayment() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HomeUserPaymentScreen(),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  Widget _buildMakePaymentButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openPayment,
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

  Widget _buildInvoicePreview() {
    final dateFmt = DateFormat('d MMM yyyy');
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
                const Icon(Icons.receipt_long_rounded, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Recent invoices',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HomeCustomerPeriodsScreen(
                          customerId: _customer!.id,
                          customerName: _customer!.name,
                        ),
                      ),
                    );
                  },
                  child: const Text('View statement'),
                ),
              ],
            ),
            const Divider(height: 20),
            if (_invoices.isEmpty)
              const Text(
                'No invoices have been issued yet.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              )
            else
              ..._invoices.map((inv) {
                final color = inv.state == PeriodPayState.paid
                    ? AppTheme.successColor
                    : (inv.state == PeriodPayState.partial ? AppTheme.warningColor : AppTheme.errorColor);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 18, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inv.invoiceNo ?? dateFmt.format(inv.start),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${dateFmt.format(inv.start)} – ${dateFmt.format(inv.end)}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        HiMoney.format(inv.balance > 0 ? inv.balance : inv.requiredAmount),
                        style: TextStyle(fontWeight: FontWeight.w700, color: color),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistory() {
    final dateFmt = DateFormat('d MMM yyyy');
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
                  'Payment receipts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_payments.isEmpty)
              const Text(
                'No payments recorded yet.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              )
            else
              ..._payments.take(8).map((p) {
                final when = p.approvedAt ?? p.createdAt;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(
                        p.status == PaymentStatus.approved
                            ? Icons.check_circle_rounded
                            : (p.status == PaymentStatus.rejected
                                ? Icons.cancel_rounded
                                : Icons.hourglass_bottom_rounded),
                        size: 18,
                        color: p.status == PaymentStatus.approved
                            ? AppTheme.successColor
                            : (p.status == PaymentStatus.rejected
                                ? AppTheme.errorColor
                                : AppTheme.warningColor),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${p.paymentType ?? 'Payment'} · ${dateFmt.format(when)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        HiMoney.format(p.amountPaid, currency: p.currency),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }),
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
