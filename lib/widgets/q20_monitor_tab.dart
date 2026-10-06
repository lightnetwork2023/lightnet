import 'package:flutter/material.dart';

import '../screens/Q20DeviceScreen.dart';
import '../services/Q20MonitorService.dart';
import '../theme/app_theme.dart';

/// Q20 fleet list + summary (no AppBar). Shared by HomeScreen and TechnicianHomeScreen.
class Q20MonitorContent extends StatefulWidget {
  const Q20MonitorContent({super.key});

  @override
  State<Q20MonitorContent> createState() => _Q20MonitorContentState();
}

class _Q20MonitorContentState extends State<Q20MonitorContent> {
  String _filter = 'all';
  String _query = '';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _routers = [];
  int _online = 0;
  int _offline = 0;
  int _pendingAdopt = 0;
  int _meshDown = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _routers.isEmpty;
      _error = null;
    });
    try {
      final data = await Q20MonitorService.listRouters();
      final routers = ((data['routers'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _routers = routers;
        _online = data['online'] as int? ?? routers.where((r) => r['online'] == true).length;
        _offline = data['offline'] as int? ?? routers.where((r) => r['online'] != true).length;
        _pendingAdopt = data['pending_adopt'] as int? ??
            routers.where((r) => r['needs_adopt'] == true).length;
        _meshDown = data['mesh_down'] as int? ??
            routers.where((r) => (r['mesh_offline'] as int? ?? 0) > 0).length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_routers);
    if (_filter == 'online') {
      list = list.where((r) => r['online'] == true).toList();
    } else if (_filter == 'offline') {
      list = list.where((r) => r['online'] != true).toList();
    } else if (_filter == 'adopt') {
      list = list.where((r) => r['needs_adopt'] == true).toList();
    } else if (_filter == 'mesh_down') {
      list = list.where((r) => _meshOfflineCount(r) > 0).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final hay = [
          r['name'],
          r['hostname'],
          r['mac'],
          r['wg_ip'],
          r['site_name'],
          r['owner_email'],
          ..._meshOfflineNames(r),
        ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
        return hay.contains(q);
      }).toList();
    }
    list.sort((a, b) {
      final aMesh = _meshOfflineCount(a);
      final bMesh = _meshOfflineCount(b);
      if (aMesh != bMesh) return bMesh.compareTo(aMesh);
      final aOff = a['online'] == true ? 1 : 0;
      final bOff = b['online'] == true ? 1 : 0;
      if (aOff != bOff) return aOff.compareTo(bOff);
      return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
    });
    return list;
  }

  int _meshOfflineCount(Map<String, dynamic> r) {
    return r['mesh_offline'] as int? ?? _meshOfflineNames(r).length;
  }

  List<String> _meshOfflineNames(Map<String, dynamic> r) {
    final named = r['mesh_offline_names'];
    if (named is List) {
      return named.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    final mesh = r['mesh'] ?? r['satellites'] ?? r['topology'];
    if (mesh is! List) return const [];
    final names = <String>[];
    for (final item in mesh) {
      if (item is! Map) continue;
      if (item['role'] == 'main') continue;
      final online = item['online'] == true || item['online'] == 1;
      if (online) continue;
      final label = (item['name'] ?? item['hostname'] ?? item['mac'] ?? 'AP').toString();
      if (label.trim().isNotEmpty) names.add(label);
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filters(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppTheme.primaryColor,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search name, MAC, IP…',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('All', 'all'),
                const SizedBox(width: 8),
                _chip('Online', 'online'),
                const SizedBox(width: 8),
                _chip('Offline', 'offline'),
                const SizedBox(width: 8),
                _chip('Mesh down', 'mesh_down'),
                const SizedBox(width: 8),
                _chip('Needs adopt', 'adopt'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      backgroundColor: Colors.grey[200],
      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryColor,
      labelStyle: TextStyle(
        color: selected ? AppTheme.primaryColor : AppTheme.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())],
      );
    }
    if (_error != null && _routers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
    }
    final filtered = _filtered;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _summary('Online', _online.toString(), Colors.green, Icons.check_circle_outline),
            const SizedBox(width: 8),
            _summary('Offline', _offline.toString(), Colors.red, Icons.cancel_outlined),
            const SizedBox(width: 8),
            _summary('Mesh down', _meshDown.toString(), Colors.red, Icons.device_hub_outlined),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              children: [
                Icon(Icons.router_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No Q20 devices found', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          )
        else
          ...filtered.map(_card),
      ],
    );
  }

  Widget _summary(String label, String count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: color.withOpacity(0.85))),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final online = r['online'] == true;
    final statusColor = online ? Colors.green : Colors.red;
    final name = r['name']?.toString() ?? r['hostname']?.toString() ?? 'Q20';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Q20DeviceScreen(
                routerId: r['id'] as int,
                initial: r,
              ),
            ),
          );
          if (mounted) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(online ? Icons.check_circle : Icons.cancel, color: statusColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            online ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(r['mac']?.toString() ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    Text(
                      '${r['wg_ip'] ?? ''}  ·  ${r['fw_build'] ?? r['fw_version'] ?? ''}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    _meshStatusLine(r),
                    if (r['needs_adopt'] == true) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Adopt available',
                        style: TextStyle(fontSize: 12, color: AppTheme.warningColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meshStatusLine(Map<String, dynamic> r) {
    final total = r['mesh_total'] as int? ?? 0;
    final meshOnline = r['mesh_online'] as int? ?? 0;
    final offlineNames = _meshOfflineNames(r);
    final offline = r['mesh_offline'] as int? ?? offlineNames.length;
    if (total == 0 && offlineNames.isEmpty) {
      return const Text('No meshed access points', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    const size = TextStyle(fontSize: 12);
    Widget count;
    if (offline == 0) {
      count = Text(
        meshOnline == 1 ? '1 meshed AP online' : '$meshOnline meshed APs online',
        style: size.copyWith(color: Colors.green, fontWeight: FontWeight.w600),
      );
    } else if (meshOnline == 0) {
      count = Text(
        offline == 1 ? '1 meshed AP offline' : '$offline meshed APs offline',
        style: size.copyWith(color: Colors.red, fontWeight: FontWeight.w700),
      );
    } else {
      count = Text.rich(
        TextSpan(
          style: size,
          children: [
            TextSpan(text: '$meshOnline online', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
            const TextSpan(text: ' · ', style: TextStyle(color: Colors.grey, fontSize: 12)),
            TextSpan(text: '$offline offline', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.device_hub, size: 14, color: offline > 0 ? Colors.red : Colors.green),
            const SizedBox(width: 4),
            Expanded(child: count),
          ],
        ),
        if (offlineNames.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            offlineNames.map((n) => '$n offline').join(' · '),
            style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
