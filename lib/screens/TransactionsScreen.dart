import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../controllers/auth_controller.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authCtrl = Get.find<AuthController>();
    final isBoss = authCtrl.isBoss;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final Stream<QuerySnapshot> stream = isBoss
        ? FirebaseFirestore.instance
            .collection('float_transactions')
            .limit(100)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('float_transactions')
            .where('user_id', isEqualTo: uid)
            .limit(100)
            .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            );
          }
          final rawDocs = snapshot.data?.docs ?? [];
          // Sort client-side by timestamp descending (avoids composite index)
          final docs = rawDocs.toList()
            ..sort((a, b) {
              final ta = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
              final tb = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No transactions yet', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                ],
              ),
            );
          }

          // Group by date
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final doc in docs) {
            final d = doc.data() as Map<String, dynamic>;
            final ts = d['timestamp'] as Timestamp?;
            final dateKey = ts != null
                ? DateFormat('MMMM dd, yyyy').format(ts.toDate())
                : 'Unknown Date';
            grouped.putIfAbsent(dateKey, () => []).add(d);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: grouped.keys.length,
            itemBuilder: (context, i) {
              final dateKey = grouped.keys.elementAt(i);
              final items = grouped[dateKey]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      dateKey,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...items.map((d) => _buildTile(context, d, isBoss)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTile(BuildContext context, Map<String, dynamic> d, bool isBoss) {
    final type = d['type'] as String? ?? '';
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final ts = d['timestamp'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '';
    final rawUserName = d['user_name'] as String? ?? '';
    final rawPerformedBy = d['performed_by_name'] as String? ?? '';
    final userName = rawUserName.trim();
    final performedBy = rawPerformedBy.trim();
    final reason = d['reason'] as String? ?? '';
    final mobile = d['mobile_or_account'] as String? ?? '';
    final location = d['location'] as String? ?? '';
    final requestTitle = d['request_title'] as String? ?? '';
    final balanceAfter = (d['balance_after'] as num?)?.toDouble();

    Color color;
    IconData icon;
    String title;
    List<String> subtitleParts = [];

    switch (type) {
      case 'credit':
        color = Colors.green;
        icon = Icons.add_circle_rounded;
        title = 'Float Added';
        // Fallback to email fields if name is empty
        final toName = userName.isNotEmpty ? userName : (d['user_email'] as String? ?? '').trim();
        final byName = performedBy.isNotEmpty ? performedBy : (d['performed_by'] as String? ?? '').trim();
        if (toName.isNotEmpty) subtitleParts.add('To: $toName');
        if (byName.isNotEmpty) subtitleParts.add('By: $byName');
        break;
      case 'approval_deduction':
        color = Colors.blue;
        icon = Icons.check_circle_rounded;
        title = requestTitle.isNotEmpty ? 'Approved: $requestTitle' : 'Request Approved';
        if (location.isNotEmpty) subtitleParts.add('Location: $location');
        if (isBoss && userName.isNotEmpty) subtitleParts.add('By: $userName');
        break;
      case 'withdrawal':
        color = Colors.orange;
        icon = Icons.money_off_rounded;
        title = reason.isNotEmpty ? 'Withdrawal: $reason' : 'Withdrawal';
        if (mobile.isNotEmpty) subtitleParts.add('To: $mobile');
        if (isBoss && performedBy.isNotEmpty) subtitleParts.add('By: $performedBy');
        break;
      default:
        color = Colors.grey;
        icon = Icons.receipt_rounded;
        title = type;
    }

    final isDebit = type == 'approval_deduction' || type == 'withdrawal';
    final subtitle = subtitleParts.join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isDebit ? '-' : '+'}TZS ${_fmt(amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDebit ? Colors.red[700] : Colors.green[700],
                  ),
                ),
                if (balanceAfter != null)
                  Text('Bal: ${_fmt(balanceAfter)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}
