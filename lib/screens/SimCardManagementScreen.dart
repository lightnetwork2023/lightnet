import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class SimCardManagementScreen extends StatefulWidget {
  const SimCardManagementScreen({super.key});

  @override
  State<SimCardManagementScreen> createState() => _SimCardManagementScreenState();
}

class _SimCardManagementScreenState extends State<SimCardManagementScreen> {
  final _searchController = TextEditingController();
  String _filterType = 'all';
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _simcardsStream() {
    return FirebaseFirestore.instance
        .collection('simcards')
        .orderBy('updated_at', descending: true)
        .snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final lower = _searchController.text.toLowerCase();
    return docs.where((d) {
      final data = d.data();
      if (_filterType != 'all' && (data['type'] ?? '') != _filterType) return false;
      if (lower.isEmpty) return true;
      final msisdn = (data['msisdn'] ?? '').toString().toLowerCase();
      final imsi = (data['imsi'] ?? '').toString().toLowerCase();
      final customer = (data['customer_name'] ?? '').toString().toLowerCase();
      final loc = (data['location'] ?? '').toString().toLowerCase();
      return msisdn.contains(lower) || imsi.contains(lower) || customer.contains(lower) || loc.contains(lower);
    }).toList();
  }

  Future<void> _exportToExcel() async {
    if (_exporting) return;

    setState(() => _exporting = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('simcards')
          .orderBy('updated_at', descending: true)
          .get();
      final filtered = _filterDocs(snap.docs);

      if (filtered.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No SIM cards to export')),
          );
        }
        return;
      }

      // Rename first, then write — writing before rename leaves data on an orphaned sheet.
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'SIM Cards');
      final sheet = excel['SIM Cards'];

      sheet.appendRow([
        TextCellValue('IMSI'),
        TextCellValue('Phone Number'),
      ]);

      for (final doc in filtered) {
        final data = doc.data();
        sheet.appendRow([
          TextCellValue((data['imsi'] ?? '').toString()),
          TextCellValue((data['msisdn'] ?? '').toString()),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to generate Excel file');
      }

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/simcards_$stamp.xlsx');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'SIM Cards export (IMSI & Phone Number)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${filtered.length} SIM card(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export Excel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showSimForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final formKey = GlobalKey<FormState>();
    String type = doc?.data()?['type'] ?? 'customer';
    String msisdn = doc?.data()?['msisdn'] ?? '';
    String imsi = doc?.data()?['imsi'] ?? '';
    String location = doc?.data()?['location'] ?? '';
    String customerName = doc?.data()?['customer_name'] ?? '';
    String speedLimitStr = (doc?.data()?['speed_limit_mbps']?.toString() ?? '');
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('SIM Card'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'customer', child: Text('Customer/User')),
                          DropdownMenuItem(value: 'company', child: Text('Company Use')),
                        ],
                        onChanged: (v) => setStateDialog(() => type = v ?? 'customer'),
                      ),
                      TextFormField(
                        initialValue: msisdn,
                        decoration: const InputDecoration(labelText: 'Phone Number (MSISDN)'),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        onChanged: (v) => msisdn = v.trim(),
                      ),
                      TextFormField(
                        initialValue: imsi,
                        decoration: const InputDecoration(labelText: 'IMSI'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        onChanged: (v) => imsi = v.trim(),
                      ),
                      TextFormField(
                        initialValue: location,
                        decoration: const InputDecoration(labelText: 'Location'),
                        onChanged: (v) => location = v.trim(),
                      ),
                      if (type == 'customer')
                        TextFormField(
                          initialValue: customerName,
                          decoration: const InputDecoration(labelText: 'Customer Name'),
                          onChanged: (v) => customerName = v.trim(),
                        ),
                      TextFormField(
                        initialValue: speedLimitStr,
                        decoration: const InputDecoration(labelText: 'Speed Limit (Mbps)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          return double.tryParse(v) == null ? 'Invalid number' : null;
                        },
                        onChanged: (v) => speedLimitStr = v.trim(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setStateDialog(() => saving = true);
                          try {
                            final msisdnQ = await FirebaseFirestore.instance
                                .collection('simcards')
                                .where('msisdn', isEqualTo: msisdn)
                                .get();
                            if (msisdnQ.docs.any((d) => d.id != doc?.id)) {
                              throw Exception('MSISDN already exists');
                            }
                            final imsiQ = await FirebaseFirestore.instance
                                .collection('simcards')
                                .where('imsi', isEqualTo: imsi)
                                .get();
                            if (imsiQ.docs.any((d) => d.id != doc?.id)) {
                              throw Exception('IMSI already exists');
                            }
                            final data = {
                              'type': type,
                              'msisdn': msisdn,
                              'imsi': imsi,
                              'location': location,
                              'customer_name': type == 'customer' ? customerName : null,
                              'speed_limit_mbps': speedLimitStr.isEmpty ? null : double.parse(speedLimitStr),
                              'updated_at': FieldValue.serverTimestamp(),
                              if (doc == null) 'created_at': FieldValue.serverTimestamp(),
                            };
                            if (doc == null) {
                              await FirebaseFirestore.instance.collection('simcards').add(data);
                            } else {
                              await FirebaseFirestore.instance.collection('simcards').doc(doc.id).set(data, SetOptions(merge: true));
                            }
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.errorColor),
                            );
                            setStateDialog(() => saving = false);
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete SIM'),
        content: const Text('Are you sure you want to delete this SIM?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('simcards').doc(doc.id).delete();
    }
  }

  Future<void> _showSimDetails(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};

    String _formatSpeed(dynamic value) {
      if (value == null) return '';
      return '${value.toString()} Mbps';
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(data['msisdn']?.toString() ?? 'SIM Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Type', (data['type'] ?? '').toString().toUpperCase()),
                _buildDetailRow('Phone Number', data['msisdn']?.toString() ?? ''),
                _buildDetailRow('IMSI', data['imsi']?.toString() ?? ''),
                _buildDetailRow('Customer Name', data['customer_name']?.toString() ?? ''),
                _buildDetailRow('Location', data['location']?.toString() ?? ''),
                _buildDetailRow('Speed Limit', _formatSpeed(data['speed_limit_mbps'])),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIM Cards'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.primaryGradient,
          ),
        ),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Export to Excel',
            onPressed: _exporting ? null : _exportToExcel,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final text = await showDialog<String>(
                context: context,
                builder: (context) {
                  final c = TextEditingController(text: _searchController.text);
                  return AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Search'),
                    content: TextField(
                      controller: c,
                      decoration: const InputDecoration(hintText: 'MSISDN, IMSI, Customer, Location'),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                      ElevatedButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Apply')),
                    ],
                  );
                },
              );
              if (text != null) {
                setState(() => _searchController.text = text);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            initialValue: _filterType,
            onSelected: (v) => setState(() => _filterType = v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'all', child: Text('All')),
              PopupMenuItem(value: 'customer', child: Text('Customer/User')),
              PopupMenuItem(value: 'company', child: Text('Company Use')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _simcardsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          final filtered = _filterDocs(docs);

          if (filtered.isEmpty) {
            return const Center(child: Text('No SIM cards found'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final doc = filtered[index];
              final data = doc.data();
              final type = (data['type'] ?? '').toString();
              final isCompany = type == 'company';
              final msisdn = (data['msisdn'] ?? '').toString();
              final location = (data['location'] ?? '').toString();
              final customerName = (data['customer_name'] ?? '').toString();
              
              return ModernCard(
                onTap: () => _showSimDetails(doc),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: isCompany 
                                ? LinearGradient(
                                    colors: [AppTheme.infoColor, AppTheme.infoColor.withOpacity(0.7)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : AppGradients.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: (isCompany ? AppTheme.infoColor : AppTheme.primaryColor).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.sim_card_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        msisdn,
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isCompany 
                                          ? AppTheme.infoColor.withOpacity(0.15)
                                          : AppTheme.primaryColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        type.toUpperCase(),
                                        style: TextStyle(
                                          color: isCompany ? AppTheme.infoColor : AppTheme.primaryColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (customerName.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline_rounded,
                                        size: 16,
                                        color: AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          customerName,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                if (location.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 16,
                                        color: AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          location,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.textTertiary.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.more_vert_rounded,
                                color: AppTheme.textSecondary,
                                size: 18,
                              ),
                            ),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showSimForm(doc: doc);
                              } else if (value == 'delete') {
                                _confirmDelete(doc);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18, color: AppTheme.textSecondary),
                                    const SizedBox(width: 12),
                                    const Text('Edit'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.errorColor),
                                    const SizedBox(width: 12),
                                    Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
                                  ],
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
          );
        },
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showSimForm(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add SIM Card',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
