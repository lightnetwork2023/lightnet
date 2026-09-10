import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class DevicesInStoreScreen extends StatefulWidget {
  const DevicesInStoreScreen({Key? key}) : super(key: key);

  @override
  State<DevicesInStoreScreen> createState() => _DevicesInStoreScreenState();
}

class _DevicesInStoreScreenState extends State<DevicesInStoreScreen> {
  static const _col = 'devices_in_store';
  final _db = FirebaseFirestore.instance;

  String _search = '';
  String _filterType = 'all';

  static const List<Map<String, String>> _deviceTypes = [
    {'value': 'router', 'label': 'Router'},
    {'value': 'mikrotik', 'label': 'MikroTik'},
    {'value': 'unifi_ap', 'label': 'UniFi AP'},
    {'value': 'sim_card', 'label': 'SIM Card'},
    {'value': 'switch', 'label': 'Switch'},
    {'value': 'cable', 'label': 'Cable / Wire'},
    {'value': 'antenna', 'label': 'Antenna'},
    {'value': 'dish', 'label': 'Dish'},
    {'value': 'nokia', 'label': 'Nokia'},
    {'value': 'other', 'label': 'Other'},
  ];

  static String _labelFor(String value) =>
      _deviceTypes.firstWhere((t) => t['value'] == value,
          orElse: () => {'label': value})['label']!;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() =>
      _db.collection(_col).snapshots();

  Future<void> _showForm(
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final formKey = GlobalKey<FormState>();
    String type = doc?.data()?['type'] ?? 'router';
    final modelCtrl =
        TextEditingController(text: doc?.data()?['model'] ?? '');
    final serialCtrl =
        TextEditingController(text: doc?.data()?['serial_number'] ?? '');
    final qtyCtrl = TextEditingController(
        text: (doc?.data()?['quantity'] ?? 1).toString());
    final notesCtrl =
        TextEditingController(text: doc?.data()?['notes'] ?? '');
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:
              Text(doc == null ? 'Add Device to Store' : 'Edit Store Device'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(
                        labelText: 'Device Type',
                        border: OutlineInputBorder()),
                    items: _deviceTypes
                        .map((t) => DropdownMenuItem(
                            value: t['value'], child: Text(t['label']!)))
                        .toList(),
                    onChanged: (v) => setSt(() => type = v ?? 'router'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Model / Name',
                        border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: serialCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Serial Number (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder()),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (int.tryParse(v.trim()) == null ||
                          int.parse(v.trim()) < 1)
                        return 'Enter a valid number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () {
                      modelCtrl.dispose();
                      serialCtrl.dispose();
                      qtyCtrl.dispose();
                      notesCtrl.dispose();
                      Navigator.pop(ctx);
                    },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setSt(() => saving = true);
                      final data = {
                        'type': type,
                        'model': modelCtrl.text.trim(),
                        'serial_number': serialCtrl.text.trim(),
                        'quantity': int.parse(qtyCtrl.text.trim()),
                        'notes': notesCtrl.text.trim(),
                        'updated_at': FieldValue.serverTimestamp(),
                      };
                      if (doc == null) {
                        data['added_at'] = FieldValue.serverTimestamp();
                        await _db.collection(_col).add(data);
                      } else {
                        await doc.reference.update(data);
                      }
                      modelCtrl.dispose();
                      serialCtrl.dispose();
                      qtyCtrl.dispose();
                      notesCtrl.dispose();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(doc == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from Store'),
        content: const Text('Delete this device from store records?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices in Store'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by model, type…',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _chip('all', 'All'),
                ..._deviceTypes
                    .map((t) => _chip(t['value']!, t['label']!)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                var docs = snap.data?.docs ?? [];
                docs.sort((a, b) {
                  final aTs = a.data()['added_at'];
                  final bTs = b.data()['added_at'];
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return (bTs as Timestamp).compareTo(aTs as Timestamp);
                });
                if (_filterType != 'all') {
                  docs = docs
                      .where((d) => d.data()['type'] == _filterType)
                      .toList();
                }
                if (_search.isNotEmpty) {
                  docs = docs.where((d) {
                    final model =
                        (d.data()['model'] as String? ?? '').toLowerCase();
                    final type =
                        (d.data()['type'] as String? ?? '').toLowerCase();
                    final serial = (d.data()['serial_number'] as String? ?? '')
                        .toLowerCase();
                    return model.contains(_search) ||
                        type.contains(_search) ||
                        serial.contains(_search);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No devices in store',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 6),
                        Text('Tap + to add a device',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                // Summary totals
                final totalQty = docs.fold<int>(
                    0, (sum, d) => sum + ((d.data()['quantity'] as int?) ?? 1));

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.primaryColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2,
                              color: AppTheme.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${docs.length} device type${docs.length == 1 ? '' : 's'}  •  $totalQty unit${totalQty == 1 ? '' : 's'} in stock',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final d = docs[i];
                          final data = d.data();
                          final type = data['type'] as String? ?? '';
                          final model = data['model'] as String? ?? '';
                          final serial =
                              data['serial_number'] as String? ?? '';
                          final qty =
                              (data['quantity'] as int?) ?? 1;
                          final notes = data['notes'] as String? ?? '';
                          final ts = data['added_at'] as Timestamp?;
                          final dateStr = ts != null
                              ? DateFormat('dd MMM yyyy')
                                  .format(ts.toDate())
                              : '';

                          return Card(
                            elevation: 2,
                            margin:
                                const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor
                                          .withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                        Icons.devices_other,
                                        color: AppTheme.primaryColor,
                                        size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(model,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 15)),
                                        const SizedBox(height: 2),
                                        Text(_labelFor(type),
                                            style: TextStyle(
                                                color: AppTheme
                                                    .primaryColor,
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w600)),
                                        if (serial.isNotEmpty)
                                          Text('S/N: $serial',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey)),
                                        if (notes.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets
                                                .only(top: 4),
                                            child: Text(notes,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey)),
                                          ),
                                        if (dateStr.isNotEmpty)
                                          Text('Added: $dateStr',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: 10,
                                            vertical: 4),
                                        decoration: BoxDecoration(
                                          color: qty > 0
                                              ? Colors.green.shade50
                                              : Colors.red.shade50,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  8),
                                          border: Border.all(
                                            color: qty > 0
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                        child: Text(
                                          'Qty: $qty',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: qty > 0
                                                ? Colors.green.shade700
                                                : Colors.red,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: () =>
                                                _showForm(doc: d),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    6),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.edit,
                                                  size: 18,
                                                  color: Colors.blueGrey),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            onTap: () => _delete(d),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    6),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.delete_outline,
                                                  size: 18,
                                                  color: Colors.red),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final selected = _filterType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppTheme.primaryColor,
        labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.black87, fontSize: 12),
        onSelected: (_) => setState(() => _filterType = value),
      ),
    );
  }
}
