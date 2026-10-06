import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/Q20MonitorService.dart';
import '../theme/app_theme.dart';

class Q20DeviceScreen extends StatefulWidget {
  final int routerId;
  final Map<String, dynamic>? initial;

  const Q20DeviceScreen({super.key, required this.routerId, this.initial});

  @override
  State<Q20DeviceScreen> createState() => _Q20DeviceScreenState();
}

class _Q20DeviceScreenState extends State<Q20DeviceScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _router = {};
  Map<String, dynamic> _live = {};
  Map<String, dynamic> _login = {};
  List<dynamic> _events = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _router = Map<String, dynamic>.from(widget.initial!);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _router.isEmpty;
      _error = null;
    });
    try {
      final data = await Q20MonitorService.getRouter(widget.routerId);
      if (!mounted) return;
      setState(() {
        _router = Map<String, dynamic>.from(data['router'] as Map? ?? _router);
        _live = Map<String, dynamic>.from(data['live'] as Map? ?? {});
        _login = Map<String, dynamic>.from(data['login'] as Map? ?? {});
        _events = (data['events'] as List?) ?? [];
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

  bool get _online => _router['online'] == true;

  List<Map<String, dynamic>> get _pending {
    final raw = _router['pending_adopt'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> get _topology {
    final raw = _router['topology'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> get _satellites {
    final raw = _router['satellites'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<void> _snack(String message, {bool error = false}) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.errorColor : AppTheme.primaryColor,
      ),
    );
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      await _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename({String? mac, String? current}) async {
    final controller = TextEditingController(text: current ?? (_router['name']?.toString() ?? ''));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mac == null ? 'Rename Q20' : 'Rename mesh node'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _withBusy(() async {
      if (mac == null) {
        await Q20MonitorService.renameRouter(widget.routerId, name);
      } else {
        await Q20MonitorService.meshAction(
          id: widget.routerId,
          action: 'rename',
          mac: mac,
          name: name,
        );
      }
      await _load();
      await _snack('Renamed to $name');
    });
  }

  Future<void> _command(String type, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text('Send $label to ${_router['name'] ?? 'this Q20'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    await _withBusy(() async {
      await Q20MonitorService.sendCommand(widget.routerId, type);
      await _load();
      await _snack('$label queued');
    });
  }

  Future<void> _mesh(String action, String mac, {String? name}) async {
    await _withBusy(() async {
      await Q20MonitorService.meshAction(
        id: widget.routerId,
        action: action,
        mac: mac,
        name: name,
      );
      await _load();
      await _snack(action == 'adopt' ? 'Adopted $mac' : '$action sent');
    });
  }

  Future<void> _openConsole() async {
    await _withBusy(() async {
      var url = _login['url']?.toString();
      if (url == null || url.isEmpty) {
        final data = await Q20MonitorService.login(widget.routerId);
        url = data['url']?.toString();
      }
      if (url == null || url.isEmpty) {
        throw Exception('Console URL was not issued');
      }
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('Could not open the device console');
    });
  }

  String _uptime(dynamic raw) {
    final secs = int.tryParse(raw?.toString() ?? '') ?? 0;
    if (secs <= 0) return '—';
    final d = secs ~/ 86400;
    final h = (secs % 86400) ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _when(dynamic raw) {
    if (raw == null) return 'never';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    return DateFormat('d MMM HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final name = _router['name']?.toString() ?? 'Q20';
    final statusColor = _online ? Colors.green : Colors.red;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(name),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Rename',
            onPressed: _busy ? null : () => _rename(current: name),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primaryColor,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: AppTheme.errorColor)),
                    ),
                  _statusCard(statusColor),
                  const SizedBox(height: 12),
                  _actions(),
                  const SizedBox(height: 16),
                  _facts(),
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Waiting to adopt'),
                    ..._pending.map(_pendingCard),
                  ],
                  const SizedBox(height: 16),
                  _sectionTitle('Mesh'),
                  if (_topology.isEmpty && _satellites.isEmpty)
                    _empty('No satellites reported yet')
                  else ...[
                    ..._topology.map(_topoCard),
                    if (_topology.isEmpty) ..._satellites.map(_satCard),
                  ],
                  const SizedBox(height: 16),
                  _sectionTitle('Recent events'),
                  if (_events.isEmpty)
                    _empty('No events yet')
                  else
                    ..._events.take(12).map(_eventTile),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _statusCard(Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: AppTheme.cardShadowColor, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_online ? Icons.check_circle : Icons.cancel, color: statusColor, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_online ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(fontWeight: FontWeight.w700, color: statusColor)),
                const SizedBox(height: 2),
                Text(_router['mac']?.toString() ?? '', style: const TextStyle(color: AppTheme.textSecondary)),
                Text(
                  'Last seen ${_when(_router['last_seen'])}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          if (_router['needs_adopt'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('ADOPT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.warningColor)),
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _actionChip(Icons.login, 'Open console', _openConsole),
        _actionChip(Icons.restart_alt, 'Reboot', () => _command('reboot', 'Reboot')),
        _actionChip(Icons.system_update_alt, 'Upgrade', () => _command('upgrade', 'Firmware upgrade')),
        _actionChip(Icons.sync, 'Re-provision', () => _command('reprovision', 'Re-provision')),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppTheme.primaryColor),
      label: Text(label),
      onPressed: _busy ? null : onTap,
      backgroundColor: AppTheme.primaryColor.withOpacity(0.08),
    );
  }

  Widget _facts() {
    final st = Map<String, dynamic>.from(_live['status'] as Map? ?? _router['live_status'] as Map? ?? {});
    final items = <List<String>>[
      ['Model', _router['model']?.toString() ?? 'JCG Q20'],
      ['Firmware', '${_router['fw_version'] ?? ''}  ${_router['fw_build'] ?? ''}'.trim()],
      ['WireGuard', _router['wg_ip']?.toString() ?? '—'],
      ['LAN', (st['lan_ip'] ?? _router['lan_ip'] ?? '').toString()],
      ['WAN', (st['wan_ip'] ?? _router['wan_ip'] ?? '').toString()],
      ['Role', (st['active_role'] ?? _router['role'] ?? _router['status'] ?? '').toString()],
      ['Clients', '${_router['clients'] ?? 0}'],
      ['Uptime', _uptime(_router['uptime'])],
      ['Internet', st['internet'] == true || _router['internet'] == true ? 'yes' : 'no'],
      ['Portal', st['portal_ready'] == true || _router['portal_ready'] == true ? 'ready' : '—'],
      ['Mesh peers', '${st['mesh_peers'] ?? _router['mesh_peers'] ?? _router['mesh_total'] ?? 0}'],
      ['Owner', _router['owner_email']?.toString() ?? _router['owner_name']?.toString() ?? '—'],
      ['Site', _router['site_name']?.toString() ?? '—'],
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: items
            .map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(width: 110, child: Text(row[0], style: const TextStyle(color: AppTheme.textSecondary))),
                    Expanded(child: Text(row[1].isEmpty ? '—' : row[1], style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> node) {
    final inform = Map<String, dynamic>.from(node['inform'] as Map? ?? {});
    final mac = (node['device_id'] ?? inform['device_id'] ?? '').toString();
    final hostname = (node['name']?.toString().isNotEmpty == true)
        ? node['name'].toString()
        : (inform['hostname'] ?? mac).toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hostname, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(mac, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            Text('Backhaul ${node['backhaul'] ?? 'unknown'}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : () => _mesh('adopt', mac),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  child: const Text('Adopt'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _mesh('reject', mac),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _topoCard(Map<String, dynamic> node) {
    final online = node['online'] == true || node['online'] == 1;
    final mac = node['mac']?.toString() ?? '';
    final role = node['role']?.toString() ?? '';
    final title = (node['name']?.toString().isNotEmpty == true)
        ? node['name'].toString()
        : (node['hostname'] ?? mac).toString();
    final isMain = role == 'main';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(isMain ? Icons.hub_outlined : Icons.device_hub_outlined,
            color: online ? Colors.green : Colors.red),
        title: Text(title),
        subtitle: Text(
          [
            role,
            mac,
            node['path']?.toString() ?? '',
            if (node['ip'] != null) node['ip'].toString(),
            if (node['mesh_signal_dbm'] != null) '${node['mesh_signal_dbm']} dBm',
          ].where((e) => e.toString().trim().isNotEmpty).join(' · '),
        ),
        trailing: isMain
            ? Text(online ? 'MAIN' : 'OFF', style: TextStyle(color: online ? Colors.green : Colors.red, fontWeight: FontWeight.w700, fontSize: 12))
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') {
                    _rename(mac: mac, current: title);
                  } else if (value == 'adopt') {
                    _mesh('adopt', mac);
                  } else {
                    _mesh(value, mac);
                  }
                },
                itemBuilder: (context) => [
                  if (node['adopted'] != true && node['adopted'] != 1)
                    const PopupMenuItem(value: 'adopt', child: Text('Adopt')),
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'restart', child: Text('Restart')),
                  const PopupMenuItem(value: 'remove', child: Text('Remove from mesh')),
                ],
              ),
      ),
    );
  }

  Widget _satCard(Map<String, dynamic> node) {
    final online = node['online'] == true;
    final mac = node['mac']?.toString() ?? '';
    final title = (node['name']?.toString().isNotEmpty == true)
        ? node['name'].toString()
        : (node['hostname'] ?? mac).toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.device_hub_outlined, color: online ? Colors.green : Colors.red),
        title: Text(title),
        subtitle: Text([mac, node['fw_build'] ?? ''].where((e) => e.toString().isNotEmpty).join(' · ')),
        trailing: Text(online ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(color: online ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _eventTile(dynamic raw) {
    final e = Map<String, dynamic>.from(raw as Map);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(e['event']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
        [e['detail'] ?? '', _when(e['created_at'])].where((x) => x.toString().isNotEmpty).join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: AppTheme.textSecondary)),
    );
  }
}
