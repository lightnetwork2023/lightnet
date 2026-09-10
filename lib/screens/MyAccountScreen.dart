import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../controllers/auth_controller.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _authController = Get.find<AuthController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account', style: TextStyle(fontWeight: FontWeight.bold)),
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
      body: _authController.isBoss ? _buildBossView() : _buildMdView(),
    );
  }

  // ─── BOSS VIEW ──────────────────────────────────────────────────────────────

  Widget _buildBossView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildMdFloatSummary(),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _showAddFloatDialog,
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Add Float to MD'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showWithdrawDialog(isBoss: true),
                icon: const Icon(Icons.money_off_rounded),
                label: const Text('Withdraw'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('All Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildTransactionList(forBoss: true),
      ],
    );
  }

  Widget _buildMdFloatSummary() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').where('role', isEqualTo: 'md').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
        final mds = snapshot.data!.docs;
        if (mds.isEmpty) {
          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(padding: EdgeInsets.all(16), child: Text('No MD users found')),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MD Float Balances', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...mds.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final name = _resolveUserName(d);
              final balance = (d['float_balance'] as num?)?.toDouble() ?? 0.0;
              final isLow = balance < 50000;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isLow ? Colors.orange.withOpacity(0.5) : Colors.green.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isLow ? Colors.orange : Colors.green).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person_rounded, color: isLow ? Colors.orange[700] : Colors.green[700]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            if (isLow)
                              Text('⚠️ Low float', style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                          ],
                        ),
                      ),
                      Text(
                        'TZS ${_fmt(balance)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isLow ? Colors.orange[700] : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ─── MD VIEW ────────────────────────────────────────────────────────────────

  Widget _buildMdView() {
    final uid = _auth.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final balance = (data['float_balance'] as num?)?.toDouble() ?? 0.0;
        final isLow = balance < 50000;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLow
                      ? [Colors.orange[700]!, Colors.orange[400]!]
                      : [AppTheme.primaryColor, AppTheme.accentColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Text('Float Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      if (isLow) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('⚠️ LOW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'TZS ${_fmt(balance)}',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  if (isLow)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Contact Owner to top up your float', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showWithdrawDialog(isBoss: false),
                icon: const Icon(Icons.money_off_rounded),
                label: const Text('Withdraw'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('My Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildTransactionList(forBoss: false),
          ],
        );
      },
    );
  }

  // ─── TRANSACTIONS LIST ───────────────────────────────────────────────────────

  Widget _buildTransactionList({required bool forBoss}) {
    final uid = _auth.currentUser?.uid;
    final Stream<QuerySnapshot> stream;
    if (forBoss) {
      stream = _firestore
          .collection('float_transactions')
          .limit(100)
          .snapshots();
    } else {
      stream = _firestore
          .collection('float_transactions')
          .where('user_id', isEqualTo: uid)
          .limit(100)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No transactions yet', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                ],
              ),
            ),
          );
        }
        // Sort client-side by timestamp descending
        final sorted = docs.toList()
          ..sort((a, b) {
            final ta = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            final tb = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        return Column(
          children: sorted.map((doc) => _buildTransactionTile(doc.data() as Map<String, dynamic>)).toList(),
        );
      },
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final ts = d['timestamp'] as Timestamp?;
    final dateStr = ts != null ? DateFormat('MMM dd, yyyy HH:mm').format(ts.toDate()) : '';
    final userName = d['user_name'] as String? ?? '';
    final performedBy = d['performed_by_name'] as String? ?? '';
    final reason = d['reason'] as String? ?? '';
    final mobile = d['mobile_or_account'] as String? ?? '';
    final location = d['location'] as String? ?? '';
    final requestTitle = d['request_title'] as String? ?? '';
    final balanceAfter = (d['balance_after'] as num?)?.toDouble();

    Color color;
    IconData icon;
    String title;
    String subtitle;

    switch (type) {
      case 'credit':
        color = Colors.green;
        icon = Icons.add_circle_rounded;
        title = 'Float Added';
        subtitle = [
          if (userName.isNotEmpty) 'To: $userName',
          if (performedBy.isNotEmpty) 'By: $performedBy',
        ].join(' • ');
        break;
      case 'approval_deduction':
        color = Colors.blue;
        icon = Icons.check_circle_rounded;
        title = 'Request Approved${requestTitle.isNotEmpty ? ': $requestTitle' : ''}';
        subtitle = [
          if (location.isNotEmpty) 'Location: $location',
          if (userName.isNotEmpty) 'By: $userName',
        ].join(' • ');
        break;
      case 'withdrawal':
        color = Colors.orange;
        icon = Icons.money_off_rounded;
        title = 'Withdrawal${reason.isNotEmpty ? ': $reason' : ''}';
        subtitle = [
          if (mobile.isNotEmpty) 'To: $mobile',
          if (performedBy.isNotEmpty) 'By: $performedBy',
        ].join(' • ');
        break;
      default:
        color = Colors.grey;
        icon = Icons.receipt_rounded;
        title = type;
        subtitle = '';
    }

    final isDebit = type == 'approval_deduction' || type == 'withdrawal';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 2),
                  Text(dateStr, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isDebit ? '-' : '+'}TZS ${_fmt(amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDebit ? Colors.red[700] : Colors.green[700],
                  ),
                ),
                if (balanceAfter != null)
                  Text('Bal: ${_fmt(balanceAfter)}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── ADD FLOAT DIALOG ───────────────────────────────────────────────────────

  void _showAddFloatDialog() {
    String? selectedMdId;
    String? selectedMdName;
    double selectedMdCurrentBalance = 0;
    final amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.add_card_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 10),
            const Text('Add Float to MD'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('users').where('role', isEqualTo: 'md').snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const LinearProgressIndicator();
                  final mds = snap.data!.docs;
                  if (mds.isEmpty) return const Text('No MD users found');
                  return DropdownButtonFormField<String>(
                    value: selectedMdId,
                    decoration: const InputDecoration(
                      labelText: 'Select MD *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    items: mds.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final n = _resolveUserName(d);
                      return DropdownMenuItem(value: doc.id, child: Text(n));
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedMdId = val;
                        final doc = mds.firstWhere((d) => d.id == val);
                        final d = doc.data() as Map<String, dynamic>;
                        selectedMdName = _resolveUserName(d);
                        selectedMdCurrentBalance = (d['float_balance'] as num?)?.toDouble() ?? 0;
                      });
                    },
                  );
                },
              ),
              if (selectedMdId != null) ...[
                const SizedBox(height: 6),
                Text('Current balance: TZS ${_fmt(selectedMdCurrentBalance)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (TZS) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () async {
                if (selectedMdId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Please select an MD')));
                  return;
                }
                final amount = double.tryParse(amountCtrl.text.trim().replaceAll(',', ''));
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Enter a valid amount')));
                  return;
                }
                Navigator.pop(ctx);
                await _addFloatToMd(selectedMdId!, selectedMdName ?? 'MD', amount, selectedMdCurrentBalance);
              },
              icon: const Icon(Icons.check),
              label: const Text('Add Float'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFloatToMd(String mdId, String mdName, double amount, double currentBalance) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final newBalance = currentBalance + amount;
    try {
      final batch = _firestore.batch();
      batch.update(_firestore.collection('users').doc(mdId), {
        'float_balance': newBalance,
        'updated_at': FieldValue.serverTimestamp(),
      });
      // Fetch MD email for fallback display
      final mdDoc = await _firestore.collection('users').doc(mdId).get();
      final mdEmail = (mdDoc.data() as Map<String, dynamic>?)?['email'] as String? ?? '';
      batch.set(_firestore.collection('float_transactions').doc(), {
        'type': 'credit',
        'amount': amount,
        'user_id': mdId,
        'user_name': mdName,
        'user_email': mdEmail,
        'performed_by': currentUser.email,
        'performed_by_name': currentUser.displayName ?? currentUser.email,
        'balance_after': newBalance,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ TZS ${_fmt(amount)} added to $mdName\'s float'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  // ─── WITHDRAW DIALOG ────────────────────────────────────────────────────────

  void _showWithdrawDialog({required bool isBoss}) {
    final reasonCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.money_off_rounded, color: Colors.orange[700]),
          const SizedBox(width: 10),
          const Text('Withdraw'),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (TZS) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'e.g., Office supplies',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mobileCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account / Mobile Number *',
                  hintText: 'e.g., 0712345678',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim().replaceAll(',', ''));
              final reason = reasonCtrl.text.trim();
              final mobile = mobileCtrl.text.trim();
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Enter a valid amount')));
                return;
              }
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Enter a reason')));
                return;
              }
              if (mobile.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Enter account/mobile number')));
                return;
              }
              Navigator.pop(ctx);
              await _processWithdrawal(amount: amount, reason: reason, mobile: mobile, isBoss: isBoss);
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirm Withdrawal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processWithdrawal({
    required double amount,
    required String reason,
    required String mobile,
    required bool isBoss,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final uid = currentUser.uid;

    try {
      final batch = _firestore.batch();
      double? newBalance;

      if (!isBoss) {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final currentBalance = ((userDoc.data() as Map<String, dynamic>?)?['float_balance'] as num?)?.toDouble() ?? 0;
        if (amount > currentBalance) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Insufficient float. Balance: TZS ${_fmt(currentBalance)}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        newBalance = currentBalance - amount;
        batch.update(_firestore.collection('users').doc(uid), {
          'float_balance': newBalance,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      final userName = currentUser.displayName ?? currentUser.email ?? '';
      final txnRef = _firestore.collection('float_transactions').doc();
      final txnData = <String, dynamic>{
        'type': 'withdrawal',
        'amount': amount,
        'user_id': uid,
        'user_name': userName,
        'performed_by': currentUser.email,
        'performed_by_name': userName,
        'reason': reason,
        'mobile_or_account': mobile,
        'timestamp': FieldValue.serverTimestamp(),
      };
      if (newBalance != null) txnData['balance_after'] = newBalance;
      batch.set(txnRef, txnData);

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Withdrawal of TZS ${_fmt(amount)} recorded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  // Resolves user display name, handling empty strings
  String _resolveUserName(Map<String, dynamic> d) {
    final name = (d['name'] as String? ?? '').trim();
    if (name.isNotEmpty) return name;
    final displayName = (d['displayName'] as String? ?? '').trim();
    if (displayName.isNotEmpty) return displayName;
    return (d['email'] as String? ?? 'Unknown').trim();
  }

  String _fmt(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}
