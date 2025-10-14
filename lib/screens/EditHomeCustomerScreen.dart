import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/home_customer.dart';
import 'package:lightnetwork/screens/CreateHomeUserAccountScreen.dart';
import '../theme/app_theme.dart';

class EditHomeCustomerScreen extends StatefulWidget {
  final String customerId;
  const EditHomeCustomerScreen({super.key, required this.customerId});

  @override
  State<EditHomeCustomerScreen> createState() => _EditHomeCustomerScreenState();
}

class _EditHomeCustomerScreenState extends State<EditHomeCustomerScreen> {
  final _auth = Get.find<AuthController>();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  HomeCustomer? _customer;
  String? _homeUserEmail; // Email of existing home user account

  // dropdown data
  List<String> _zones = [];
  List<String> _types = [];

  // controllers
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _speedCtrl = TextEditingController();
  final _planCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'TZS');
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // selections
  String? _zone;
  String? _type;
  PaymentScheduleType _schedule = PaymentScheduleType.monthly;
  int? _billingDayOfMonth; // 1..28
  int? _billingWeekday;    // 1..7
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _confirmAndArchive() async {
    if (_customer == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Customer'),
        content: const Text('This will move the customer and all related payments and plan snapshots to the Archive. Attachments remain in storage. You can restore later by moving back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Show progress while archiving
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await HomeInternetService.archiveCustomer(id: widget.customerId);
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer archived')));
      Navigator.of(context).pop(true); // exit edit screen
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _confirmAndDelete() async {
    if (_customer == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer'),
        content: const Text('This will permanently delete the customer and all related payments and plan snapshots. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Show progress while deleting
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await HomeInternetService.deleteCustomer(id: widget.customerId);
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer deleted')));
      Navigator.of(context).pop(true); // exit edit screen
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _init() async {
    try {
      final c = await HomeInternetService.getCustomer(widget.customerId);
      final zones = await HomeInternetService.fetchZones();
      final types = await HomeInternetService.fetchCustomerTypes();
      final email = await HomeInternetService.getHomeUserEmail(widget.customerId);
      if (!mounted) return;
      setState(() {
        _customer = c;
        _zones = zones;
        _types = types;
        _homeUserEmail = email;
        if (c != null) {
          _nameCtrl.text = c.name;
          _phoneCtrl.text = c.phone;
          _locationCtrl.text = c.location;
          _speedCtrl.text = c.speedMbps.toString();
          _planCtrl.text = c.planAmount.toStringAsFixed(0);
          _currencyCtrl.text = c.currency;
          _addressCtrl.text = c.address ?? '';
          _notesCtrl.text = c.notes ?? '';
          _zone = c.zone;
          _type = c.customerType;
          _schedule = c.schedule;
          _billingDayOfMonth = c.billingDayOfMonth;
          _billingWeekday = c.billingWeekday;
          _active = c.active;
        }
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
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _speedCtrl.dispose();
    _planCtrl.dispose();
    _currencyCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isBoss) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Customer'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
          ),
        ),
        body: const Center(child: Text('Boss role required to edit customers.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_customer == null ? 'Edit Customer' : 'Edit ${_customer!.name}'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          if (!_loading)
            IconButton(
              tooltip: 'Save',
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'archive') {
                await _confirmAndArchive();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_rounded, color: AppTheme.warningColor),
                  title: Text(
                    'Archive Customer',
                    style: TextStyle(color: AppTheme.warningColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _section('Basic Info'),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationCtrl,
                      decoration: const InputDecoration(labelText: 'Location'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _zone,
                            items: _zones.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                            onChanged: (v) => setState(() => _zone = v),
                            decoration: const InputDecoration(labelText: 'Zone'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _type,
                            items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (v) => setState(() => _type = v),
                            decoration: const InputDecoration(labelText: 'Customer Type'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    _section('Plan'),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _speedCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Speed (Mbps)'),
                            validator: (v) {
                              final i = int.tryParse(v ?? '');
                              if (i == null || i <= 0) return 'Invalid speed';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _planCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Plan Amount'),
                            validator: (v) {
                              final d = double.tryParse(v ?? '');
                              if (d == null || d <= 0) return 'Invalid amount';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _currencyCtrl,
                            decoration: const InputDecoration(labelText: 'Currency'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<PaymentScheduleType>(
                            value: _schedule,
                            items: PaymentScheduleType.values
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s.name.toUpperCase()),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _schedule = v ?? PaymentScheduleType.monthly),
                            decoration: const InputDecoration(labelText: 'Schedule'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    if (_schedule == PaymentScheduleType.monthly)
                      TextFormField(
                        initialValue: (_billingDayOfMonth ?? 1).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Billing Day of Month (1-28)'),
                        onChanged: (v) => _billingDayOfMonth = int.tryParse(v)?.clamp(1, 28),
                      )
                    else
                      DropdownButtonFormField<int>(
                        value: _billingWeekday ?? DateTime.monday,
                        items: const [
                          DropdownMenuItem(value: DateTime.monday, child: Text('Monday')),
                          DropdownMenuItem(value: DateTime.tuesday, child: Text('Tuesday')),
                          DropdownMenuItem(value: DateTime.wednesday, child: Text('Wednesday')),
                          DropdownMenuItem(value: DateTime.thursday, child: Text('Thursday')),
                          DropdownMenuItem(value: DateTime.friday, child: Text('Friday')),
                          DropdownMenuItem(value: DateTime.saturday, child: Text('Saturday')),
                          DropdownMenuItem(value: DateTime.sunday, child: Text('Sunday')),
                        ],
                        onChanged: (v) => setState(() => _billingWeekday = v),
                        decoration: const InputDecoration(labelText: 'Billing Weekday'),
                      ),

                    const SizedBox(height: 20),
                    _section('More'),
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Active'),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),

                    const SizedBox(height: 24),
                    // Show existing account email or create button
                    if (_homeUserEmail != null)
                      Card(
                        elevation: 1,
                        color: AppTheme.successColor.withOpacity(0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Home User Account',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _homeUserEmail!,
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateHomeUserAccountScreen(
                                  customerId: widget.customerId,
                                  customerName: _customer?.name ?? '',
                                ),
                              ),
                            );
                            // Refresh to check if account was created
                            if (result == true && mounted) {
                              final email = await HomeInternetService.getHomeUserEmail(widget.customerId);
                              setState(() => _homeUserEmail = email);
                            }
                          },
                          icon: const Icon(Icons.person_add_rounded),
                          label: const Text('Create Home User Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppTheme.primaryColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Changes'),
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
            ),
    );
  }

  Widget _section(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_auth.isBoss) return;
    if (!_formKey.currentState!.validate()) return;

    final speed = int.tryParse(_speedCtrl.text.trim()) ?? 0;
    final amount = double.tryParse(_planCtrl.text.trim()) ?? 0.0;

    try {
      await HomeInternetService.updateCustomer(
        id: widget.customerId,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        zone: _zone,
        speedMbps: speed,
        customerType: _type,
        planAmount: amount,
        currency: _currencyCtrl.text.trim(),
        schedule: _schedule,
        billingDayOfMonth: _schedule == PaymentScheduleType.monthly ? (_billingDayOfMonth ?? 1).clamp(1, 28) : null,
        billingWeekday: _schedule == PaymentScheduleType.weekly ? (_billingWeekday ?? DateTime.monday) : null,
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        active: _active,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer updated')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
