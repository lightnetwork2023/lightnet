import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class HomeInternetDropdownsScreen extends StatefulWidget {
  const HomeInternetDropdownsScreen({super.key});

  @override
  State<HomeInternetDropdownsScreen> createState() => _HomeInternetDropdownsScreenState();
}

class _HomeInternetDropdownsScreenState extends State<HomeInternetDropdownsScreen> {
  final _auth = Get.find<AuthController>();

  final _zoneCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<String> _zones = [];
  List<String> _types = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final zones = await HomeInternetService.fetchZones();
      final types = await HomeInternetService.fetchCustomerTypes();
      if (!mounted) return;
      setState(() {
        _zones = List<String>.from(zones);
        _types = List<String>.from(types);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _zoneCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isBoss) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dropdown Options'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
          ),
        ),
        body: const Center(child: Text('Boss role required to edit options.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dropdown Options'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
          ),
          IconButton(
            onPressed: (_loading || _saving) ? null : _save,
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Save',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Zones'),
                  _addRow(
                    controller: _zoneCtrl,
                    hint: 'Add new zone (e.g., Zone A)',
                    onAdd: () => _addValue(_zones, _zoneCtrl),
                  ),
                  const SizedBox(height: 8),
                  _listCard(_zones, (i) => setState(() => _zones.removeAt(i))),

                  const SizedBox(height: 24),
                  _section('Customer Types'),
                  _addRow(
                    controller: _typeCtrl,
                    hint: 'Add new customer type (e.g., Business)',
                    onAdd: () => _addValue(_types, _typeCtrl),
                  ),
                  const SizedBox(height: 8),
                  _listCard(_types, (i) => setState(() => _types.removeAt(i))),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
      ),
    );
  }

  Widget _addRow({required TextEditingController controller, required String hint, required VoidCallback onAdd}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
      ],
    );
  }

  Widget _listCard(List<String> items, ValueChanged<int> onRemoveIndex) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('No items, add above'),
      );
    }

    return Card(
      elevation: 1,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          return ListTile(
            leading: const Icon(Icons.drag_indicator, color: AppTheme.textSecondary),
            title: Text(items[i]),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              onPressed: () => onRemoveIndex(i),
            ),
          );
        },
      ),
    );
  }

  void _addValue(List<String> list, TextEditingController c) {
    final v = c.text.trim();
    if (v.isEmpty) return;
    final exists = list.any((e) => e.toLowerCase() == v.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already exists')));
      return;
    }
    setState(() => list.add(v));
    c.clear();
  }

  Future<void> _save() async {
    if (_zones.isEmpty || _types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one zone and one customer type')));
      return;
    }
    setState(() => _saving = true);
    try {
      await HomeInternetService.setDropdownOptions(zones: _zones, customerTypes: _types);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Options saved')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
