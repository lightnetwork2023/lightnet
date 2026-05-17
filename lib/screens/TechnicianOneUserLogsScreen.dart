import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

/// Boss-only: reads `technician_one_user_logs` with filter + name resolution.
class TechnicianOneUserLogsScreen extends StatefulWidget {
  const TechnicianOneUserLogsScreen({super.key});

  @override
  State<TechnicianOneUserLogsScreen> createState() =>
      _TechnicianOneUserLogsScreenState();
}

class _TechnicianOneUserLogsScreenState
    extends State<TechnicianOneUserLogsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _dateFmt = DateFormat('dd MMM yyyy, HH:mm');
  final _monthFmt = DateFormat('MMMM yyyy');

  /// uid -> display name  (populated eagerly + lazily as new UIDs appear in logs)
  Map<String, String> _techNames = {};
  bool _namesLoaded = false;
  /// UIDs already fetched individually so we don't repeat lookups
  final Set<String> _resolvedUids = {};

  // Filters
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  String? _selectedUid; // null = all technicians
  DateTime? _selectedDay; // null = whole month

  // Generate last 12 months as options
  List<String> get _monthOptions {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return DateFormat('yyyy-MM').format(d);
    });
  }

  String _monthLabel(String ym) {
    final parts = ym.split('-');
    if (parts.length < 2) return ym;
    final d = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    return _monthFmt.format(d);
  }

  String _techLabel(String uid) => _techNames[uid] ?? uid;

  @override
  void initState() {
    super.initState();
    _loadTechnicianNames();
  }

  Future<void> _loadTechnicianNames() async {
    // Eager load: fetch all users with role 'technician'
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'technician')
          .get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] ?? '').toString().trim();
        map[doc.id] = name.isNotEmpty ? name : doc.id;
        _resolvedUids.add(doc.id);
      }
      if (mounted) setState(() { _techNames = map; _namesLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _namesLoaded = true);
    }
  }

  /// For any UIDs that appeared in logs but were not in the initial query
  /// (different role value, role changed, etc.) fetch them one by one.
  Future<void> _resolveUnknownUids(List<String> uids) async {
    final missing = uids
        .toSet()
        .where((uid) => uid.isNotEmpty && !_resolvedUids.contains(uid))
        .toList();
    if (missing.isEmpty) return;

    // Mark as resolving immediately so we don't double-fetch
    _resolvedUids.addAll(missing);

    final futures = missing.map((uid) async {
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (doc.exists) {
          final name = (doc.data()?['name'] ?? '').toString().trim();
          return MapEntry(uid, name.isNotEmpty ? name : uid);
        }
      } catch (_) {}
      return MapEntry(uid, uid); // fallback: show uid
    });

    final entries = await Future.wait(futures);
    if (mounted) {
      setState(() {
        for (final e in entries) {
          _techNames[e.key] = e.value;
        }
      });
    }
  }

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q = _firestore
        .collection('technician_one_user_logs')
        .orderBy('created_at', descending: true)
        .limit(500);

    // month or day filter
    if (_selectedDay != null) {
      final dayStr = DateFormat('yyyy-MM-dd').format(_selectedDay!);
      q = q.where('day', isEqualTo: dayStr);
    } else {
      q = q.where('month', isEqualTo: _selectedMonth);
    }

    if (_selectedUid != null) {
      q = q.where('technician_uid', isEqualTo: _selectedUid);
    }
    return q;
  }

  Future<void> _pickDay() async {
    final parts = _selectedMonth.split('-');
    final base = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final lastDay = DateTime(base.year, base.month + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? base,
      firstDate: base,
      lastDate: lastDay,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDay = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    if (!auth.isBoss) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generation logs')),
        body: const Center(child: Text('Boss access only.')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Technician voucher logs'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          if (_selectedDay != null || _selectedUid != null)
            TextButton(
              onPressed: () => setState(() {
                _selectedDay = null;
                _selectedUid = null;
              }),
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _errorView(snap.error.toString());
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                // Resolve any UIDs not yet in the names map (lazy, one-off fetch)
                final unknownUids = docs
                    .map((d) => d.data()['technician_uid']?.toString() ?? '')
                    .where((uid) =>
                        uid.isNotEmpty && !_resolvedUids.contains(uid))
                    .toList();
                if (unknownUids.isNotEmpty) {
                  // fire-and-forget; setState inside will rebuild with names
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _resolveUnknownUids(unknownUids));
                }
                if (docs.isEmpty) return _emptyView();
                return _buildList(docs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: month dropdown + day picker button
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedMonth,
                  decoration: InputDecoration(
                    labelText: 'Month',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _monthOptions
                      .map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedMonth = v;
                        _selectedDay = null; // reset day when month changes
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: _selectedDay != null ? AppTheme.primaryColor : AppTheme.textSecondary,
                ),
                label: Text(
                  _selectedDay != null
                      ? DateFormat('dd MMM').format(_selectedDay!)
                      : 'Pick day',
                  style: TextStyle(
                    color: _selectedDay != null ? AppTheme.primaryColor : AppTheme.textSecondary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _selectedDay != null
                        ? AppTheme.primaryColor
                        : Colors.grey.shade300,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _pickDay,
              ),
              if (_selectedDay != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _selectedDay = null),
                  tooltip: 'Clear day',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ],
          ),
          // Row 2: technician filter chips
          if (_namesLoaded && _techNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(
                    label: 'All technicians',
                    selected: _selectedUid == null,
                    onTap: () => setState(() => _selectedUid = null),
                  ),
                  ..._techNames.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _filterChip(
                          label: e.value,
                          selected: _selectedUid == e.key,
                          onTap: () => setState(() =>
                              _selectedUid = _selectedUid == e.key ? null : e.key),
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // Group by day for section headers
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final d = doc.data();
      final day = d['day']?.toString() ?? '—';
      groups.putIfAbsent(day, () => []).add(d);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: days.length,
      itemBuilder: (context, di) {
        final day = days[di];
        final items = groups[day]!;
        // Parse day label
        String dayLabel = day;
        try {
          final dt = DateFormat('yyyy-MM-dd').parse(day);
          dayLabel = DateFormat('EEEE, dd MMMM yyyy').format(dt);
        } catch (_) {}

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header with count badge
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dayLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            ...items.map((d) => _buildCard(d)),
          ],
        );
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> d) {
    final when = _formatTime(d['created_at']);
    final uid = d['technician_uid']?.toString() ?? '';
    final techName = _techNames[uid] ?? uid; // ← show name, fallback to uid
    final voucher = d['username']?.toString() ?? '';
    final dur = d['duration_key']?.toString() ?? '';
    final speed = d['speed_limit']?.toString() ?? '10M/10M';

    final durLabel = {
      '3h': '3 hours',
      '1d': '1 day',
    }[dur] ?? dur;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.confirmation_number_outlined,
                  color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Voucher code + time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          voucher,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        when,
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Technician name
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 13, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        techName,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Tags
                  Wrap(
                    spacing: 6,
                    children: [
                      _tag(Icons.timer_outlined, durLabel, AppTheme.infoColor),
                      _tag(Icons.speed_outlined, speed, AppTheme.successColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _emptyView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'No logs for this period',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      );

  Widget _errorView(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
              const SizedBox(height: 8),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.errorColor, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  String _formatTime(dynamic value) {
    if (value is Timestamp) return _dateFmt.format(value.toDate().toLocal());
    if (value is DateTime) return _dateFmt.format(value.toLocal());
    return value?.toString() ?? '—';
  }
}
