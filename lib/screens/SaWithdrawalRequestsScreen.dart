import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class SaWithdrawalRequestsScreen extends StatefulWidget {
  const SaWithdrawalRequestsScreen({super.key});

  @override
  State<SaWithdrawalRequestsScreen> createState() =>
      _SaWithdrawalRequestsScreenState();
}

class _SaWithdrawalRequestsScreenState
    extends State<SaWithdrawalRequestsScreen> {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  String _filter = 'pending';

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _fmt(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},');

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  // ─── Approval Flow ──────────────────────────────────────────────────────────

  Future<void> _showApprovalDialog(
      BuildContext ctx, String docId, Map<String, dynamic> req) async {
    File? evidenceFile;
    bool uploading = false;
    final picker = ImagePicker();

    await showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Withdrawal',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Request summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(req['user_name'] as String? ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        'TZS ${_fmt((req['amount'] as num?)?.toDouble() ?? 0)}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                      const SizedBox(height: 4),
                      Text('To: ${req['account_name'] ?? ''}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Account/Mobile: ${req['mobile_or_account'] ?? ''}',
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Upload Payment Evidence *',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final img = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80);
                          if (img != null) {
                            setDState(() => evidenceFile = File(img.path));
                          }
                        },
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Gallery'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final img = await picker.pickImage(
                              source: ImageSource.camera,
                              imageQuality: 80);
                          if (img != null) {
                            setDState(() => evidenceFile = File(img.path));
                          }
                        },
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('Camera'),
                      ),
                    ),
                  ],
                ),
                if (evidenceFile != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(evidenceFile!,
                        height: 140, width: double.infinity, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 4),
                  const Text('✅ Evidence selected',
                      style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
                if (uploading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  const Text('Uploading evidence & processing…',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white),
              onPressed: (uploading || evidenceFile == null)
                  ? null
                  : () async {
                      setDState(() => uploading = true);
                      try {
                        // Upload evidence to Firebase Storage
                        final ext = evidenceFile!.path.split('.').last;
                        final ref = _storage.ref(
                            'sa_withdrawal_evidence/$docId.$ext');
                        await ref.putFile(evidenceFile!);
                        final evidenceUrl = await ref.getDownloadURL();

                        final currentUser =
                            FirebaseAuth.instance.currentUser;
                        final saId = req['user_id'] as String? ?? '';
                        final amount =
                            (req['amount'] as num?)?.toDouble() ?? 0;

                        // Batch: approve request + deduct from SA balance
                        final batch = _db.batch();
                        batch.update(
                            _db
                                .collection('sa_withdrawal_requests')
                                .doc(docId),
                            {
                              'status': 'approved',
                              'evidence_url': evidenceUrl,
                              'approved_at':
                                  FieldValue.serverTimestamp(),
                              'approved_by':
                                  currentUser?.email ?? '',
                            });
                        if (saId.isNotEmpty) {
                          batch.update(
                              _db.collection('users').doc(saId),
                              {
                                'withdrawable_balance':
                                    FieldValue.increment(-amount),
                              });
                        }
                        await batch.commit();

                        if (mounted) Navigator.pop(dCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Withdrawal approved'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDState(() => uploading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('❌ Error: $e')),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Approve & Send Evidence'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectRequest(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Withdrawal'),
        content:
            const Text('Are you sure you want to reject this request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _db.collection('sa_withdrawal_requests').doc(docId).update({
      'status': 'rejected',
      'rejected_at': FieldValue.serverTimestamp(),
      'rejected_by': FirebaseAuth.instance.currentUser?.email ?? '',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Query query = _db.collection('sa_withdrawal_requests');
    if (_filter != 'all') {
      query = query.where('status', isEqualTo: _filter);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SA Withdrawals',
            style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'pending',
                  child: Row(children: [
                    Icon(Icons.hourglass_top_rounded, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Pending')
                  ])),
              PopupMenuItem(
                  value: 'approved',
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Approved')
                  ])),
              PopupMenuItem(
                  value: 'rejected',
                  child: Row(children: [
                    Icon(Icons.cancel_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Rejected')
                  ])),
              PopupMenuItem(
                  value: 'all',
                  child: Row(children: [
                    Icon(Icons.list_rounded, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('All')
                  ])),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          // Sort client-side: newest first
          final sorted = docs.toList()
            ..sort((a, b) {
              final ta = (a.data() as Map)['created_at'] as Timestamp?;
              final tb = (b.data() as Map)['created_at'] as Timestamp?;
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });

          if (sorted.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No ${_filter == 'all' ? '' : _filter} withdrawal requests',
                    style: TextStyle(color: Colors.grey[500], fontSize: 15),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (ctx, i) {
              final doc = sorted[i];
              final d = doc.data() as Map<String, dynamic>;
              final status = d['status'] as String? ?? 'pending';
              final amount = (d['amount'] as num?)?.toDouble() ?? 0;
              final ts = d['created_at'] as Timestamp?;
              final dateStr = ts != null
                  ? DateFormat('dd MMM yyyy, HH:mm').format(ts.toDate())
                  : '';
              final evidenceUrl = d['evidence_url'] as String?;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                      color: _statusColor(status).withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                _statusColor(status).withOpacity(0.12),
                            child: Icon(_statusIcon(status),
                                color: _statusColor(status), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['user_name'] as String? ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                Text(dateStr,
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      // Amount
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Amount',
                              style: TextStyle(color: Colors.grey)),
                          Text(
                            'TZS ${_fmt(amount)}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Account details
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(d['account_name'] as String? ?? '',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.phone_android_rounded,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(d['mobile_or_account'] as String? ?? '',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      // Evidence image (if approved)
                      if (evidenceUrl != null && evidenceUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Payment Evidence',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: Colors.grey)),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showEvidenceFullscreen(evidenceUrl),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              evidenceUrl,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : const SizedBox(
                                          height: 120,
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator())),
                              errorBuilder: (_, __, ___) => Container(
                                height: 120,
                                color: Colors.grey[200],
                                child: const Center(
                                    child:
                                        Icon(Icons.broken_image, size: 40)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Approved by: ${d['approved_by'] ?? ''}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                      // Action buttons (pending only)
                      if (status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(
                                        color: Colors.red)),
                                onPressed: () => _rejectRequest(doc.id),
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                                label: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white),
                                onPressed: () =>
                                    _showApprovalDialog(context, doc.id, d),
                                icon: const Icon(Icons.check_rounded,
                                    size: 18),
                                label: const Text('Approve + Evidence'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEvidenceFullscreen(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(url),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
