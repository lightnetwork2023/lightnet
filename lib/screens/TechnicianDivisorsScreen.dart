import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class TechnicianDivisorsScreen extends StatefulWidget {
  const TechnicianDivisorsScreen({super.key});

  @override
  State<TechnicianDivisorsScreen> createState() => _TechnicianDivisorsScreenState();
}

class _TechnicianDivisorsScreenState extends State<TechnicianDivisorsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all | flagged | unset
  late final Stream<QuerySnapshot> _techStream;

  @override
  void initState() {
    super.initState();
    _techStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'technician')
        .snapshots();
  }

  static const double _defaultDivisor = 30000.0;

  double _readDivisor(Map<String, dynamic> d) {
    final raw = d['commission_divisor'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? _defaultDivisor;
    return _defaultDivisor;
  }

  bool _isFlagged(double v) => v < 1000;
  bool _isUnset(Map<String, dynamic> d) => d['commission_divisor'] == null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Technician Divisors'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.deepPurple.withOpacity(0.05),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search technician name or email…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _filterChip('All', 'all'),
                  const SizedBox(width: 6),
                  _filterChip('Flagged (<1000)', 'flagged', color: Colors.red),
                  const SizedBox(width: 6),
                  _filterChip('Unset', 'unset', color: Colors.orange),
                ]),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _techStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? [];

                // Filter + search
                final filtered = docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final divisor = _readDivisor(d);

                  if (_filter == 'flagged' && !_isFlagged(divisor)) return false;
                  if (_filter == 'unset' && !_isUnset(d)) return false;

                  if (_query.isEmpty) return true;
                  final name = (d['name'] ?? '').toString().toLowerCase();
                  final email = (d['email'] ?? '').toString().toLowerCase();
                  return name.contains(_query) || email.contains(_query);
                }).toList();

                final flaggedCount = docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return _isFlagged(_readDivisor(d));
                }).length;
                final unsetCount = docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return _isUnset(d);
                }).length;

                return Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Colors.grey[100],
                    child: Row(children: [
                      _summaryBox('Total', docs.length.toString(), Colors.blueGrey),
                      const SizedBox(width: 8),
                      _summaryBox('Flagged', flaggedCount.toString(), Colors.red),
                      const SizedBox(width: 8),
                      _summaryBox('Unset', unsetCount.toString(), Colors.orange),
                      const Spacer(),
                      Text('${filtered.length} shown',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ),
                  if (filtered.isEmpty)
                    const Expanded(
                      child: Center(child: Text('No technicians match the filter', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _TechRow(
                          doc: filtered[i],
                          onEdit: () => _showQuickEdit(filtered[i]),
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, {Color? color}) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: (color ?? Colors.deepPurple).withOpacity(0.25),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _summaryBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
        const SizedBox(width: 6),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  void _showQuickEdit(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final name = (d['name'] ?? d['email'] ?? 'Technician').toString();
    final current = _readDivisor(d);
    final initial = current.toStringAsFixed(0);
    final ctrl = TextEditingController(text: initial);
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final v = double.tryParse(ctrl.text.trim()) ?? 0;
        return AlertDialog(
          title: Text('Edit: $name', style: const TextStyle(fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(
                labelText: 'Divisor',
                prefixIcon: const Icon(Icons.functions_rounded),
                helperText: 'Saved: ${current.toStringAsFixed(0)}',
                border: const OutlineInputBorder(),
              ),
            ),
            if (v > 0 && v < 1000) ...[
              const SizedBox(height: 8),
              Text(
                '⚠ Very low divisor. Did you mean ${(v * 1000).toStringAsFixed(0)}?',
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final p in [10000.0, 20000.0, 30000.0, 50000.0])
                ActionChip(
                  label: Text(p.toStringAsFixed(0)),
                  onPressed: () {
                    ctrl.text = p.toStringAsFixed(0);
                    setLocal(() {});
                  },
                ),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              onPressed: () async {
                if (v <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Enter a valid positive number')),
                  );
                  return;
                }
                final auth = Get.isRegistered<AuthController>() ? Get.find<AuthController>() : null;
                try {
                  await doc.reference.update({
                    'commission_divisor': v,
                    'commission_divisor_updated_at': FieldValue.serverTimestamp(),
                    'commission_divisor_updated_by': auth?.user?.uid,
                  });
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Updated $name → ${v.toStringAsFixed(0)}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }
}

class _TechRow extends StatelessWidget {
  final DocumentSnapshot doc;
  final VoidCallback onEdit;
  const _TechRow({required this.doc, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final name = (d['name'] ?? '').toString();
    final email = (d['email'] ?? '').toString();
    final raw = d['commission_divisor'];
    double? divisor;
    if (raw is num) divisor = raw.toDouble();
    if (raw is String) divisor = double.tryParse(raw);

    final isUnset = raw == null;
    final isFlagged = divisor != null && divisor < 1000;
    final updatedAt = d['commission_divisor_updated_at'] as Timestamp?;

    Color badgeColor = Colors.green;
    String badgeText = '÷${divisor?.toStringAsFixed(0) ?? '?'}';
    if (isUnset) {
      badgeColor = Colors.orange;
      badgeText = 'UNSET';
    } else if (isFlagged) {
      badgeColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: (isFlagged || isUnset) ? badgeColor.withOpacity(0.5) : Colors.transparent),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeColor.withOpacity(0.15),
          child: Icon(
            isUnset ? Icons.help_outline_rounded : (isFlagged ? Icons.warning_amber_rounded : Icons.check_circle_outline),
            color: badgeColor,
          ),
        ),
        title: Text(name.isEmpty ? email : name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty) Text(email, style: const TextStyle(fontSize: 11)),
            if (updatedAt != null)
              Text('Updated: ${_fmtTs(updatedAt)}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            if (isFlagged && divisor != null)
              Text('Commission per 300k = ${(300000 / divisor).toStringAsFixed(0)} TZS  ⚠',
                  style: const TextStyle(fontSize: 10, color: Colors.red)),
          ],
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badgeText,
              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 20, color: Colors.deepPurple),
            onPressed: onEdit,
          ),
        ]),
        onTap: onEdit,
      ),
    );
  }

  String _fmtTs(Timestamp ts) {
    final d = ts.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
