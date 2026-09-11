import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../controllers/ApiService.dart';
import '../services/SiteService.dart';
import '../services/MikroTikMonitorService.dart';
import '../theme/app_theme.dart';
import 'SiteRegistrationScreen.dart';
import 'FieldDetailsScreen.dart';

class SiteOverviewScreen extends StatefulWidget {
  final String siteId;
  const SiteOverviewScreen({super.key, required this.siteId});
  @override
  State<SiteOverviewScreen> createState() => _SiteOverviewScreenState();
}

class _SiteOverviewScreenState extends State<SiteOverviewScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _siteStream;
  int _voucherCount = 0;
  int _paymentCount = 0;
  List<Map<String, dynamic>> _allVouchers = [];
  bool _statsLoading = false;
  String? _statsLoadedFor;
  bool _mikrotikExpanded = false;
  bool _agentsExpanded = false;
  bool _customersExpanded = false;

  @override
  void initState() {
    super.initState();
    _siteStream = SiteService.streamSite(widget.siteId);
  }

  Future<void> _loadStats(String mainLoc) async {
    if (_statsLoadedFor == mainLoc || mainLoc.isEmpty) return;
    setState(() => _statsLoading = true);
    try {
      final results = await Future.wait([
        ApiService.fetchSuperAgentRecentVouchers(locations: mainLoc),
        ApiService.fetchSuperAgentPayments([mainLoc]),
      ]);
      if (mounted) {
        final vouchers = List<Map<String, dynamic>>.from(
          (results[0]['vouchers'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        setState(() {
          _allVouchers = vouchers;
          _voucherCount = vouchers.length;
          _paymentCount = (results[1]['payments'] as List? ?? []).length;
          _statsLoading = false;
          _statsLoadedFor = mainLoc;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _siteStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(appBar: AppBar(title: const Text('Site')), body: const Center(child: Text('Site not found.')));
        }
        final data = snap.data!.data()!;
        final name = data['name'] as String? ?? 'Site';
        final mainLoc = data['main_location'] as String? ?? '';
        final physical = data['physical_location'] as String? ?? '';
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        final equipment = List<Map<String, dynamic>>.from(
            (data['equipment'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []);
        final agentIds = List<String>.from(data['agent_ids'] ?? []);
        final customerIds = List<String>.from(data['home_customer_ids'] ?? []);

        final mikrotikIds = equipment
            .where((e) => e['type'] == 'mikrotik' && (e['device_id'] as String?)?.isNotEmpty == true)
            .map((e) => e['device_id'] as String)
            .toList();

        // Trigger stats load once per location
        if (mainLoc.isNotEmpty && _statsLoadedFor != mainLoc && !_statsLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats(mainLoc));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(name),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppGradients.primaryGradient)),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Stats',
                onPressed: () {
                  setState(() => _statsLoadedFor = null);
                  _loadStats(mainLoc);
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Site',
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SiteRegistrationScreen(existingId: widget.siteId, existingData: data),
                )),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Site Info Card ─────────────────────────────────────────
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.location_city_rounded, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Expanded(child: Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))),
                      ]),
                      const SizedBox(height: 10),
                      _infoRow(Icons.place_outlined, mainLoc.isEmpty ? 'No location' : mainLoc),
                      if (physical.isNotEmpty) _infoRow(Icons.map_outlined, physical),
                      if (lat != null && lng != null)
                        _infoRow(Icons.gps_fixed, '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'),
                      const SizedBox(height: 16),
                      // ── 24h Stats Row ──────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _statChip(
                              icon: Icons.receipt_long_rounded,
                              label: 'Vouchers (24h)',
                              value: _statsLoading ? '...' : '$_voucherCount',
                              color: Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statChip(
                              icon: Icons.payment_rounded,
                              label: 'Payments (24h)',
                              value: _statsLoading ? '...' : '$_paymentCount',
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── MikroTik Devices ───────────────────────────────────────
              _expandableCard(
                title: 'MikroTik Devices',
                subtitle: 'Router monitoring & traffic',
                icon: Icons.dns_rounded,
                color: Colors.indigo,
                count: mikrotikIds.length,
                expanded: _mikrotikExpanded,
                onTap: () => setState(() => _mikrotikExpanded = !_mikrotikExpanded),
              ),
              if (_mikrotikExpanded) ...[  
              const SizedBox(height: 12),
              if (mikrotikIds.isEmpty)
                _emptyBox('No MikroTik devices assigned to this site.')
              else
                StreamBuilder<QuerySnapshot>(
                  stream: MikroTikMonitorService.getMikroTikDevicesByIds(mikrotikIds),
                  builder: (context, devSnap) {
                    if (!devSnap.hasData) return const Center(child: CircularProgressIndicator());
                    if (devSnap.data!.docs.isEmpty) return _emptyBox('Devices not found in monitoring.');
                    return Column(
                      children: devSnap.data!.docs.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final status = d['status'] as String? ?? 'unknown';
                        final devName = d['name'] as String? ?? 'Unknown';
                        final ip = d['ipAddress'] as String? ?? '';
                        final loc = d['location'] as String? ?? '';
                        final lastSeen = d['lastSeen'] as Timestamp?;
                        Color statusColor;
                        IconData statusIcon;
                        switch (status) {
                          case 'online': statusColor = Colors.green; statusIcon = Icons.check_circle; break;
                          case 'offline': statusColor = Colors.red; statusIcon = Icons.cancel; break;
                          default: statusColor = Colors.orange; statusIcon = Icons.help_outline;
                        }
                        final clientsCount = (d['clients_count'] as int?)
                            ?? (d['connected_clients'] as List?)?.length
                            ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showClientsBottomSheet(context, d, devName),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Icon(statusIcon, color: statusColor, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(devName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                        Text(ip, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                        if (loc.isNotEmpty) Text(loc, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                        if (lastSeen != null)
                                          Text('Last seen: ${_formatTs(lastSeen)}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                        const SizedBox(height: 4),
                                                        Row(children: [
                                          Icon(Icons.people_outline, size: 12,
                                              color: clientsCount > 0 ? Colors.green : Colors.grey[400]),
                                          const SizedBox(width: 4),
                                          Text(
                                            clientsCount > 0
                                                ? '$clientsCount connected · tap to view'
                                                : 'Tap to view connected clients',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: clientsCount > 0 ? Colors.green : Colors.grey[400],
                                            ),
                                          ),
                                        ]),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                        child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                                      ),
                                      if (clientsCount > 0) ...[  
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.wifi_rounded, size: 12, color: Colors.green),
                                              const SizedBox(width: 3),
                                              Text('$clientsCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

              ], // end _mikrotikExpanded

              // ── Other Equipment ────────────────────────────────────────
              if (equipment.any((e) => e['type'] != 'mikrotik')) ...[
                const SizedBox(height: 20),
                _sectionHeader('Other Equipment', Icons.devices_other_outlined),
                const SizedBox(height: 12),
                ...equipment.where((e) => e['type'] != 'mikrotik').map((eq) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: Icon(EquipmentMeta.iconFor(eq['type'] as String? ?? ''), color: AppTheme.primaryColor),
                    title: Text(EquipmentMeta.labelFor(eq['type'] as String? ?? '')),
                    subtitle: Text(_equipSubtitle(eq)),
                  ),
                )),
              ],

              // ── Agents ────────────────────────────────────────────────
              const SizedBox(height: 12),
              _expandableCard(
                title: 'Assigned Agents',
                subtitle: 'Field & sales agents',
                icon: Icons.people_rounded,
                color: Colors.teal,
                count: agentIds.length,
                expanded: _agentsExpanded,
                onTap: () => setState(() => _agentsExpanded = !_agentsExpanded),
              ),
              if (_agentsExpanded) ...[  
                const SizedBox(height: 12),
                if (agentIds.isEmpty)
                  _emptyBox('No agents assigned to this site.')
                else
                  _AgentsList(agentIds: agentIds),
              ],

              // ── Home Customers ────────────────────────────────────────
              const SizedBox(height: 12),
              _expandableCard(
                title: 'Home Customers',
                subtitle: 'Home internet clients',
                icon: Icons.home_rounded,
                color: Colors.deepOrange,
                count: customerIds.length,
                expanded: _customersExpanded,
                onTap: () => setState(() => _customersExpanded = !_customersExpanded),
              ),
              if (_customersExpanded) ...[  
                const SizedBox(height: 12),
                if (customerIds.isEmpty)
                  _emptyBox('No home customers assigned to this site.')
                else
                  _HomeCustomersList(customerIds: customerIds),
              ],

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _statChip({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      ]),
    );
  }

  Widget _expandableCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int count,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(expanded ? 0.12 : 0.07), color.withOpacity(expanded ? 0.06 : 0.03)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(expanded ? 0.35 : 0.18), width: 1.2),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.10), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey.shade800)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: Icon(Icons.keyboard_arrow_down_rounded, color: color.withOpacity(0.8), size: 26),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, {bool? expanded, VoidCallback? onTap}) {
    final row = Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary))),
        if (onTap != null)
          Icon(expanded == true ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: Colors.grey.shade500, size: 20)
        else
          Container(height: 1, width: 24, color: Colors.grey.shade300),
      ],
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: row),
      );
    }
    return row;
  }

  Widget _emptyBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(msg, style: const TextStyle(color: Colors.grey))),
    );
  }

  void _showClientsBottomSheet(BuildContext context, Map<String, dynamic> deviceData, String deviceName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MikroTikClientsBottomSheet(
        deviceData: deviceData,
        deviceName: deviceName,
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  String _formatTs(Timestamp ts) {
    final date = ts.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, HH:mm').format(date);
  }

  String _equipSubtitle(Map<String, dynamic> eq) {
    final type = eq['type'] as String? ?? '';
    if (type == 'link') return eq['azimuth'] != null ? 'Azimuth: ${eq['azimuth']}°' : '';
    return [
      if ((eq['model'] as String?)?.isNotEmpty == true) 'Model: ${eq['model']}',
      if ((eq['serial_number'] as String?)?.isNotEmpty == true) 'S/N: ${eq['serial_number']}',
    ].join(' • ');
  }
}

// ── Agents list widget ────────────────────────────────────────────────────────

class _AgentsList extends StatefulWidget {
  final List<String> agentIds;
  const _AgentsList({required this.agentIds});
  @override
  State<_AgentsList> createState() => _AgentsListState();
}

class _AgentsListState extends State<_AgentsList> {
  List<Map<String, dynamic>> _agents = [];
  Map<String, int> _voucherCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. Load agent Firestore docs
      final docs = await Future.wait(
        widget.agentIds.map((id) => FirebaseFirestore.instance.collection('users').doc(id).get()),
      );
      final agents = docs.where((d) => d.exists).map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {'id': d.id, ...data};
      }).toList();

      // 2. Fetch 24h voucher count per agent using their exact location
      //    (same API call as AgentRecentLoginsScreen)
      final countEntries = await Future.wait(
        agents.map((a) async {
          final agentLoc = a['location'] as String? ?? '';
          if (agentLoc.isEmpty) return MapEntry(a['id'] as String, 0);
          try {
            final res = await ApiService.fetchSuperAgentRecentVouchers(locations: agentLoc);
            final count = (res['vouchers'] as List? ?? []).length;
            return MapEntry(a['id'] as String, count);
          } catch (_) {
            return MapEntry(a['id'] as String, 0);
          }
        }),
      );

      if (mounted) {
        setState(() {
          _agents = agents;
          _voucherCounts = Map.fromEntries(countEntries);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_agents.isEmpty) return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('Agents not found.', style: TextStyle(color: Colors.grey))));
    return Column(
      children: _agents.map((a) {
        final id = a['id'] as String;
        final name = a['name'] as String? ?? a['email'] as String? ?? id;
        final loc = a['location'] as String? ?? '';
        final vCount = _voucherCounts[id] ?? 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: AppTheme.primaryColor.withOpacity(0.1), child: const Icon(Icons.person, color: AppTheme.primaryColor)),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: loc.isNotEmpty ? Text('📍 $loc') : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: vCount > 0 ? Colors.green.withOpacity(0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: vCount > 0 ? Colors.green.withOpacity(0.4) : Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_rounded, size: 13, color: vCount > 0 ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '$vCount',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: vCount > 0 ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text('24h', style: TextStyle(fontSize: 10, color: vCount > 0 ? Colors.green.shade700 : Colors.grey)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── MikroTik Connected Clients Bottom Sheet ─────────────────────────────────

String _ouiType(String mac) {
  if (mac.length < 8) return 'unknown';
  final oui = mac.substring(0, 8).toUpperCase();
  const map = <String, String>{
    // Apple (phones)
    'A4:4C:11': 'phone', '3C:07:D2': 'phone', 'A8:BB:50': 'phone', 'F0:D1:D4': 'phone',
    '40:B3:95': 'phone', 'AC:3C:0B': 'phone', 'D0:81:7A': 'phone', '18:E7:F4': 'phone',
    'BC:92:6B': 'phone', 'F4:F1:5A': 'phone', '3C:CD:93': 'phone', '00:88:65': 'phone',
    // Samsung (phones)
    'CC:07:AB': 'phone', '1C:1B:0D': 'phone', 'B4:EF:39': 'phone', '40:F3:AA': 'phone',
    'D0:B0:EF': 'phone', '78:4F:43': 'phone', '8C:77:12': 'phone', '2C:2E:69': 'phone',
    '54:88:0E': 'phone', '70:F9:27': 'phone',
    // Huawei (phones)
    'C8:01:4A': 'phone', '4C:1F:AD': 'phone', '28:D2:44': 'phone', '00:1E:10': 'phone',
    '8C:34:FD': 'phone', 'F8:4E:73': 'phone', '90:17:AC': 'phone',
    // Xiaomi
    '28:E3:1F': 'phone', '9C:99:A0': 'phone', 'F4:8B:32': 'phone', 'AC:23:50': 'phone',
    '64:9A:BE': 'phone', '00:9E:C8': 'phone',
    // Tecno / Infinix (East Africa)
    '28:8A:1C': 'phone', 'A0:82:D3': 'phone', '78:2B:CB': 'phone',
    // OPPO / Realme
    'EC:DF:3A': 'phone', '94:65:9C': 'phone', 'C8:9A:B1': 'phone',
    // Vivo
    '58:7A:62': 'phone', 'EC:3C:BB': 'phone', '0C:82:68': 'phone',
    // Dell (laptops)
    '18:A9:9B': 'laptop', 'E4:B9:7A': 'laptop', 'F8:BC:12': 'laptop', 'BC:B1:F3': 'laptop',
    '00:1C:C0': 'laptop', '14:FE:B5': 'laptop', '08:D4:0C': 'laptop',
    // HP (laptops)
    '94:57:A5': 'laptop', '3C:D9:2B': 'laptop', 'FC:3D:DD': 'laptop', '20:6A:8A': 'laptop',
    'AC:CF:85': 'laptop', '1C:98:EC': 'laptop',
    // Lenovo
    '00:1A:6B': 'laptop', '60:67:20': 'laptop', 'D0:50:99': 'laptop', '4C:77:CB': 'laptop',
    '54:EE:75': 'laptop', 'F8:16:54': 'laptop',
    // Intel WiFi (common in laptops)
    '8C:8D:28': 'laptop', 'AC:FD:CE': 'laptop', '48:51:B7': 'laptop',
    // TP-Link (routers/APs)
    '50:C7:BF': 'router', 'A4:2B:B8': 'router', 'F8:1A:67': 'router', 'C0:25:E9': 'router',
    '1C:61:B4': 'router', '74:EA:3A': 'router', '40:4A:03': 'router', '6C:5A:B0': 'router',
    // MikroTik
    '4C:5E:0C': 'router', 'B8:69:0E': 'router', '2C:C8:DC': 'router', '48:A9:8A': 'router',
    'D4:CA:6D': 'router', 'E4:8D:8C': 'router', '6C:3B:6B': 'router',
    // Ubiquiti
    '24:A4:3C': 'router', 'F0:9F:C2': 'router', 'DC:9F:DB': 'router', '78:8A:20': 'router',
    // Asus
    '10:7B:44': 'router', '00:E0:18': 'router', 'B4:E9:B0': 'router',
    // Hikvision (cameras)
    'C0:56:27': 'camera', '44:19:1A': 'camera', 'BC:54:96': 'camera', '3C:E3:B3': 'camera',
    '54:C4:15': 'camera',
    // Dahua (cameras)
    'E0:50:9B': 'camera', 'A0:AC:7A': 'camera', '70:85:C1': 'camera',
    // Sony (TVs)
    '00:1A:80': 'tv', 'A8:E3:EE': 'tv', '10:4F:A8': 'tv', '54:42:49': 'tv',
    // LG (TVs)
    'A8:B8:6E': 'tv', '00:1E:75': 'tv', '70:C1:A3': 'tv', 'C4:36:6C': 'tv',
    // Samsung TVs
    'E4:F0:56': 'tv', 'F4:7B:5E': 'tv', '8C:71:F8': 'tv',
  };
  return map[oui] ?? 'unknown';
}

String _vendorName(String mac) {
  if (mac.length < 8) return '';
  final oui = mac.substring(0, 8).toUpperCase();
  const vendors = <String, String>{
    // Apple
    'A4:4C:11': 'Apple', '3C:07:D2': 'Apple', 'A8:BB:50': 'Apple', 'F0:D1:D4': 'Apple',
    '40:B3:95': 'Apple', 'AC:3C:0B': 'Apple', 'D0:81:7A': 'Apple', '18:E7:F4': 'Apple',
    'BC:92:6B': 'Apple', 'F4:F1:5A': 'Apple', '3C:CD:93': 'Apple', '00:88:65': 'Apple',
    // Samsung
    'CC:07:AB': 'Samsung', '1C:1B:0D': 'Samsung', 'B4:EF:39': 'Samsung', '40:F3:AA': 'Samsung',
    'D0:B0:EF': 'Samsung', '78:4F:43': 'Samsung', '8C:77:12': 'Samsung', '2C:2E:69': 'Samsung',
    '54:88:0E': 'Samsung', '70:F9:27': 'Samsung', 'E4:F0:56': 'Samsung', '8C:71:F8': 'Samsung',
    // Huawei
    'C8:01:4A': 'Huawei', '4C:1F:AD': 'Huawei', '28:D2:44': 'Huawei', '00:1E:10': 'Huawei',
    '8C:34:FD': 'Huawei', 'F8:4E:73': 'Huawei', '90:17:AC': 'Huawei',
    // Xiaomi
    '28:E3:1F': 'Xiaomi', '9C:99:A0': 'Xiaomi', 'F4:8B:32': 'Xiaomi', 'AC:23:50': 'Xiaomi',
    '64:9A:BE': 'Xiaomi', '00:9E:C8': 'Xiaomi',
    // Nokia
    'F0:D4:F7': 'Nokia', '00:17:D3': 'Nokia', 'AC:DE:48': 'Nokia', '10:68:3F': 'Nokia',
    // Tecno
    '28:8A:1C': 'Tecno', 'A0:82:D3': 'Tecno', '78:2B:CB': 'Tecno',
    // OPPO / Realme
    'EC:DF:3A': 'OPPO', '94:65:9C': 'OPPO', 'C8:9A:B1': 'Realme',
    // Vivo
    '58:7A:62': 'Vivo', 'EC:3C:BB': 'Vivo', '0C:82:68': 'Vivo',
    // Dell
    '18:A9:9B': 'Dell', 'E4:B9:7A': 'Dell', 'F8:BC:12': 'Dell', 'BC:B1:F3': 'Dell',
    '00:1C:C0': 'Dell', '14:FE:B5': 'Dell', '08:D4:0C': 'Dell',
    // HP
    '94:57:A5': 'HP', '3C:D9:2B': 'HP', 'FC:3D:DD': 'HP', '20:6A:8A': 'HP',
    'AC:CF:85': 'HP', '1C:98:EC': 'HP',
    // Lenovo
    '00:1A:6B': 'Lenovo', '60:67:20': 'Lenovo', 'D0:50:99': 'Lenovo', '4C:77:CB': 'Lenovo',
    '54:EE:75': 'Lenovo', 'F8:16:54': 'Lenovo',
    // Intel WiFi
    '8C:8D:28': 'Intel', 'AC:FD:CE': 'Intel', '48:51:B7': 'Intel',
    // TP-Link
    '50:C7:BF': 'TP-Link', 'A4:2B:B8': 'TP-Link', 'F8:1A:67': 'TP-Link', 'C0:25:E9': 'TP-Link',
    '1C:61:B4': 'TP-Link', '74:EA:3A': 'TP-Link', '40:4A:03': 'TP-Link', '6C:5A:B0': 'TP-Link',
    // MikroTik
    '4C:5E:0C': 'MikroTik', 'B8:69:0E': 'MikroTik', '2C:C8:DC': 'MikroTik', '48:A9:8A': 'MikroTik',
    'D4:CA:6D': 'MikroTik', 'E4:8D:8C': 'MikroTik', '6C:3B:6B': 'MikroTik',
    // Ubiquiti
    '24:A4:3C': 'Ubiquiti', 'F0:9F:C2': 'Ubiquiti', 'DC:9F:DB': 'Ubiquiti', '78:8A:20': 'Ubiquiti',
    // Asus
    '10:7B:44': 'Asus', '00:E0:18': 'Asus', 'B4:E9:B0': 'Asus',
    // Hikvision
    'C0:56:27': 'Hikvision', '44:19:1A': 'Hikvision', 'BC:54:96': 'Hikvision', '3C:E3:B3': 'Hikvision',
    '54:C4:15': 'Hikvision',
    // Dahua
    'E0:50:9B': 'Dahua', 'A0:AC:7A': 'Dahua', '70:85:C1': 'Dahua',
    // Sony
    '00:1A:80': 'Sony', 'A8:E3:EE': 'Sony', '10:4F:A8': 'Sony', '54:42:49': 'Sony',
    // LG
    'A8:B8:6E': 'LG', '00:1E:75': 'LG', '70:C1:A3': 'LG', 'C4:36:6C': 'LG',
  };
  return vendors[oui] ?? '';
}

bool _isRandomizedMac(String mac) {
  if (mac.length < 2) return false;
  final firstByte = int.tryParse(mac.substring(0, 2), radix: 16) ?? 0;
  return (firstByte & 0x02) != 0;
}

String _deviceLabel(String username, String mac, {String ip = '', String hostname = ''}) {
  final stripped = username.replaceAll(':', '').replaceAll('-', '');
  final isMacLogin = RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(stripped);
  if (isMacLogin || username == 'Unknown' || username.isEmpty) {
    if (hostname.isNotEmpty && !hostname.contains(':')) return hostname;
    if (_isRandomizedMac(mac)) {
      return ip.isNotEmpty ? 'Device $ip' : 'Private Device';
    }
    final vendor = _vendorName(mac);
    if (vendor.isNotEmpty) {
      final type = _ouiType(mac);
      switch (type) {
        case 'phone': return '$vendor Phone';
        case 'laptop': return '$vendor Laptop';
        case 'tv': return '$vendor TV';
        case 'camera': return '$vendor Camera';
        case 'router': return vendor;
        default: return vendor;
      }
    }
    return ip.isNotEmpty ? 'Device $ip' : 'Unknown Device';
  }
  return username;
}

IconData _deviceIconFor(String type) {
  switch (type) {
    case 'phone': return Icons.smartphone;
    case 'laptop': return Icons.laptop_mac;
    case 'tv': return Icons.tv;
    case 'camera': return Icons.videocam_outlined;
    case 'router': return Icons.router_outlined;
    default: return Icons.devices_rounded;
  }
}

Color _deviceColorFor(String type) {
  switch (type) {
    case 'phone': return Colors.blueAccent;
    case 'laptop': return Colors.indigo;
    case 'tv': return Colors.purple;
    case 'camera': return Colors.redAccent;
    case 'router': return Colors.teal;
    default: return Colors.blueGrey;
  }
}

class MikroTikClientsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> deviceData;
  final String deviceName;
  const MikroTikClientsBottomSheet({super.key, required this.deviceData, required this.deviceName});

  @override
  State<MikroTikClientsBottomSheet> createState() => _MikroTikClientsBottomSheetState();
}

class _MikroTikClientsBottomSheetState extends State<MikroTikClientsBottomSheet> {
  static const int _pageSize = 10;
  int _currentPage = 0;
  final ScrollController _listScrollCtrl = ScrollController();

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listScrollCtrl.hasClients) _listScrollCtrl.jumpTo(0);
    });
  }

  List<Map<String, dynamic>> _parseClients() {
    try {
      final raw = widget.deviceData['connected_clients'];
      if (raw == null) return [];
      Iterable items;
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = raw.values;
      } else {
        return [];
      }
      final out = <Map<String, dynamic>>[];
      for (final e in items) {
        if (e is Map) {
          out.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final allClients = _parseClients();
    final totalPages = allClients.isEmpty ? 1 : ((allClients.length - 1) ~/ _pageSize) + 1;
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, allClients.length);
    final pageClients = allClients.isEmpty ? <Map<String, dynamic>>[] : allClients.sublist(start, end);
    final updatedAt = widget.deviceData['clients_updated_at'] as Timestamp?;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.3,
      expand: false,
      builder: (_, __) => Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.router, color: Colors.green, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.deviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (updatedAt != null)
                          Text(
                            'Updated ${_relativeTime(updatedAt.toDate())}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: allClients.isNotEmpty ? Colors.green.withOpacity(0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${allClients.length} active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: allClients.isNotEmpty ? Colors.green : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            Expanded(
              child: allClients.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.devices_outlined, size: 52, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('No clients data yet', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Once the backend pushes hotspot active data to Firestore, connected clients will appear here automatically.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: _listScrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: pageClients.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
                      itemBuilder: (_, i) {
                        try {
                          return _ClientTile(client: pageClients[i]);
                        } catch (e) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Text('Client #$i error: $e', style: const TextStyle(fontSize: 11, color: Colors.red)),
                          );
                        }
                      },
                    ),
            ),
            if (totalPages > 1)
              SafeArea(
                top: false,
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
                      color: AppTheme.primaryColor,
                    ),
                    Expanded(
                      child: Text(
                        'Page ${_currentPage + 1} of $totalPages  •  ${allClients.length} clients',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPage < totalPages - 1 ? () => _goToPage(_currentPage + 1) : null,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
              ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ClientTile extends StatelessWidget {
  final Map<String, dynamic> client;
  const _ClientTile({required this.client});

  static String _str(dynamic v) => v == null ? '' : v.toString();
  static int _int(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
    return 0;
  }
  static String _firstNonEmpty(List<String> values) {
    for (final v in values) { if (v.isNotEmpty) return v; }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final rawUser = _firstNonEmpty([_str(client['user']), _str(client['username'])]);
    final username = rawUser.isEmpty ? 'Unknown' : rawUser;
    final ip = _firstNonEmpty([_str(client['address']), _str(client['ip_address']), _str(client['ip'])]);
    final mac = _firstNonEmpty([_str(client['mac-address']), _str(client['mac_address']), _str(client['mac'])]).toUpperCase();
    final bytesIn = _int(client['bytes-in']) != 0 ? _int(client['bytes-in']) : _int(client['bytes_in']);
    final bytesOut = _int(client['bytes-out']) != 0 ? _int(client['bytes-out']) : _int(client['bytes_out']);
    final uptime = _str(client['uptime']);
    final idleTime = _firstNonEmpty([_str(client['idle-time']), _str(client['idle_time'])]);
    final hostname = _firstNonEmpty([_str(client['host-name']), _str(client['hostname'])]).trim();

    final deviceType = _ouiType(mac);
    final iconData = _deviceIconFor(deviceType);
    final iconColor = _deviceColorFor(deviceType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(iconData, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_deviceLabel(username, mac, ip: ip, hostname: hostname), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                if (ip.isNotEmpty)
                  Text(ip, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                if (mac.isNotEmpty)
                  Text(mac, style: TextStyle(fontSize: 11, color: Colors.grey[500], letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Row(children: [
                  _badge(Icons.arrow_downward_rounded, Colors.green,
                      _SiteOverviewScreenState._formatBytes(bytesOut)),
                  const SizedBox(width: 8),
                  _badge(Icons.arrow_upward_rounded, Colors.orange,
                      _SiteOverviewScreenState._formatBytes(bytesIn)),
                  if (uptime.isNotEmpty) ...[  
                    const SizedBox(width: 8),
                    _badge(Icons.timer_outlined, Colors.blue, uptime),
                  ],
                ]),
                if (idleTime.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('idle: $idleTime', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 2),
      Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]);
  }
}

class _HomeCustomersList extends StatefulWidget {
  final List<String> customerIds;
  const _HomeCustomersList({required this.customerIds});
  @override
  State<_HomeCustomersList> createState() => _HomeCustomersListState();
}

class _HomeCustomersListState extends State<_HomeCustomersList> {
  List<Map<String, dynamic>> _customers = [];
  final Map<String, Map<String, dynamic>> _clientsData = {};
  bool _loading = true;

  static String _fmt(int? bytes) {
    if (bytes == null || bytes == 0) return '0 B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  static String _fmtBps(num bps) {
    if (bps < 1000) return '${bps.toStringAsFixed(0)} bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)} Kbps';
    return '${(bps / 1000000).toStringAsFixed(2)} Mbps';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final futures = widget.customerIds.map((id) =>
          FirebaseFirestore.instance.collection('home_customers').doc(id).get());
      final docs = await Future.wait(futures);
      if (mounted) {
        setState(() {
          _customers = docs.where((d) => d.exists).map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {'id': d.id, ...data};
          }).toList();
          _loading = false;
        });
      }
      // Usage is loaded per card on tap to avoid N+1 Firestore reads.
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadConsumption(String customerId) async {
    try {
      // Step 1: get the field registration for this customer to find their IP
      final regSnap = await FirebaseFirestore.instance
          .collection('field_registrations')
          .where('owner_id', isEqualTo: customerId)
          .limit(1)
          .get();
      if (regSnap.docs.isEmpty) return;

      // Step 2: extract the first equipment IP
      final equipment = List<Map<String, dynamic>>.from(
          (regSnap.docs.first.data()['equipment'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)));
      String? ip;
      for (final eq in equipment) {
        final eqIp = eq['ip_address'] as String?;
        if (eqIp != null && eqIp.trim().isNotEmpty) {
          ip = eqIp.trim();
          break;
        }
      }
      if (ip == null) return;

      // Step 3: look up home_clients by IP
      final clientSnap = await FirebaseFirestore.instance
          .collection('home_clients')
          .where('ip', isEqualTo: ip)
          .limit(1)
          .get();
      if (clientSnap.docs.isEmpty || !mounted) return;
      setState(() => _clientsData[customerId] = clientSnap.docs.first.data());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_customers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Text('Customers not found.', style: TextStyle(color: Colors.grey))),
      );
    }
    return Column(
      children: _customers.map((c) {
        final name = c['name'] as String? ?? c['full_name'] as String? ?? c['id'] as String;
        final zone  = c['zone'] as String? ?? '';
        final plan  = c['current_plan'] as String? ?? '';
        final custId = c['id'] as String;
        final cd = _clientsData[custId];
        final lastTs = cd?['last_seen'] as Timestamp?;
        final isOnline = lastTs != null &&
            DateTime.now().difference(lastTs.toDate()).inMinutes < 4;
        final dlBps   = cd?['download_bps_5min'] as num?;
        final todayDl = cd?['today_download_bytes'] as int?;
        final todayUl = cd?['today_upload_bytes'] as int?;
        final monDl   = cd?['month_download_bytes'] as int?;
        final monUl   = cd?['month_upload_bytes'] as int?;
        final weekDl  = cd?['week_download_bytes'] as int?;
        final weekUl  = cd?['week_upload_bytes'] as int?;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: cd != null
                ? BorderSide(color: isOnline ? Colors.green.shade200 : Colors.grey.shade300)
                : BorderSide.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                onTap: () => _loadConsumption(custId),
                leading: CircleAvatar(
                  backgroundColor: cd != null
                      ? (isOnline ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1))
                      : Colors.teal.withOpacity(0.1),
                  child: Icon(Icons.home,
                      color: cd != null ? (isOnline ? Colors.green : Colors.grey) : Colors.teal),
                ),
                title: Row(children: [
                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (cd != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green.shade100 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOnline ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold,
                          color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                ]),
                subtitle: Text(
                  [if (zone.isNotEmpty) '📍 $zone', if (plan.isNotEmpty) '📶 $plan'].join('  •  '),
                ),
              ),
              if (cd != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (dlBps != null && dlBps > 0)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.speed_rounded, size: 12, color: Colors.blue),
                          const SizedBox(width: 3),
                          Text(_fmtBps(dlBps),
                              style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600)),
                        ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.today_rounded, size: 11, color: Colors.green),
                        const SizedBox(width: 3),
                        const Text('Today ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('↓${_fmt(todayDl)} ↑${_fmt(todayUl)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black87)),
                      ]),
                      if (weekDl != null || weekUl != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.date_range_rounded, size: 11, color: Colors.orange),
                          const SizedBox(width: 3),
                          const Text('Week ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('↓${_fmt(weekDl)} ↑${_fmt(weekUl)}',
                              style: const TextStyle(fontSize: 11, color: Colors.black87)),
                        ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.calendar_month_rounded, size: 11, color: Colors.purple),
                        const SizedBox(width: 3),
                        const Text('Month ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('↓${_fmt(monDl)} ↑${_fmt(monUl)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ]),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
