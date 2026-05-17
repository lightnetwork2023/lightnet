import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key});

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  final _db = FirebaseFirestore.instance;

  // Filters
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  DateTime? _selectedDay;
  String _selectedRole = 'all';
  String _selectedCategory = 'all';
  bool _errorsOnly = false;

  // Available months dropdown
  static final List<String> _months = List.generate(6, (i) {
    final d = DateTime.now();
    return DateFormat('yyyy-MM').format(DateTime(d.year, d.month - i, 1));
  });

  static const Map<String, String> _roleLabels = {
    'all': 'All Roles',
    'boss': 'Boss',
    'agent': 'Agent',
    'superagent': 'Super Agent',
    'technician': 'Technician',
    'homeuser': 'Home User',
  };

  static const Map<String, String> _categoryLabels = {
    'all': 'All Events',
    'auth': 'Auth',
    'voucher': 'Vouchers',
    'payment': 'Payments',
    'home': 'Home Internet',
    'expense': 'Expenses',
    'user_mgmt': 'User Mgmt',
    'debt': 'Debt',
    'device': 'Devices',
    'error': 'Errors',
  };

  static const Map<String, List<String>> _categoryEvents = {
    'auth': ['user_signed_in', 'user_signed_out', 'password_reset_sent'],
    'voucher': ['vouchers_generated', 'voucher_generated_one', 'user_deleted_radius', 'voucher_settings_updated', 'voucher_deleted'],
    'payment': ['payment_initiated'],
    'home': ['home_customer_created', 'home_customer_updated', 'home_customer_deleted', 'home_customer_archived', 'home_customer_restored', 'home_payment_added', 'home_payment_approved', 'home_payment_rejected'],
    'expense': ['expense_submitted', 'expense_updated', 'expense_approved', 'expense_rejected'],
    'user_mgmt': ['user_created', 'user_deleted', 'user_role_updated'],
    'debt': ['payable_added', 'receivable_added', 'debt_payment_recorded', 'debt_deleted'],
    'device': ['network_device_added', 'network_device_deleted', 'simcard_added', 'simcard_updated', 'simcard_deleted'],
    'error': ['error'],
  };

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> q = _db.collection('app_logs');

    if (_selectedDay != null) {
      q = q.where('day', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDay!));
    } else {
      q = q.where('month', isEqualTo: _selectedMonth);
    }

    if (_selectedRole != 'all') {
      q = q.where('role', isEqualTo: _selectedRole);
    }

    if (_errorsOnly) {
      q = q.where('is_error', isEqualTo: true);
    }

    return q.orderBy('timestamp', descending: true).limit(200);
  }

  bool _matchesCategory(Map<String, dynamic> data) {
    if (_selectedCategory == 'all') return true;
    if (_errorsOnly && data['is_error'] == true) return true;
    final events = _categoryEvents[_selectedCategory] ?? [];
    return events.contains(data['event']);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppTheme.primaryColor,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDay = picked);
    }
  }

  void _clearDay() => setState(() => _selectedDay = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('App Activity Logs', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _errorsOnly ? Icons.error : Icons.error_outline,
              color: _errorsOnly ? Colors.red[200] : Colors.white,
            ),
            tooltip: 'Errors only',
            onPressed: () => setState(() => _errorsOnly = !_errorsOnly),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersPanel(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildQuery().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
                        const SizedBox(height: 8),
                        Text('${snap.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        const Text(
                          'Create required Firestore index\n(tap the link in the console)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                final allDocs = snap.data?.docs ?? [];
                final docs = allDocs.where((d) => _matchesCategory(d.data())).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No logs found', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                      ],
                    ),
                  );
                }

                // Group by day
                final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped = {};
                for (final doc in docs) {
                  final day = doc.data()['day'] as String? ?? 'Unknown';
                  grouped.putIfAbsent(day, () => []).add(doc);
                }
                final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: days.length,
                  itemBuilder: (context, i) {
                    final day = days[i];
                    final entries = grouped[day]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DayHeader(day: day, count: entries.length),
                        ...entries.map((doc) => _LogCard(data: doc.data())),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // Row 1: Month and Day picker
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedMonth,
                      isDense: true,
                      items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() { _selectedMonth = v; _selectedDay = null; });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _pickDay,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _selectedDay != null ? AppTheme.primaryColor.withOpacity(0.1) : null,
                    border: Border.all(color: _selectedDay != null ? AppTheme.primaryColor : Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: _selectedDay != null ? AppTheme.primaryColor : Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _selectedDay != null ? DateFormat('MMM d').format(_selectedDay!) : 'Day',
                        style: TextStyle(
                          fontSize: 13,
                          color: _selectedDay != null ? AppTheme.primaryColor : Colors.grey[700],
                        ),
                      ),
                      if (_selectedDay != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _clearDay,
                          child: const Icon(Icons.close, size: 14, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Role chips
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _roleLabels.entries.map((e) {
                final selected = _selectedRole == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(e.value, style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.grey[800])),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedRole = e.key),
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: Colors.grey[100],
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Row 3: Category chips
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categoryLabels.entries.map((e) {
                final selected = _selectedCategory == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(e.value, style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.grey[800])),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedCategory = e.key),
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: Colors.grey[100],
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String day;
  final int count;
  const _DayHeader({required this.day, required this.count});

  @override
  Widget build(BuildContext context) {
    DateTime? dt;
    try {
      dt = DateTime.parse(day);
    } catch (_) {}

    final label = dt != null ? DateFormat('EEEE, MMMM d, yyyy').format(dt) : day;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count events', style: TextStyle(color: Colors.grey[700], fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LogCard({required this.data});

  static const Map<String, IconData> _eventIcons = {
    'user_signed_in': Icons.login,
    'user_signed_out': Icons.logout,
    'user_created': Icons.person_add,
    'user_deleted': Icons.person_remove,
    'user_role_updated': Icons.manage_accounts,
    'password_reset_sent': Icons.lock_reset,
    'vouchers_generated': Icons.confirmation_number,
    'voucher_generated_one': Icons.confirmation_number_outlined,
    'user_deleted_radius': Icons.delete_outline,
    'voucher_settings_updated': Icons.edit,
    'voucher_deleted': Icons.delete,
    'payment_initiated': Icons.payment,
    'home_customer_created': Icons.home,
    'home_customer_updated': Icons.edit_note,
    'home_customer_deleted': Icons.home_outlined,
    'home_customer_archived': Icons.archive,
    'home_customer_restored': Icons.unarchive,
    'home_payment_added': Icons.receipt,
    'home_payment_approved': Icons.check_circle,
    'home_payment_rejected': Icons.cancel,
    'expense_submitted': Icons.attach_money,
    'expense_updated': Icons.edit,
    'expense_approved': Icons.check_circle_outline,
    'expense_rejected': Icons.cancel_outlined,
    'payable_added': Icons.arrow_upward,
    'receivable_added': Icons.arrow_downward,
    'debt_payment_recorded': Icons.payments,
    'debt_deleted': Icons.delete_sweep,
    'network_device_added': Icons.router,
    'network_device_deleted': Icons.router_outlined,
    'simcard_added': Icons.sim_card,
    'simcard_updated': Icons.sim_card_outlined,
    'simcard_deleted': Icons.sim_card_download_outlined,
    'error': Icons.error_outline,
  };

  static const Map<String, Color> _eventColors = {
    'user_signed_in': Color(0xFF4CAF50),
    'user_signed_out': Color(0xFF9E9E9E),
    'user_created': Color(0xFF2196F3),
    'user_deleted': Color(0xFFF44336),
    'user_role_updated': Color(0xFF9C27B0),
    'password_reset_sent': Color(0xFF607D8B),
    'vouchers_generated': Color(0xFF00BCD4),
    'voucher_generated_one': Color(0xFF00ACC1),
    'user_deleted_radius': Color(0xFFE91E63),
    'voucher_settings_updated': Color(0xFF3F51B5),
    'voucher_deleted': Color(0xFFF44336),
    'payment_initiated': Color(0xFF4CAF50),
    'home_customer_created': Color(0xFF009688),
    'home_customer_updated': Color(0xFF03A9F4),
    'home_customer_deleted': Color(0xFFF44336),
    'home_customer_archived': Color(0xFFFF9800),
    'home_customer_restored': Color(0xFF8BC34A),
    'home_payment_added': Color(0xFF00BCD4),
    'home_payment_approved': Color(0xFF4CAF50),
    'home_payment_rejected': Color(0xFFF44336),
    'expense_submitted': Color(0xFFFF5722),
    'expense_updated': Color(0xFFFF9800),
    'expense_approved': Color(0xFF4CAF50),
    'expense_rejected': Color(0xFFF44336),
    'payable_added': Color(0xFFE91E63),
    'receivable_added': Color(0xFF4CAF50),
    'debt_payment_recorded': Color(0xFF009688),
    'debt_deleted': Color(0xFFF44336),
    'network_device_added': Color(0xFF607D8B),
    'network_device_deleted': Color(0xFF9E9E9E),
    'simcard_added': Color(0xFF673AB7),
    'simcard_updated': Color(0xFF9C27B0),
    'simcard_deleted': Color(0xFFF44336),
    'error': Color(0xFFF44336),
  };

  String _eventLabel(String event) {
    return event.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    if (ts is Timestamp) {
      return DateFormat('HH:mm:ss').format(ts.toDate().toLocal());
    }
    return '';
  }

  List<_Detail> _buildDetails() {
    final details = <_Detail>[];
    final event = data['event'] as String? ?? '';

    void add(String label, dynamic val) {
      if (val != null && val.toString().isNotEmpty) {
        details.add(_Detail(label, val.toString()));
      }
    }

    // Auth
    if (event == 'user_created') {
      add('Email', data['new_email']);
      add('Role', data['new_role']);
      add('Name', data['new_name']);
      add('Location', data['new_location']);
    } else if (event == 'user_deleted') {
      add('Target UID', data['target_uid']);
      add('Target name', data['target_name']);
    } else if (event == 'user_role_updated') {
      add('Target UID', data['target_uid']);
      add('Old role', data['old_role']);
      add('New role', data['new_role']);
    } else if (event == 'password_reset_sent') {
      add('Email', data['target_email']);
    }
    // Vouchers
    else if (event == 'vouchers_generated') {
      add('Location', data['location']);
      add('Count', data['num_users']);
      add('Days', data['num_days']);
      add('Speed', data['speed_limit']);
    } else if (event == 'voucher_generated_one') {
      add('Duration', data['duration_key']);
    } else if (event == 'user_deleted_radius' || event == 'voucher_deleted') {
      add('Username', data['username']);
    } else if (event == 'voucher_settings_updated') {
      add('Username', data['username']);
      add('MAC', data['mac_address']);
      add('Speed', data['speed_limit']);
      add('Expire', data['expire_time']);
    }
    // Payments
    else if (event == 'payment_initiated') {
      add('Provider', data['provider']);
      add('Phone', data['phone']);
      add('Amount', data['amount']);
      add('Qty', data['quantity']);
      add('Location', data['location']);
      add('Days', data['days']);
    }
    // Home Internet
    else if (event == 'home_customer_created') {
      add('Customer', data['customer_name']);
      add('ID', data['customer_id']);
      add('Location', data['location']);
    } else if (event == 'home_customer_updated' || event == 'home_customer_archived' || event == 'home_customer_restored') {
      add('ID', data['customer_id']);
    } else if (event == 'home_customer_deleted') {
      add('ID', data['customer_id']);
      add('Name', data['customer_name']);
    } else if (event == 'home_payment_added') {
      add('Customer', data['customer_id']);
      add('Amount', data['amount']);
      add('Currency', data['currency']);
    } else if (event == 'home_payment_approved' || event == 'home_payment_rejected') {
      add('Customer', data['customer_id']);
      add('Payment ID', data['payment_id']);
      if (event == 'home_payment_rejected') add('Reason', data['reason']);
    }
    // Expenses
    else if (event == 'expense_submitted' || event == 'expense_updated') {
      add('ID', data['expense_id']);
      add('Title', data['title']);
      add('Amount', data['amount']);
      add('Location', data['location']);
    } else if (event == 'expense_approved') {
      add('ID', data['expense_id']);
      add('Amount', data['amount']);
      add('Submitted by', data['submitted_by']);
    } else if (event == 'expense_rejected') {
      add('ID', data['expense_id']);
      add('Reason', data['reason']);
      add('Amount', data['amount']);
    }
    // Debts
    else if (event == 'payable_added') {
      add('Creditor', data['creditor_name']);
      add('Amount', data['amount']);
      add('ID', data['doc_id']);
    } else if (event == 'receivable_added') {
      add('Debtor', data['debtor_name']);
      add('Amount', data['amount']);
      add('ID', data['doc_id']);
    } else if (event == 'debt_payment_recorded') {
      add('Type', data['type']);
      add('Debt ID', data['debt_id']);
      add('Amount', data['amount']);
    } else if (event == 'debt_deleted') {
      add('Type', data['type']);
      add('Debt ID', data['debt_id']);
    }
    // Devices
    else if (event == 'network_device_added') {
      add('Name', data['device_name']);
      add('Location', data['location']);
      add('MAC', data['mac_id']);
    } else if (event == 'network_device_deleted') {
      add('MAC', data['mac_id']);
    } else if (event == 'simcard_added') {
      add('MSISDN', data['msisdn']);
      add('Location', data['location']);
      add('Type', data['sim_type']);
    } else if (event == 'simcard_updated') {
      add('MSISDN', data['msisdn']);
      add('Doc ID', data['doc_id']);
    } else if (event == 'simcard_deleted') {
      add('MSISDN', data['msisdn']);
    }
    // Error
    else if (event == 'error') {
      add('Action', data['action']);
      add('Error', data['error']);
    }

    return details;
  }

  @override
  Widget build(BuildContext context) {
    final event = data['event'] as String? ?? 'unknown';
    final isError = data['is_error'] == true;
    final color = isError ? const Color(0xFFF44336) : (_eventColors[event] ?? Colors.blueGrey);
    final icon = _eventIcons[event] ?? Icons.info_outline;
    final name = data['name'] as String? ?? data['uid'] as String? ?? '—';
    final role = data['role'] as String? ?? '—';
    final time = _formatTime(data['timestamp']);
    final details = _buildDetails();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isError ? Border.all(color: Colors.red[200]!, width: 1.5) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _eventLabel(event),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isError ? Colors.red[700] : Colors.grey[800],
                          ),
                        ),
                      ),
                      Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _RoleBadge(role: role),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: details.map((d) => _DetailChip(label: d.label, value: d.value)).toList(),
                    ),
                  ],
                  if (isError && data['error'] != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Text(
                        data['error'].toString(),
                        style: TextStyle(fontSize: 11, color: Colors.red[800], fontFamily: 'monospace'),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail {
  final String label;
  final String value;
  _Detail(this.label, this.value);
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  const _DetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(color: Colors.grey[500])),
            TextSpan(text: value, style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  static const Map<String, Color> _colors = {
    'boss': Color(0xFF6C3483),
    'agent': Color(0xFF1A5276),
    'superagent': Color(0xFF0E6655),
    'technician': Color(0xFF784212),
    'homeuser': Color(0xFF1F618D),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[role] ?? Colors.grey[700]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        role,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
