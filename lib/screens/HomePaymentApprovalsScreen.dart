import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/attachment_ref.dart';
import 'package:lightnetwork/models/payment_record.dart';
import 'package:lightnetwork/screens/HomeCustomerPeriodsScreen.dart';
import '../theme/app_theme.dart';

class HomePaymentApprovalsScreen extends StatefulWidget {
  const HomePaymentApprovalsScreen({super.key});

  @override
  State<HomePaymentApprovalsScreen> createState() => _HomePaymentApprovalsScreenState();
}

class _HomePaymentApprovalsScreenState extends State<HomePaymentApprovalsScreen> {
  final _auth = Get.find<AuthController>();
  final Map<String, String> _customerNames = {};
  final Set<String> _nameLookups = {};

  void _prefetchNames(Iterable<String> ids) {
    for (final id in ids) {
      if (id.isEmpty || _customerNames.containsKey(id) || _nameLookups.contains(id)) {
        continue;
      }
      _nameLookups.add(id);
      HomeInternetService.getCustomer(id).then((customer) {
        if (!mounted) return;
        setState(() {
          _customerNames[id] = customer?.name ?? 'Customer $id';
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _customerNames[id] = 'Customer $id';
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isBoss) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Home Payment Approvals'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
          ),
        ),
        body: const Center(child: Text('Boss role required to approve payments.')),
      );
    }

    final fmtAmt = NumberFormat('#,##0');
    final fmtDate = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Payment Approvals'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collectionGroup('payments')
            .where('status', isEqualTo: PaymentStatus.pendingApproval.name)
            .orderBy('created_at', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const _EmptyApprovals();
          }
          final pending = docs.map((d) {
            final pr = PaymentRecord.fromMap(d.data(), d.id);
            return pr;
          }).toList();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _prefetchNames(pending.map((p) => p.customerId));
          });
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final pr = pending[index];
              final amount = 'TZS ${fmtAmt.format(pr.amountPaid)}';
              final created = fmtDate.format(pr.createdAt);
              final attachmentsCount = pr.attachments.length;
              final customerName = _customerNames[pr.customerId] ?? 'Customer ${pr.customerId}';

              return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _showDetails(context, pr),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppGradients.cardGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.receipt_long_rounded, color: AppTheme.warningColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customerName,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          amount,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: ${pr.customerId}',
                                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'PENDING',
                                      style: TextStyle(color: AppTheme.warningColor, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.textSecondary),
                                  const SizedBox(width: 6),
                                  Text('Created: $created', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _miniChip(Icons.attach_file_rounded, 'Attachments: $attachmentsCount'),
                                  if (pr.paymentType != null && pr.paymentType!.isNotEmpty)
                                    _miniChip(Icons.payments_rounded, pr.paymentType!),
                                  if (pr.reference != null && pr.reference!.isNotEmpty)
                                    _miniChip(Icons.numbers_rounded, 'Ref: ${pr.reference}'),
                                  _miniChip(Icons.person_rounded, 'By: ${pr.createdByName}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
            },
          );
        },
      ),
    );
  }

  Future<void> _approve(PaymentRecord pr) async {
    try {
      await HomeInternetService.approvePayment(customerId: pr.customerId, paymentId: pr.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment approved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _reject(PaymentRecord pr) async {
    final reason = await _askReason();
    if (!mounted) return;
    if (reason == null) return;
    try {
      await HomeInternetService.rejectPayment(customerId: pr.customerId, paymentId: pr.id, reason: reason);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment rejected')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<String?> _askReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Payment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context, PaymentRecord pr) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _PaymentDetailsScreen(
          payment: pr,
          onApprove: () async {
            Navigator.pop(ctx);
            await _approve(pr);
          },
          onReject: () async {
            Navigator.pop(ctx);
            await _reject(pr);
          },
        ),
      ),
    );
  }

}

class _EmptyApprovals extends StatelessWidget {
  const _EmptyApprovals();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified_outlined, size: 48, color: AppTheme.textTertiary),
            SizedBox(height: 12),
            Text('No pending approvals', style: TextStyle(color: AppTheme.textSecondary)),
            SizedBox(height: 4),
            Text('New payments will appear here for boss approval.', style: TextStyle(color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _PaymentDetailsScreen extends StatelessWidget {
  final PaymentRecord payment;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PaymentDetailsScreen({
    required this.payment,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final fmtAmt = NumberFormat('#,##0');
    final fmtDate = DateFormat('yyyy-MM-dd HH:mm');
    final fmtDateOnly = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Details'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.payments_rounded, size: 48, color: AppTheme.primaryColor),
                    const SizedBox(height: 12),
                    Text(
                      'TZS ${fmtAmt.format(payment.amountPaid)}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.warningColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'PENDING APPROVAL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Payment Information
            _SectionTitle(title: 'Payment Information'),
            const SizedBox(height: 12),
            _InfoRow(label: 'Customer ID', value: payment.customerId),
            _InfoRow(label: 'Amount', value: 'TZS ${fmtAmt.format(payment.amountPaid)}'),
            _InfoRow(label: 'Schedule', value: payment.schedule.name.toUpperCase()),
            _InfoRow(label: 'Period', value: '${fmtDateOnly.format(payment.periodStart)} to ${fmtDateOnly.format(payment.periodEnd)}'),
            _InfoRow(label: 'Due Date', value: fmtDateOnly.format(payment.dueDate)),
            if (payment.reference != null && payment.reference!.isNotEmpty)
              _InfoRow(label: 'Reference', value: payment.reference!),
            if (payment.notes != null && payment.notes!.isNotEmpty)
              _InfoRow(label: 'Notes', value: payment.notes!, maxLines: 3),

            const SizedBox(height: 20),

            // Periods Navigation
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HomeCustomerPeriodsScreen(
                        customerId: payment.customerId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('View Billing Periods'),
              ),
            ),
            const SizedBox(height: 20),

            // Submitted By
            _SectionTitle(title: 'Submitted By'),
            const SizedBox(height: 12),
            _InfoRow(label: 'Name', value: payment.createdByName),
            _InfoRow(label: 'Date', value: fmtDate.format(payment.createdAt)),

            const SizedBox(height: 20),

            // Attachments
            if (payment.attachments.isNotEmpty) ...[
              _SectionTitle(title: 'Attachments (${payment.attachments.length})'),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: payment.attachments.length,
                itemBuilder: (context, index) {
                  final attachment = payment.attachments[index];
                  final isImage = attachment.contentType.startsWith('image/');
                  return GestureDetector(
                    onTap: () => _viewAttachment(context, attachment),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: isImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                attachment.url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded),
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  attachment.contentType.contains('pdf')
                                      ? Icons.picture_as_pdf_rounded
                                      : Icons.insert_drive_file_rounded,
                                  color: Colors.red,
                                  size: 32,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  attachment.name.length > 12
                                      ? '${attachment.name.substring(0, 12)}...'
                                      : attachment.name,
                                  style: const TextStyle(fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.cancel_rounded),
                    label: const Text('Reject'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _viewAttachment(BuildContext context, AttachmentRef attachment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _AttachmentViewerScreen(attachment: attachment),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;

  const _InfoRow({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.textPrimary),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _miniChip(IconData icon, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.textSecondary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AttachmentViewerScreen extends StatelessWidget {
  final AttachmentRef attachment;

  const _AttachmentViewerScreen({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.contentType.startsWith('image/');

    return Scaffold(
      appBar: AppBar(
        title: Text(attachment.name),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: Center(
        child: isImage
            ? InteractiveViewer(
                child: Image.network(
                  attachment.url,
                  errorBuilder: (_, __, ___) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_rounded, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Failed to load image'),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      attachment.contentType.contains('pdf')
                          ? Icons.picture_as_pdf_rounded
                          : Icons.insert_drive_file_rounded,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      attachment.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(attachment.sizeBytes / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Open in browser or external viewer
                        // You can use url_launcher package here
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open in Browser'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
