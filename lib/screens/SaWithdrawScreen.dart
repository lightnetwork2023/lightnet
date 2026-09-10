import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class SaWithdrawScreen extends StatefulWidget {
  const SaWithdrawScreen({super.key});

  @override
  State<SaWithdrawScreen> createState() => _SaWithdrawScreenState();
}

class _SaWithdrawScreenState extends State<SaWithdrawScreen> {
  final _authController = Get.find<AuthController>();
  final _db = FirebaseFirestore.instance;
  bool _isSubmitting = false;

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _fmt(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},');

  // ─── Withdraw Dialog ──────────────────────────────────────────────────────

  void _showWithdrawDialog(double availableBalance) {
    final amountCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Request Withdrawal',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available:',
                            style: TextStyle(color: Colors.grey)),
                        Text(
                          'TZS ${_fmt(availableBalance)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (TZS) *',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n =
                          double.tryParse(v?.replaceAll(',', '') ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      if (n > availableBalance) return 'Exceeds available balance';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile or Account Number *',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Account Holder Name *',
                      prefixIcon: Icon(Icons.person_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (_isSubmitting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _isSubmitting ? null : () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white),
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDS(() => _isSubmitting = true);
                      try {
                        final uid = _authController.user?.uid;
                        final amount = double.parse(
                            amountCtrl.text.replaceAll(',', ''));

                        final pendingSnap = await _db
                            .collection('sa_withdrawal_requests')
                            .where('user_id', isEqualTo: uid)
                            .where('status', isEqualTo: 'pending')
                            .get();
                        final pendingTotal =
                            pendingSnap.docs.fold<double>(
                          0,
                          (s, d) =>
                              s +
                              ((d.data()['amount'] as num?)?.toDouble() ??
                                  0),
                        );
                        if (pendingTotal + amount > availableBalance) {
                          throw Exception(
                              'Total pending (TZS ${_fmt(pendingTotal + amount)}) would exceed available balance.');
                        }

                        await _db
                            .collection('sa_withdrawal_requests')
                            .add({
                          'user_id': uid,
                          'user_name': _authController.userName,
                          'amount': amount,
                          'mobile_or_account': mobileCtrl.text.trim(),
                          'account_name': nameCtrl.text.trim(),
                          'status': 'pending',
                          'created_at': FieldValue.serverTimestamp(),
                        });

                        if (mounted) Navigator.pop(dCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('✅ Withdrawal request submitted'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ $e')));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isSubmitting = false);
                          setDS(() {});
                        }
                      }
                    },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Evidence fullscreen ──────────────────────────────────────────────────

  void _showEvidenceFullscreen(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(url))),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = _authController.user?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdraw',
            style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple, Colors.purpleAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Not authenticated'))
          : StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('users').doc(uid).snapshots(),
              builder: (context, snap) {
                final data =
                    snap.data?.data() as Map<String, dynamic>? ?? {};
                final balance =
                    (data['withdrawable_balance'] as num?)?.toDouble() ??
                        0.0;
                final settlement =
                    data['last_monthly_settlement'] as Map<String, dynamic>?;
                final month = settlement?['month'] as String? ?? '';
                final gross =
                    (settlement?['gross_revenue'] as num?)?.toDouble() ??
                        0;
                final deductions =
                    (settlement?['deductions'] as num?)?.toDouble() ?? 0;
                final netCredited =
                    (settlement?['net_credited'] as num?)?.toDouble() ?? 0;
                final saPercent =
                    (_authController.commissionSuperAgent * 100)
                        .toStringAsFixed(0);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Balance card ────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.account_balance_wallet_rounded,
                                  color: Colors.white70, size: 20),
                              SizedBox(width: 8),
                              Text('Withdrawable Balance',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'TZS ${_fmt(balance)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold),
                          ),
                          if (month.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Last Settlement: $month',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Revenue ($saPercent%): TZS ${_fmt(gross * _authController.commissionSuperAgent)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11),
                                      ),
                                      Text(
                                        '- TZS ${_fmt(deductions)} (SIM)',
                                        style: const TextStyle(
                                            color: Colors.orangeAccent,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Net Credited: TZS ${_fmt(netCredited)}',
                                    style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1B5E20),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: balance <= 0
                                  ? null
                                  : () => _showWithdrawDialog(balance),
                              icon: const Icon(
                                  Icons.arrow_circle_up_rounded,
                                  size: 20),
                              label: Text(
                                balance <= 0
                                    ? 'No Balance Available'
                                    : 'Request Withdrawal',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── My Requests ─────────────────────────────────────
                    const Text('My Withdrawal Requests',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    StreamBuilder<QuerySnapshot>(
                      stream: _db
                          .collection('sa_withdrawal_requests')
                          .where('user_id', isEqualTo: uid)
                          .limit(30)
                          .snapshots(),
                      builder: (context, reqSnap) {
                        if (reqSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final docs = reqSnap.data?.docs ?? [];
                        final sorted = docs.toList()
                          ..sort((a, b) {
                            final ta = (a.data() as Map)['created_at']
                                as Timestamp?;
                            final tb = (b.data() as Map)['created_at']
                                as Timestamp?;
                            if (ta == null && tb == null) return 0;
                            if (ta == null) return 1;
                            if (tb == null) return -1;
                            return tb.compareTo(ta);
                          });

                        if (sorted.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text('No withdrawal requests yet',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          );
                        }

                        return Column(
                          children: sorted.map((doc) {
                            final d =
                                doc.data() as Map<String, dynamic>;
                            final status =
                                d['status'] as String? ?? 'pending';
                            final amount =
                                (d['amount'] as num?)?.toDouble() ?? 0;
                            final ts = d['created_at'] as Timestamp?;
                            final dateStr = ts != null
                                ? DateFormat('dd MMM yyyy, HH:mm')
                                    .format(ts.toDate())
                                : '';
                            final evidenceUrl =
                                d['evidence_url'] as String?;

                            Color statusColor;
                            IconData statusIcon;
                            switch (status) {
                              case 'approved':
                                statusColor = Colors.green;
                                statusIcon = Icons.check_circle_rounded;
                                break;
                              case 'rejected':
                                statusColor = Colors.red;
                                statusIcon = Icons.cancel_rounded;
                                break;
                              default:
                                statusColor = Colors.orange;
                                statusIcon = Icons.hourglass_top_rounded;
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color:
                                        statusColor.withOpacity(0.3)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(statusIcon,
                                            color: statusColor, size: 22),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'TZS ${_fmt(amount)}',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: statusColor),
                                          ),
                                        ),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                                color: statusColor,
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${d['account_name'] ?? ''} • ${d['mobile_or_account'] ?? ''}',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 13),
                                    ),
                                    Text(dateStr,
                                        style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 11)),
                                    if (status == 'approved' &&
                                        evidenceUrl != null &&
                                        evidenceUrl.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      const Text('Payment Evidence',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                              color: Colors.green)),
                                      const SizedBox(height: 6),
                                      GestureDetector(
                                        onTap: () =>
                                            _showEvidenceFullscreen(
                                                evidenceUrl),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(
                                            evidenceUrl,
                                            height: 150,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            loadingBuilder:
                                                (_, child, p) => p == null
                                                    ? child
                                                    : const SizedBox(
                                                        height: 150,
                                                        child: Center(
                                                            child:
                                                                CircularProgressIndicator())),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text('Tap to view full size',
                                          style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 11)),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}
