import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/models/payment_record.dart';
import '../theme/app_theme.dart';
import 'AddHomePaymentScreen.dart';

class CustomerPaymentsScreen extends StatelessWidget {
  final String customerId;
  final String? customerName;
  const CustomerPaymentsScreen({super.key, required this.customerId, this.customerName});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    return Scaffold(
      appBar: AppBar(
        title: Text(customerName == null ? 'Payments $customerId' : '${customerName!} ($customerId)')
            ,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddHomePaymentScreen(customerId: customerId, customerName: customerName),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Payment'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: StreamBuilder<List<PaymentRecord>>(
        stream: HomeInternetService.streamPayments(customerId),
        builder: (context, snapshot) {
          // Show cached data immediately, no loading spinner
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }
          
          final payments = snapshot.data ?? [];
          if (payments.isEmpty && snapshot.connectionState != ConnectionState.waiting) {
            return const _EmptyPayments();
          }
          
          return ListView.separated(
            itemCount: payments.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final pr = payments[index];
              final created = DateFormat('yyyy-MM-dd HH:mm').format(pr.createdAt);
              final statusColor = _statusColor(pr.status);
              return ListTile(
                title: Text('TZS ${fmt.format(pr.amountPaid)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Status: ${pr.status.name} • $created'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    pr.status.name.toUpperCase(),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                onTap: () => _openPayment(context, pr),
              );
            },
          );
        },
      ),
    );
  }

  Color _statusColor(PaymentStatus s) {
    switch (s) {
      case PaymentStatus.approved:
        return AppTheme.successColor;
      case PaymentStatus.rejected:
        return AppTheme.errorColor;
      case PaymentStatus.pendingApproval:
      default:
        return AppTheme.warningColor;
    }
  }

  void _openPayment(BuildContext context, PaymentRecord pr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Amount: ${pr.amountPaid} ${pr.currency}'),
              const SizedBox(height: 6),
              Text('Status: ${pr.status.name}'),
              const SizedBox(height: 6),
              if (pr.reference != null && pr.reference!.isNotEmpty)
                Text('Reference: ${pr.reference}'),
              if (pr.notes != null && pr.notes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Notes: ${pr.notes}'),
              ],
              const SizedBox(height: 10),
              const Text('Attachments:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (pr.attachments.isEmpty)
                const Text('No attachments')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: pr.attachments.map((a) => GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(a.url, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade200,
                        image: DecorationImage(image: NetworkImage(a.url), fit: BoxFit.cover),
                      ),
                    ),
                  )).toList(),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _EmptyPayments extends StatelessWidget {
  const _EmptyPayments();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.receipt_long_rounded, size: 48, color: AppTheme.textTertiary),
            SizedBox(height: 12),
            Text('No payments yet', style: TextStyle(color: AppTheme.textSecondary)),
            SizedBox(height: 4),
            Text('Use the Add Payment button to record a receipt.', style: TextStyle(color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}
