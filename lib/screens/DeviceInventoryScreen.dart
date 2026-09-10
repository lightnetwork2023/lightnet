import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/FieldRegistrationService.dart';
import '../theme/app_theme.dart';
import 'FieldDetailsScreen.dart';

class DeviceInventoryScreen extends StatefulWidget {
  const DeviceInventoryScreen({Key? key}) : super(key: key);

  @override
  State<DeviceInventoryScreen> createState() => _DeviceInventoryScreenState();
}

class _DeviceInventoryScreenState extends State<DeviceInventoryScreen> {
  String _searchQuery = '';
  String _filterType = 'all';
  final TextEditingController _searchCtrl = TextEditingController();

  static const _typeFilters = [
    {'value': 'all',             'label': 'All Devices'},
    {'value': 'sim_card_router', 'label': 'SIM Card Router'},
    {'value': 'mikrotik',        'label': 'MikroTik'},
    {'value': 'nokia',           'label': 'Nokia'},
    {'value': 'other_router',    'label': 'Other Router'},
    {'value': 'access_point',    'label': 'Access Point'},
    {'value': 'dish_receiver',           'label': 'Dish Receiver'},
    {'value': 'link',                    'label': 'Link'},
    {'value': 'omnidirectional_antenna', 'label': 'Omni Antenna'},
    {'value': 'sector_antenna',          'label': 'Sector Antenna'},
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _flattenEquipment(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final flat = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final data = doc.data();
      final equipment =
          (data['equipment'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final eq in equipment) {
        flat.add({
          ...eq,
          'reg_id': doc.id,
          'owner_id': data['owner_id'] ?? '',
          'owner_name': data['owner_name'] ?? '',
          'owner_role': data['owner_role'] ?? '',
          'location': data['location'] ?? '',
          'physical_location': data['physical_location'] ?? '',
          'client_name': data['client_name'] ?? '',
          'latitude': data['latitude'],
          'longitude': data['longitude'],
        });
      }
    }
    return flat;
  }

  List<Map<String, dynamic>> _applyFilters(
      List<Map<String, dynamic>> items) {
    var result = items;

    if (_filterType != 'all') {
      result =
          result.where((i) => i['type'] == _filterType).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((i) {
        final serial = (i['serial_number'] as String? ?? '').toLowerCase();
        final model = (i['model'] as String? ?? '').toLowerCase();
        final sim = (i['sim_card_number'] as String? ?? '').toLowerCase();
        final owner = (i['owner_name'] as String? ?? '').toLowerCase();
        final client = (i['client_name'] as String? ?? '').toLowerCase();
        final loc = (i['location'] as String? ?? '').toLowerCase();
        final physLoc = (i['physical_location'] as String? ?? '').toLowerCase();
        final devName = (i['device_name'] as String? ?? '').toLowerCase();
        return serial.contains(q) ||
            model.contains(q) ||
            sim.contains(q) ||
            owner.contains(q) ||
            client.contains(q) ||
            loc.contains(q) ||
            physLoc.contains(q) ||
            devName.contains(q);
      }).toList();
    }

    return result;
  }

  Map<String, int> _countByType(List<Map<String, dynamic>> items) {
    final counts = <String, int>{};
    for (final i in items) {
      final t = i['type'] as String? ?? 'unknown';
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Inventory'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FieldRegistrationService.streamAll(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          final allItems = _flattenEquipment(docs);
          final filtered = _applyFilters(allItems);
          final counts = _countByType(allItems);

          return Column(
            children: [
              // ── Summary cards ──────────────────────────────────────
              Container(
                color: Colors.grey.shade50,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Total Devices: ${allItems.length}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    SizedBox(
                      height: 64,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: EquipmentMeta.types.map((t) {
                          final type = t['type'] as String;
                          final count = counts[type] ?? 0;
                          if (count == 0) return const SizedBox.shrink();
                          return _SummaryChip(
                            icon: t['icon'] as IconData,
                            label: t['label'] as String,
                            count: count,
                            selected: _filterType == type,
                            onTap: () => setState(() => _filterType =
                                _filterType == type ? 'all' : type),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // ── Search + filter bar ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText:
                              'Search model, serial, SIM, owner, location…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  })
                              : null,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        onChanged: (v) =>
                            setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Filter by type',
                      icon: Icon(
                        Icons.filter_list,
                        color: _filterType != 'all'
                            ? AppTheme.primaryColor
                            : null,
                      ),
                      onSelected: (v) =>
                          setState(() => _filterType = v),
                      itemBuilder: (_) => _typeFilters
                          .map((f) => PopupMenuItem<String>(
                                value: f['value'],
                                child: Text(f['label']!),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} device${filtered.length != 1 ? 's' : ''}',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              ),

              // ── Device list ───────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.devices_other_outlined,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No devices found',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          return _DeviceCard(
                            item: item,
                            onEdit: () {
                              final regId =
                                  item['reg_id'] as String;
                              final ownerId =
                                  item['owner_id'] as String;
                              final ownerName =
                                  item['owner_name'] as String? ?? '';
                              final ownerRole =
                                  item['owner_role'] as String? ?? '';
                              final ownerLoc =
                                  item['location'] as String? ?? '';
                              final doc = docs.firstWhere(
                                  (d) => d.id == regId,
                                  orElse: () => docs.first);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FieldRegistrationFormScreen(
                                    existingId: regId,
                                    existingData: doc.data(),
                                    ownerId: ownerId,
                                    ownerName: ownerName,
                                    ownerRole: ownerRole,
                                    ownerLocation: ownerLoc,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Summary Chip ──────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor
              : AppTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 14,
                    color: selected ? Colors.white : AppTheme.primaryColor),
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? Colors.white.withOpacity(0.9)
                    : AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Device Card ───────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit;

  const _DeviceCard({required this.item, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final type = item['type'] as String? ?? 'unknown';
    final label = EquipmentMeta.labelFor(type);

    String details = '';
    if (type == 'sim_card_router') {
      details = [
        if ((item['model'] as String?)?.isNotEmpty == true)
          'Model: ${item['model']}',
        if ((item['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${item['serial_number']}',
        if ((item['sim_card_number'] as String?)?.isNotEmpty == true)
          'SIM: ${item['sim_card_number']}',
      ].join('  •  ');
    } else if (type == 'mikrotik') {
      details =
          '${item['device_name'] ?? 'Unknown'}  (${item['ip_address'] ?? ''})';
    } else if (type == 'unifi_ap') {
      details =
          '${item['ap_name'] ?? 'Unknown'}  •  MAC: ${item['ap_mac'] ?? ''}';
    } else if (type == 'link') {
      details =
          item['azimuth'] != null ? 'Azimuth: ${item['azimuth']}°' : '';
    } else if (type == 'omnidirectional_antenna') {
      details = [
        if ((item['model'] as String?)?.isNotEmpty == true) 'Model: ${item['model']}',
        if (item['height'] != null) 'Height: ${item['height']}m',
        if (item['frequency'] != null) 'Freq: ${item['frequency']}MHz',
      ].join('  •  ');
    } else if (type == 'sector_antenna') {
      details = [
        if ((item['model'] as String?)?.isNotEmpty == true) 'Model: ${item['model']}',
        if (item['height'] != null) 'Height: ${item['height']}m',
        if (item['frequency'] != null) 'Freq: ${item['frequency']}MHz',
        if (item['azimuth'] != null) 'Azimuth: ${item['azimuth']}°',
        if (item['beamwidth'] != null) 'BW: ${item['beamwidth']}°',
      ].join('  •  ');
    } else {
      details = [
        if ((item['model'] as String?)?.isNotEmpty == true)
          'Model: ${item['model']}',
        if ((item['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${item['serial_number']}',
      ].join('  •  ');
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(EquipmentMeta.iconFor(type),
                  color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  if (details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(details,
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 13)),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(
                        '${item['owner_name']}  (${(item['owner_role'] as String? ?? '').toUpperCase()})',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          [
                            if ((item['client_name'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              item['client_name'],
                            if ((item['physical_location'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              item['physical_location'],
                            if ((item['location'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              item['location'],
                          ].join(' – '),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: Colors.blue, size: 20),
              onPressed: onEdit,
              tooltip: 'Edit registration',
            ),
          ],
        ),
      ),
    );
  }
}
