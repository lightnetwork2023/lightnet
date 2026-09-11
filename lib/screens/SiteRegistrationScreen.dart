import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../controllers/location_controller.dart';
import '../services/SiteService.dart';
import '../services/MikroTikMonitorService.dart';
import '../theme/app_theme.dart';
import 'FieldDetailsScreen.dart';

class SiteRegistrationScreen extends StatefulWidget {
  final String? existingId;
  final Map<String, dynamic>? existingData;

  const SiteRegistrationScreen({super.key, this.existingId, this.existingData});

  @override
  State<SiteRegistrationScreen> createState() => _SiteRegistrationScreenState();
}

class _SiteRegistrationScreenState extends State<SiteRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _physicalCtrl = TextEditingController();
  final LocationController _locationController = Get.find<LocationController>();

  String _mainLocation = '';
  double? _lat, _lng;
  bool _gettingGPS = false;
  bool _saving = false;

  // Equipment
  List<Map<String, dynamic>> _equipment = [];
  List<Map<String, dynamic>> _mikrotikDevices = [];
  bool _mikrotikLoaded = false;

  // Agents
  List<Map<String, dynamic>> _allAgents = [];
  final Set<String> _selectedAgentIds = {};
  bool _agentsLoaded = false;

  // Home Customers
  List<Map<String, dynamic>> _allHomeCustomers = [];
  final Set<String> _selectedHomeCustomerIds = {};
  bool _homeCustomersLoaded = false;

  @override
  void initState() {
    super.initState();
    if (_locationController.locations.isEmpty) _locationController.loadLocations();
    // Pickers load their lists on first open.
    final d = widget.existingData;
    if (d != null) {
      _nameCtrl.text = d['name'] as String? ?? '';
      _physicalCtrl.text = d['physical_location'] as String? ?? '';
      _mainLocation = d['main_location'] as String? ?? '';
      _lat = (d['latitude'] as num?)?.toDouble();
      _lng = (d['longitude'] as num?)?.toDouble();
      _equipment = List<Map<String, dynamic>>.from(
          (d['equipment'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []);
      final agentIds = List<String>.from(d['agent_ids'] ?? []);
      _selectedAgentIds.addAll(agentIds);
      final customerIds = List<String>.from(d['home_customer_ids'] ?? []);
      _selectedHomeCustomerIds.addAll(customerIds);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _physicalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'agent')
          .get();
      if (mounted) {
        setState(() {
          _allAgents = snap.docs.map((d) {
            final data = d.data();
            return {'id': d.id, 'name': data['name'] ?? data['email'] ?? d.id, ...data};
          }).toList();
          _agentsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _agentsLoaded = true);
    }
  }

  Future<void> _loadHomeCustomers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('home_customers').get();
      if (mounted) {
        setState(() {
          _allHomeCustomers = snap.docs.map((d) {
            final data = d.data();
            return {'id': d.id, 'name': data['name'] ?? data['full_name'] ?? d.id, ...data};
          }).toList();
          _homeCustomersLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _homeCustomersLoaded = true);
    }
  }

  Future<void> _loadMikrotikDevices() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('mikrotik_devices').get();
      if (mounted) {
        setState(() {
          _mikrotikDevices = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _mikrotikLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _mikrotikLoaded = true);
    }
  }

  Future<void> _captureGPS() async {
    setState(() => _gettingGPS = true);
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) { _snack('Location services disabled.'); return; }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) { _snack('Permission denied.'); return; }
      }
      if (perm == LocationPermission.deniedForever) { _snack('Permission permanently denied.'); return; }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() { _lat = pos.latitude; _lng = pos.longitude; });
        _snack('GPS: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}');
      }
    } catch (e) {
      _snack('GPS error: $e');
    } finally {
      if (mounted) setState(() => _gettingGPS = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_mainLocation.isEmpty) { _snack('Please select a main location.'); return; }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'main_location': _mainLocation,
        'physical_location': _physicalCtrl.text.trim(),
        'equipment': _equipment,
        'agent_ids': _selectedAgentIds.toList(),
        'home_customer_ids': _selectedHomeCustomerIds.toList(),
      };
      if (_lat != null) data['latitude'] = _lat;
      if (_lng != null) data['longitude'] = _lng;
      if (widget.existingId != null) {
        await SiteService.update(widget.existingId!, data);
        _snack('Site updated!');
      } else {
        await SiteService.add(data);
        _snack('Site created!');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showAddEquipmentSheet() {
    if (!_mikrotikLoaded) {
      _loadMikrotikDevices();
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Equipment Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            ...EquipmentMeta.types.map((t) => ListTile(
              leading: Icon(t['icon'] as IconData, color: AppTheme.primaryColor),
              title: Text(t['label'] as String),
              onTap: () {
                Navigator.pop(ctx);
                _showEquipmentDialog(t['type'] as String, t['label'] as String);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showEquipmentDialog(String type, String label, [Map<String, dynamic>? existing, int? editIdx]) {
    final ctrls = <String, TextEditingController>{};
    String? mikrotikId = existing?['device_id'];
    String? mikrotikName = existing?['device_name'];
    String? mikrotikIp = existing?['ip_address'];

    if (type != 'mikrotik') {
      ctrls['model'] = TextEditingController(text: existing?['model'] ?? '');
      if (type != 'link') {
        ctrls['serial'] = TextEditingController(text: existing?['serial_number'] ?? '');
      } else {
        ctrls['azimuth'] = TextEditingController(text: existing?['azimuth']?.toString() ?? '');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(editIdx != null ? 'Edit $label' : 'Add $label'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (type == 'mikrotik') ...[
                  if (!_mikrotikLoaded)
                    const Center(child: CircularProgressIndicator())
                  else if (_mikrotikDevices.isEmpty)
                    const Text('No MikroTik devices found.\nAdd from MikroTik Monitoring.', textAlign: TextAlign.center)
                  else
                    ..._mikrotikDevices.map((d) {
                      final sel = mikrotikId == d['id'];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.dns, color: sel ? AppTheme.primaryColor : Colors.grey),
                        title: Text(d['name'] as String? ?? 'Unknown'),
                        subtitle: Text(d['ipAddress'] as String? ?? ''),
                        selected: sel,
                        selectedTileColor: AppTheme.primaryColor.withOpacity(0.1),
                        onTap: () => setDlg(() {
                          mikrotikId = d['id'] as String;
                          mikrotikName = d['name'] as String?;
                          mikrotikIp = d['ipAddress'] as String?;
                        }),
                      );
                    }),
                ] else if (type == 'link') ...[
                  TextField(
                    controller: ctrls['azimuth'],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Azimuth / Angle (°)', border: OutlineInputBorder()),
                  ),
                ] else ...[
                  TextField(controller: ctrls['model'], decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: ctrls['serial'], decoration: const InputDecoration(labelText: 'Serial Number', border: OutlineInputBorder())),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { for (final c in ctrls.values) c.dispose(); Navigator.pop(ctx); },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
              onPressed: () {
                if (type == 'mikrotik' && mikrotikId == null) {
                  _snack('Please select a MikroTik device.'); return;
                }
                final item = <String, dynamic>{'type': type, 'label': label};
                if (type == 'mikrotik') {
                  item['device_id'] = mikrotikId;
                  item['device_name'] = mikrotikName;
                  item['ip_address'] = mikrotikIp;
                } else if (type == 'link') {
                  item['azimuth'] = double.tryParse(ctrls['azimuth']!.text.trim());
                } else {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                }
                setState(() {
                  if (editIdx != null) _equipment[editIdx] = item;
                  else _equipment.add(item);
                });
                for (final c in ctrls.values) c.dispose();
                Navigator.pop(ctx);
              },
              child: Text(editIdx != null ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAgentPicker() {
    if (!_agentsLoaded) {
      _loadAgents();
    }
    String search = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBs) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Agents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(hintText: 'Search…', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  onChanged: (v) => setBs(() => search = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: !_agentsLoaded
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          controller: sc,
                          children: _allAgents.where((a) {
                            final name = (a['name'] as String? ?? '').toLowerCase();
                            final loc = (a['location'] as String? ?? '').toLowerCase();
                            return search.isEmpty || name.contains(search.toLowerCase()) || loc.contains(search.toLowerCase());
                          }).map((a) {
                            final id = a['id'] as String;
                            final name = a['name'] as String? ?? id;
                            final loc = a['location'] as String? ?? '';
                            return CheckboxListTile(
                              value: _selectedAgentIds.contains(id),
                              title: Text(name),
                              subtitle: loc.isNotEmpty ? Text(loc) : null,
                              onChanged: (v) {
                                setState(() { v! ? _selectedAgentIds.add(id) : _selectedAgentIds.remove(id); });
                                setBs(() {});
                              },
                            );
                          }).toList(),
                        ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomerPicker() {
    if (!_homeCustomersLoaded) {
      _loadHomeCustomers();
    }
    String search = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBs) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Home Customers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(hintText: 'Search…', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  onChanged: (v) => setBs(() => search = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: !_homeCustomersLoaded
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          controller: sc,
                          children: _allHomeCustomers.where((c) {
                            final name = (c['name'] as String? ?? '').toLowerCase();
                            return search.isEmpty || name.contains(search.toLowerCase());
                          }).map((c) {
                            final id = c['id'] as String;
                            final name = c['name'] as String? ?? id;
                            final zone = c['zone'] as String? ?? '';
                            return CheckboxListTile(
                              value: _selectedHomeCustomerIds.contains(id),
                              title: Text(name),
                              subtitle: zone.isNotEmpty ? Text(zone) : null,
                              onChanged: (v) {
                                setState(() { v! ? _selectedHomeCustomerIds.add(id) : _selectedHomeCustomerIds.remove(id); });
                                setBs(() {});
                              },
                            );
                          }).toList(),
                        ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: Colors.grey.shade300)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Site' : 'New Site'),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppGradients.primaryGradient)),
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton.icon(onPressed: _save, icon: const Icon(Icons.save, color: Colors.white), label: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Site Information ─────────────────────────────────────
            _sectionHeader('Site Information', Icons.location_city_outlined),
            const SizedBox(height: 12),
            Obx(() {
              final locs = _locationController.locations;
              return DropdownButtonFormField<String>(
                value: _mainLocation.isEmpty ? null : _mainLocation,
                decoration: const InputDecoration(labelText: 'Main Location *', prefixIcon: Icon(Icons.place_outlined), border: OutlineInputBorder()),
                items: locs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() => _mainLocation = v ?? ''),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              );
            }),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Site Name *', prefixIcon: Icon(Icons.business_outlined), border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _physicalCtrl,
              decoration: const InputDecoration(labelText: 'Physical Address', prefixIcon: Icon(Icons.map_outlined), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            // ── GPS ─────────────────────────────────────────────────
            _sectionHeader('GPS Coordinates', Icons.gps_fixed),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Expanded(
                    child: _lat != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Lat: ${_lat!.toStringAsFixed(6)}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                              Text('Lng: ${_lng!.toStringAsFixed(6)}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                            ],
                          )
                        : const Text('No coordinates yet', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _gettingGPS ? null : _captureGPS,
                    icon: _gettingGPS ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
                    label: Text(_gettingGPS ? 'Getting...' : 'Capture GPS'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Equipment ─────────────────────────────────────────────
            _sectionHeader('Equipment', Icons.devices_other_outlined),
            const SizedBox(height: 12),
            if (_equipment.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('No equipment added yet', style: TextStyle(color: Colors.grey))),
              ),
            ..._equipment.asMap().entries.map((entry) {
              final idx = entry.key;
              final eq = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(EquipmentMeta.iconFor(eq['type'] as String? ?? ''), color: AppTheme.primaryColor),
                  title: Text(EquipmentMeta.labelFor(eq['type'] as String? ?? '')),
                  subtitle: Text(_equipSubtitle(eq)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _showEquipmentDialog(eq['type'] as String, EquipmentMeta.labelFor(eq['type'] as String? ?? ''), eq, idx)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => setState(() => _equipment.removeAt(idx))),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _showAddEquipmentSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add Equipment'),
            ),
            const SizedBox(height: 20),

            // ── Agents ─────────────────────────────────────────────
            _sectionHeader('Assigned Agents', Icons.people_outline),
            const SizedBox(height: 12),
            if (_selectedAgentIds.isNotEmpty) ...[
              ..._selectedAgentIds.map((id) {
                final agent = _allAgents.firstWhere((a) => a['id'] == id, orElse: () => {'id': id, 'name': id});
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, color: AppTheme.primaryColor),
                  title: Text(agent['name'] as String? ?? id),
                  subtitle: (agent['location'] as String?)?.isNotEmpty == true ? Text(agent['location'] as String) : null,
                  trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: () => setState(() => _selectedAgentIds.remove(id))),
                );
              }),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _showAgentPicker,
              icon: const Icon(Icons.person_add_outlined),
              label: Text(_selectedAgentIds.isEmpty ? 'Add Agents' : 'Manage Agents (${_selectedAgentIds.length})'),
            ),
            const SizedBox(height: 20),

            // ── Home Customers ─────────────────────────────────────
            _sectionHeader('Home Customers', Icons.home_outlined),
            const SizedBox(height: 12),
            if (_selectedHomeCustomerIds.isNotEmpty) ...[
              ..._selectedHomeCustomerIds.map((id) {
                final cust = _allHomeCustomers.firstWhere((c) => c['id'] == id, orElse: () => {'id': id, 'name': id});
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.home_outlined, color: Colors.teal),
                  title: Text(cust['name'] as String? ?? id),
                  subtitle: (cust['zone'] as String?)?.isNotEmpty == true ? Text(cust['zone'] as String) : null,
                  trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: () => setState(() => _selectedHomeCustomerIds.remove(id))),
                );
              }),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _showCustomerPicker,
              icon: const Icon(Icons.home_work_outlined),
              label: Text(_selectedHomeCustomerIds.isEmpty ? 'Add Home Customers' : 'Manage Customers (${_selectedHomeCustomerIds.length})'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _equipSubtitle(Map<String, dynamic> eq) {
    final type = eq['type'] as String? ?? '';
    if (type == 'mikrotik') return '${eq['device_name'] ?? 'Unknown'} (${eq['ip_address'] ?? ''})';
    if (type == 'link') return eq['azimuth'] != null ? 'Azimuth: ${eq['azimuth']}°' : '';
    return [
      if ((eq['model'] as String?)?.isNotEmpty == true) 'Model: ${eq['model']}',
      if ((eq['serial_number'] as String?)?.isNotEmpty == true) 'S/N: ${eq['serial_number']}',
    ].join(' • ');
  }
}
