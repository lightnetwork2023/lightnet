import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../controllers/auth_controller.dart';
import '../controllers/ApiService.dart';
import '../theme/app_theme.dart';

class TechnicianVoucherScreen extends StatefulWidget {
  const TechnicianVoucherScreen({Key? key}) : super(key: key);

  @override
  State<TechnicianVoucherScreen> createState() =>
      _TechnicianVoucherScreenState();
}

class _TechnicianVoucherScreenState extends State<TechnicianVoucherScreen> {
  static const _col = 'technician_vouchers';
  static const int _maxPerAgent = 2;
  static const int _voucherDays = 31;
  static const String _voucherSpeed = '10M/10M';

  final AuthController _auth = Get.find<AuthController>();
  final _db = FirebaseFirestore.instance;

  // Selected agent
  Map<String, dynamic>? _selectedAgent;
  String? _selectedAgentId;

  // All agents loaded once
  List<Map<String, dynamic>> _agents = [];
  bool _agentsLoaded = false;

  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    final snap = await _db
        .collection('users')
        .where('role', whereIn: ['agent', 'superagent']).get();
    if (mounted) {
      setState(() {
        _agents = snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        _agentsLoaded = true;
      });
    }
  }

  // Stream all vouchers for this agent — filter client-side (no composite index needed)
  Stream<QuerySnapshot<Map<String, dynamic>>> _agentVouchersStream(
      String agentId) {
    return _db
        .collection(_col)
        .where('agent_id', isEqualTo: agentId)
        .snapshots();
  }

  Future<void> _createVoucher(int currentCount) async {
    if (_selectedAgent == null || _selectedAgentId == null) return;
    if (currentCount >= _maxPerAgent) return;

    final location = _selectedAgent!['location'] as String? ?? '';
    if (location.isEmpty) {
      _snack('Agent has no location set. Cannot create voucher.');
      return;
    }

    setState(() => _creating = true);
    try {
      // Snapshot valid users BEFORE creation to find the new one after
      ApiService.clearCacheKey('valid_users_$location');
      final List<dynamic> beforeUsers =
          await ApiService.fetchValidUsers(location);
      final beforeUsernames = beforeUsers
          .map((u) => u['username']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();

      final result = await ApiService.generateUsers(
        numUsers: 1,
        numDays: _voucherDays.toDouble(),
        location: location,
        speedLimit: _voucherSpeed,
      );

      final msg = result['message'] as String? ?? 'Voucher created';

      // Fetch users AFTER creation — find the new username by diff
      String? newUsername;
      try {
        final List<dynamic> afterUsers =
            await ApiService.fetchValidUsers(location);
        final newEntry = afterUsers.firstWhere(
          (u) => !beforeUsernames.contains(u['username']?.toString() ?? ''),
          orElse: () => null,
        );
        newUsername = newEntry?['username']?.toString();
      } catch (_) {}

      await _db.collection(_col).add({
        'agent_id': _selectedAgentId,
        'agent_name': _selectedAgent!['name'] ?? '',
        'agent_location': location,
        'technician_id': _auth.user?.uid ?? '',
        'technician_name': _auth.userName.isNotEmpty
            ? _auth.userName
            : (_auth.user?.displayName ?? _auth.user?.email ?? 'Technician'),
        'created_at': FieldValue.serverTimestamp(),
        'expires_at': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: _voucherDays))),
        'used': false,
        'speed': _voucherSpeed,
        'days': _voucherDays,
        'response_message': msg,
        'username': newUsername ?? '',
      });

      _snack('Voucher created successfully!');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // Auto-detect used vouchers: check expiry + backend status
  Future<void> _autoCheckUsedStatus(String agentId,
      String agentLocation) async {
    try {
      final now = DateTime.now();
      final snap = await _db
          .collection(_col)
          .where('agent_id', isEqualTo: agentId)
          .where('used', isEqualTo: false)
          .get();

      // Build a map of username -> used status from backend
      final Map<String, bool> backendUsed = {};
      if (agentLocation.isNotEmpty) {
        try {
          ApiService.clearCacheKey(
              'super_agent_recent_vouchers_$agentLocation');
          final res = await ApiService.fetchSuperAgentRecentVouchers(
              locations: agentLocation);
          final vouchers = res['vouchers'] as List? ?? [];
          for (final v in vouchers) {
            final uname = v['username'] as String?;
            if (uname == null) continue;
            final usedVal = v['used'];
            backendUsed[uname] =
                usedVal == 1 || usedVal == true || usedVal == '1';
          }
        } catch (_) {}
      }

      for (final doc in snap.docs) {
        final data = doc.data();
        // 1. Auto-expire if expires_at has passed
        final expiresTs = data['expires_at'] as Timestamp?;
        if (expiresTs != null && expiresTs.toDate().isBefore(now)) {
          await doc.reference.update({'used': true});
          continue;
        }
        // 2. Check backend usage via stored username
        final username = data['username'] as String?;
        if (username != null &&
            username.isNotEmpty &&
            backendUsed[username] == true) {
          await doc.reference.update({'used': true});
        }
      }
    } catch (_) {}
  }

  Future<void> _pickAgent() async {
    if (!_agentsLoaded) {
      _snack('Loading agents, please wait…');
      return;
    }
    String query = '';
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bsCtx) => StatefulBuilder(
        builder: (bsCtx, setBs) {
          final filtered = query.isEmpty
              ? _agents
              : _agents.where((a) {
                  final name =
                      (a['name'] as String? ?? '').toLowerCase();
                  final loc =
                      (a['location'] as String? ?? '').toLowerCase();
                  final q = query.toLowerCase();
                  return name.contains(q) || loc.contains(q);
                }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, sc) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.person_search,
                        color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    const Text('Select Agent',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bsCtx)),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by name or location…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setBs(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No results',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            controller: sc,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final a = filtered[i];
                              final role =
                                  a['role'] as String? ?? '';
                              final selected =
                                  _selectedAgentId == a['id'];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: role == 'superagent'
                                      ? Colors.purple.shade100
                                      : Colors.blue.shade100,
                                  child: Icon(
                                    role == 'superagent'
                                        ? Icons.supervisor_account
                                        : Icons.person,
                                    color: role == 'superagent'
                                        ? Colors.purple
                                        : Colors.blue,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                    a['name'] as String? ?? 'Unknown',
                                    style: TextStyle(
                                        fontWeight: selected
                                            ? FontWeight.bold
                                            : FontWeight.normal)),
                                subtitle: Text(
                                    a['location'] as String? ?? '',
                                    style: const TextStyle(
                                        fontSize: 12)),
                                selected: selected,
                                selectedTileColor:
                                    AppTheme.primaryColor.withOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                onTap: () => Navigator.pop(bsCtx, a),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != null) {
      setState(() {
        _selectedAgent = result;
        _selectedAgentId = result['id'] as String?;
      });
      // Background: auto-check used status for this agent
      final loc = result['location'] as String? ?? '';
      _autoCheckUsedStatus(result['id'] as String, loc);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Agent Voucher'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Agent Selector ──────────────────────────────────
          InkWell(
            onTap: _pickAgent,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Select Agent / Super Agent',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixIcon: _agentsLoaded
                    ? const Icon(Icons.arrow_drop_down)
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )),
                prefixIcon: const Icon(Icons.person_search,
                    color: AppTheme.primaryColor),
              ),
              child: Text(
                _selectedAgent != null
                    ? '${_selectedAgent!['name']}  –  ${_selectedAgent!['location'] ?? ''}'
                    : 'Tap to select…',
                style: TextStyle(
                  color: _selectedAgent != null
                      ? Colors.black87
                      : Colors.grey,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Content when agent selected ─────────────────────
          if (_selectedAgentId != null) ...[
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _agentVouchersStream(_selectedAgentId!),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ));
                }

                final allDocs = snap.data?.docs ?? [];
                final since =
                    DateTime.now().subtract(const Duration(days: 30));

                // Client-side: count within last 30 days
                final count = allDocs.where((d) {
                  final ts = d.data()['created_at'] as Timestamp?;
                  if (ts == null) return false;
                  return ts.toDate().isAfter(since);
                }).length;

                // Client-side: unused vouchers only
                final unusedDocs = allDocs.where((d) {
                  return d.data()['used'] == false;
                }).toList();
                unusedDocs.sort((a, b) {
                  final aTs = a.data()['created_at'] as Timestamp?;
                  final bTs = b.data()['created_at'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return bTs.compareTo(aTs);
                });

                final limitReached = count >= _maxPerAgent;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Quota card ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: limitReached
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: limitReached
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            limitReached
                                ? Icons.block
                                : Icons.check_circle_outline,
                            color: limitReached
                                ? Colors.red
                                : Colors.green.shade700,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$count / $_maxPerAgent vouchers created in the last 30 days',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: limitReached
                                        ? Colors.red.shade700
                                        : Colors.green.shade800,
                                  ),
                                ),
                                if (limitReached)
                                  const Text(
                                    'Limit reached. No more vouchers for this agent this month.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.redAccent),
                                  )
                                else
                                  Text(
                                    '${_maxPerAgent - count} remaining  •  31 days  •  10 Mbps',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green.shade700),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Create button ───────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: limitReached
                              ? Colors.grey.shade300
                              : AppTheme.primaryColor,
                          foregroundColor: limitReached
                              ? Colors.grey.shade600
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed:
                            (limitReached || _creating)
                                ? null
                                : () => _createVoucher(count),
                        icon: _creating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.add_card),
                        label: Text(_creating
                            ? 'Creating…'
                            : 'Create Voucher (31 days · 10 Mbps)'),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Unused Vouchers ─────────────────────
                    const Text(
                      'Unused Vouchers for this Agent',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.primaryColor),
                    ),
                    const SizedBox(height: 8),

                    if (unusedDocs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(
                          child: Text('No unused vouchers yet',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      Column(
                        children: unusedDocs.map((doc) {
                          final data = doc.data();
                          final createdTs =
                              data['created_at'] as Timestamp?;
                          final expiresTs =
                              data['expires_at'] as Timestamp?;
                          final createdStr = createdTs != null
                              ? DateFormat('dd MMM yyyy  HH:mm')
                                  .format(createdTs.toDate())
                              : '—';
                          final expiresStr = expiresTs != null
                              ? DateFormat('dd MMM yyyy')
                                  .format(expiresTs.toDate())
                              : '—';
                          final techName =
                              data['technician_name'] as String? ?? '—';
                          final msg =
                              data['response_message'] as String? ?? '';

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                          Icons.card_giftcard,
                                          color: Colors.orange,
                                          size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Voucher',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          Text(
                                              '31 days  •  10 Mbps  •  Expires $expiresStr',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                            color:
                                                Colors.orange.shade300),
                                      ),
                                      child: const Text('Unused',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange,
                                              fontWeight:
                                                  FontWeight.w600)),
                                    ),
                                  ]),
                                  const Divider(height: 16),
                                  _infoRow(Icons.schedule, 'Created',
                                      createdStr),
                                  if (techName.isNotEmpty)
                                    _infoRow(Icons.person_outline,
                                        'By', techName),
                                  if (data['username'] != null &&
                                      (data['username'] as String)
                                          .isNotEmpty)
                                    _infoRow(Icons.confirmation_number,
                                        'Voucher #',
                                        data['username'] as String),
                                  if (msg.isNotEmpty)
                                    _infoRow(Icons.info_outline,
                                        'Response', msg),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                );
              },
            ),
          ] else ...[
            // ── No agent selected placeholder ─────────────────
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Column(
                children: [
                  Icon(Icons.person_search,
                      size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Select an agent above',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 6),
                  Text(
                      'You can create up to 2 vouchers per agent every 30 days',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black87))),
        ],
      ),
    );
  }
}
