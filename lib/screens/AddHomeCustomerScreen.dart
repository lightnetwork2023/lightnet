import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/models/home_customer.dart';
import '../theme/app_theme.dart';

class AddHomeCustomerScreen extends StatefulWidget {
  const AddHomeCustomerScreen({super.key});

  @override
  State<AddHomeCustomerScreen> createState() => _AddHomeCustomerScreenState();
}

class _AddHomeCustomerScreenState extends State<AddHomeCustomerScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _planAmount = TextEditingController();
  final TextEditingController _speed = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  PaymentScheduleType _schedule = PaymentScheduleType.monthly;
  DateTime _startDate = DateTime.now();
  int? _billingDayOfMonth;
  int? _billingWeekday;

  List<String> _zones = [];
  String? _zone;

  List<String> _customerTypes = [];
  String? _customerType;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _initDropdowns();
  }

  Future<void> _initDropdowns() async {
    final zones = await HomeInternetService.fetchZones();
    final types = await HomeInternetService.fetchCustomerTypes();
    setState(() {
      _zones = zones;
      _customerTypes = types;
      _zone = zones.isNotEmpty ? zones.first : null;
      _customerType = types.isNotEmpty ? types.first : null;
      _billingDayOfMonth = DateTime.now().day.clamp(1, 28);
      _billingWeekday = DateTime.now().weekday;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    _planAmount.dispose();
    _speed.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Home Internet Customer'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_name, 'Full Name', Icons.person, requiredField: true),
              const SizedBox(height: 12),
              _buildTextField(_phone, 'Phone', Icons.phone, keyboard: TextInputType.phone, requiredField: true),
              const SizedBox(height: 12),
              _buildTextField(_location, 'Location', Icons.location_on, requiredField: true),
              const SizedBox(height: 12),

              // Zone dropdown
              _buildDropdown<String>(
                label: 'Zone',
                value: _zone,
                items: _zones,
                icon: Icons.map_rounded,
                onChanged: (v) => setState(() => _zone = v),
              ),
              const SizedBox(height: 12),

              // Customer Type dropdown
              _buildDropdown<String>(
                label: 'Customer Type',
                value: _customerType,
                items: _customerTypes,
                icon: Icons.category_rounded,
                onChanged: (v) => setState(() => _customerType = v),
              ),
              const SizedBox(height: 12),

              // Speed and Plan Amount
              Row(
                children: [
                  Expanded(child: _buildTextField(_speed, 'Speed (Mbps)', Icons.speed, keyboard: TextInputType.number, requiredField: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(_planAmount, 'Plan Amount (TZS)', Icons.payments, keyboard: TextInputType.number, requiredField: true)),
                ],
              ),
              const SizedBox(height: 12),

              // Schedule
              _buildDropdown<PaymentScheduleType>(
                label: 'Payment Schedule',
                value: _schedule,
                items: PaymentScheduleType.values,
                icon: Icons.schedule_rounded,
                display: (v) => v == PaymentScheduleType.weekly ? 'Weekly' : 'Monthly',
                onChanged: (v) => setState(() => _schedule = v ?? PaymentScheduleType.monthly),
              ),
              const SizedBox(height: 12),

              // Billing anchors
              if (_schedule == PaymentScheduleType.monthly)
                _buildDropdown<int>(
                  label: 'Billing Day of Month',
                  value: _billingDayOfMonth,
                  items: List<int>.generate(28, (i) => i + 1),
                  icon: Icons.calendar_today_rounded,
                  onChanged: (v) => setState(() => _billingDayOfMonth = v),
                )
              else
                _buildDropdown<int>(
                  label: 'Billing Weekday',
                  value: _billingWeekday,
                  items: const [1,2,3,4,5,6,7],
                  icon: Icons.event_rounded,
                  display: (d) => const {
                    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun',
                  }[d]!,
                  onChanged: (v) => setState(() => _billingWeekday = v),
                ),
              const SizedBox(height: 12),

              // Start date
              _buildDatePicker(
                context: context,
                label: 'Start Date',
                value: _startDate,
                onPick: (d) => setState(() => _startDate = d),
              ),
              const SizedBox(height: 12),

              _buildTextField(_address, 'Address (optional)', Icons.home_outlined),
              const SizedBox(height: 12),
              _buildTextField(_notes, 'Notes (optional)', Icons.notes, maxLines: 3),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(_submitting ? 'Saving...' : 'Save Customer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController c, String label, IconData icon, {bool requiredField = false, TextInputType? keyboard, int maxLines = 1}) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) {
        if (requiredField && (v == null || v.trim().isEmpty)) return 'Required';
        return null;
      },
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required IconData icon,
    String Function(T v)? display,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: items.map((e) => DropdownMenuItem<T>(
            value: e,
            child: Text(display != null ? display(e) : '$e'),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required BuildContext context,
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onPick,
  }) {
    final fmt = DateFormat('yyyy-MM-dd');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_note_rounded),
      title: Text(label),
      subtitle: Text(fmt.format(value)),
      trailing: const Icon(Icons.edit_calendar_rounded),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_zone == null || _customerType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select zone and customer type')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await HomeInternetService.createCustomer(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        location: _location.text.trim(),
        zone: _zone!,
        speedMbps: int.tryParse(_speed.text.trim()) ?? 0,
        customerType: _customerType!,
        planAmount: double.tryParse(_planAmount.text.trim()) ?? 0,
        schedule: _schedule,
        startDate: _startDate,
        billingDayOfMonth: _schedule == PaymentScheduleType.monthly ? _billingDayOfMonth : null,
        billingWeekday: _schedule == PaymentScheduleType.weekly ? _billingWeekday : null,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) {
        Get.back();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer created')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
