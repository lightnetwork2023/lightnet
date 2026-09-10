import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/auth_controller.dart';
import '../controllers/location_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class InternetPaymentsScreen extends StatefulWidget {
  const InternetPaymentsScreen({Key? key}) : super(key: key);

  @override
  State<InternetPaymentsScreen> createState() => _InternetPaymentsScreenState();
}

class _InternetPaymentsScreenState extends State<InternetPaymentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _auth = Get.find<AuthController>();
  final _locationController = Get.find<LocationController>();

  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _history = [];
  bool _loadingSubs = true;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSubscriptions();
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── helpers ──────────────────────────────────────────────────────────────

  bool _isConfirmedThisMonth(Map<String, dynamic> sub) {
    final raw = sub['last_confirmed_date'];
    if (raw == null) return false;
    final dt = (raw is Timestamp) ? raw.toDate() : null;
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month;
  }

  /// 'paid' | 'due_soon' | 'overdue' | 'upcoming'
  String _status(Map<String, dynamic> sub) {
    if (_isConfirmedThisMonth(sub)) return 'paid';
    final dueDay = (sub['due_day'] as num?)?.toInt() ?? 1;
    final today = DateTime.now().day;
    final diff = dueDay - today;
    if (diff < 0) return 'overdue';
    if (diff <= 3) return 'due_soon';
    return 'upcoming';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':     return Colors.green;
      case 'due_soon': return Colors.orange;
      case 'overdue':  return Colors.red;
      default:         return Colors.blue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'paid':     return 'Paid';
      case 'due_soon': return 'Due Soon';
      case 'overdue':  return 'Overdue';
      default:         return 'Upcoming';
    }
  }

  // ─── data ──────────────────────────────────────────────────────────────────

  Future<void> _loadSubscriptions() async {
    setState(() => _loadingSubs = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('internet_payments')
          .orderBy('location')
          .get();
      _subscriptions = snap.docs
          .map((d) => {'_id': d.id, ...d.data()})
          .toList();
    } catch (e) {
      debugPrint('InternetPayments load error: $e');
    } finally {
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('internet_payment_history')
          .orderBy('confirmed_at', descending: true)
          .limit(100)
          .get();
      _history = snap.docs
          .map((d) => {'_id': d.id, ...d.data()})
          .toList();
    } catch (e) {
      debugPrint('InternetPayments history error: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _confirmPayment(Map<String, dynamic> sub) async {
    // ── Require SMS/transaction evidence before confirming ──────────────
    final smsCtrl     = TextEditingController();
    final amtCtrl     = TextEditingController(
        text: (sub['monthly_amount'] ?? 0).toString());
    final notesCtrl   = TextEditingController();
    bool dialogSaving = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.sms_outlined, color: Colors.green.shade700, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Payment Evidence', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter the SMS or transaction reference received as proof of payment.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: smsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'SMS / Transaction Reference *',
                    hintText: 'Paste the payment confirmation SMS or Ref No.',
                    prefixIcon: const Icon(Icons.message_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount Paid (TZS) *',
                    prefixIcon: const Icon(Icons.attach_money_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: const Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: dialogSaving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: dialogSaving
                  ? null
                  : () {
                      if (smsCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('SMS / Reference is required'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      if (amtCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Amount paid is required'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final now = DateTime.now();
    final monthYear = DateFormat('yyyy-MM').format(now);
    final userName = _auth.userName;
    final docId = sub['_id'] as String;
    try {
      await FirebaseFirestore.instance
          .collection('internet_payments')
          .doc(docId)
          .update({
        'last_confirmed_date': FieldValue.serverTimestamp(),
        'confirmed_by': userName,
      });
      await FirebaseFirestore.instance
          .collection('internet_payment_history')
          .add({
        'payment_id': docId,
        'location': sub['location'] ?? '',
        'provider': sub['provider'] ?? '',
        'package_mbps': sub['package_mbps'] ?? 0,
        'due_day': sub['due_day'] ?? 1,
        'account_number': sub['account_number'] ?? '',
        'confirmed_at': FieldValue.serverTimestamp(),
        'confirmed_by': userName,
        'month_year': monthYear,
        'amount_paid': double.tryParse(amtCtrl.text.trim()) ?? 0,
        'sms_reference': smsCtrl.text.trim(),
        if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
      });
      await _loadSubscriptions();
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment confirmed for ${sub['location']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSubscription(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Subscription'),
        content: const Text('Remove this internet payment entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('internet_payments')
          .doc(docId)
          .delete();
      _loadSubscriptions();
    }
  }

  // ─── add / edit dialog ─────────────────────────────────────────────────────

  void _showAddEditDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final locations = _locationController.locations;

    String selectedLocation = isEdit ? (existing['location'] as String? ?? 'General') : 'General';
    final providerCtrl = TextEditingController(text: isEdit ? existing['provider']?.toString() : '');
    final mbpsCtrl     = TextEditingController(text: isEdit ? existing['package_mbps']?.toString() : '');
    final dueDayCtrl   = TextEditingController(text: isEdit ? existing['due_day']?.toString() : '');
    final accountCtrl  = TextEditingController(text: isEdit ? existing['account_number']?.toString() : '');
    final regNumCtrl   = TextEditingController(text: isEdit ? existing['registration_number']?.toString() : '');
    final amountCtrl   = TextEditingController(text: isEdit ? existing['monthly_amount']?.toString() : '');
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.wifi_rounded, color: Colors.blue.shade700, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isEdit ? 'Edit Subscription' : 'Add Internet Payment',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Location dropdown
                  DropdownButtonFormField<String>(
                    value: selectedLocation,
                    decoration: InputDecoration(
                      labelText: 'Location / Site',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'General',
                        child: Text('— General (No specific location) —'),
                      ),
                      ...locations.map((l) => DropdownMenuItem(value: l, child: Text(l))),
                    ],
                    onChanged: (v) => setD(() => selectedLocation = v ?? 'General'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Select General if this internet is not tied to a specific site',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: providerCtrl,
                    decoration: InputDecoration(
                      labelText: 'Provider (e.g. TTCL, Liquid)',
                      prefixIcon: const Icon(Icons.business_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: mbpsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Package (Mbps)',
                      prefixIcon: const Icon(Icons.speed_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: dueDayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Payment Due Day (1–31)',
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: accountCtrl,
                    decoration: InputDecoration(
                      labelText: 'Account / Control Number',
                      prefixIcon: const Icon(Icons.tag_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: regNumCtrl,
                    decoration: InputDecoration(
                      labelText: 'Registration Number (optional)',
                      prefixIcon: const Icon(Icons.confirmation_number_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monthly Amount (TZS)',
                      prefixIcon: const Icon(Icons.attach_money_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (providerCtrl.text.trim().isEmpty ||
                                      dueDayCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Fill required fields')),
                                    );
                                    return;
                                  }
                                  final dueDay = int.tryParse(dueDayCtrl.text.trim()) ?? 1;
                                  if (dueDay < 1 || dueDay > 31) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Due day must be 1–31')),
                                    );
                                    return;
                                  }
                                  setD(() => saving = true);
                                  final data = {
                                    'location': selectedLocation,
                                    'is_general': selectedLocation == 'General',
                                    'provider': providerCtrl.text.trim(),
                                    'package_mbps': double.tryParse(mbpsCtrl.text.trim()) ?? 0,
                                    'due_day': dueDay,
                                    'account_number': accountCtrl.text.trim(),
                                    'registration_number': regNumCtrl.text.trim(),
                                    'monthly_amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
                                  };
                                  try {
                                    if (isEdit) {
                                      await FirebaseFirestore.instance
                                          .collection('internet_payments')
                                          .doc(existing['_id'] as String)
                                          .update(data);
                                    } else {
                                      data['created_at'] = FieldValue.serverTimestamp();
                                      data['created_by'] = _auth.userName;
                                      await FirebaseFirestore.instance
                                          .collection('internet_payments')
                                          .add(data);
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _loadSubscriptions();
                                  } catch (e) {
                                    setD(() => saving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: saving
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(isEdit ? 'Update' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── build ─────────────────────────────────────────────────────────────────

  Widget _buildSubscriptionCard(Map<String, dynamic> sub) {
    final status = _status(sub);
    final color  = _statusColor(status);
    final label  = _statusLabel(status);
    final dueDay = (sub['due_day'] as num?)?.toInt() ?? 1;
    final isPaid = status == 'paid';
    final locLabel = (sub['location'] == null || sub['location'].toString().isEmpty)
        ? 'General'
        : sub['location'].toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.wifi_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            locLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          if (locLabel == 'General') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('General', style: TextStyle(fontSize: 10, color: Colors.purple.shade700)),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${sub['provider'] ?? '—'}  •  ${sub['package_mbps'] ?? 0} Mbps',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      if ((sub['monthly_amount'] ?? 0) > 0) ...
                        [
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.attach_money_outlined,
                                  size: 13, color: Colors.green.shade700),
                              Text(
                                'TZS ${sub['monthly_amount']}/month',
                                style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Due: day $dueDay each month', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.tag_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    sub['account_number']?.toString().isEmpty ?? true ? '—' : sub['account_number'].toString(),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if ((sub['registration_number']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Reg: ${sub['registration_number']}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
            if (!isPaid) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmPayment(sub),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Confirm Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
            if (isPaid) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Confirmed by ${sub['confirmed_by'] ?? '—'}',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                    onPressed: () => _showAddEditDialog(existing: sub),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    onPressed: () => _deleteSubscription(sub['_id'] as String),
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> h) {
    DateTime? confirmedAt;
    final raw = h['confirmed_at'];
    if (raw is Timestamp) confirmedAt = raw.toDate();
    final dateStr = confirmedAt != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(confirmedAt)
        : '—';

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.check_rounded, color: Colors.green.shade700, size: 20),
      ),
      title: Text(
        '${h['location'] ?? '—'} — ${h['provider'] ?? '—'}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${h['package_mbps'] ?? 0} Mbps  •  ${h['month_year'] ?? '—'}${(h['amount_paid'] ?? 0) > 0 ? '  •  TZS ${h['amount_paid']}' : ''}\nConfirmed: $dateStr by ${h['confirmed_by'] ?? '—'}${(h['sms_reference'] ?? '').toString().isNotEmpty ? '\nRef: ${h['sms_reference']}' : ''}',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      isThreeLine: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Internet Payments',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              _loadSubscriptions();
              _loadHistory();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.wifi_rounded), text: 'Subscriptions'),
            Tab(icon: Icon(Icons.history_rounded), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Subscriptions ──
          _loadingSubs
              ? const ModernLoading(message: 'Loading subscriptions...')
              : _subscriptions.isEmpty
                  ? const EmptyState(
                      icon: Icons.wifi_off_rounded,
                      title: 'No Subscriptions',
                      subtitle: 'Tap + to add an internet payment entry',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSubscriptions,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _subscriptions.length,
                        itemBuilder: (_, i) => _buildSubscriptionCard(_subscriptions[i]),
                      ),
                    ),
          // ── History ──
          _loadingHistory
              ? const ModernLoading(message: 'Loading history...')
              : _history.isEmpty
                  ? const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No History Yet',
                      subtitle: 'Confirmed payments will appear here',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _history.length,
                        itemBuilder: (_, i) => _buildHistoryTile(_history[i]),
                      ),
                    ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEditDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Subscription'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}
