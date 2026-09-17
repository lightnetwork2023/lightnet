import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/ApiService.dart';
import '../theme/app_theme.dart';

class LoginDetailsScreen extends StatefulWidget {
  const LoginDetailsScreen({super.key});

  @override
  State<LoginDetailsScreen> createState() => _LoginDetailsScreenState();
}

class _LoginDetailsScreenState extends State<LoginDetailsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;
  DateTime? _lastRefresh;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 90), (_) => _loadAll(silent: true));
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      if (!silent) {
        ApiService.clearCacheKey('active_macs');
      }
      final sessions = (await ApiService.fetchActiveSessions())
          .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _loading = false;
          _lastRefresh = DateTime.now();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  // Flexible field reader — handles different MikroTik API field naming styles
  String _f(Map d, List<String> keys, [String fallback = '—']) {
    for (final k in keys) {
      final v = d[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return fallback;
  }

  String _username(Map d) => _f(d, ['user', 'username', 'name', 'User']);
  String _ip(Map d) => _f(d, ['address', 'ip', 'Address', 'client-address']);
  String _mac(Map d) => _f(d, ['mac-address', 'mac_address', 'mac', 'Mac-Address', 'MAC']);
  String _uptime(Map d) => _f(d, ['uptime', 'Uptime', 'session-time', 'SessionTime']);
  String _server(Map d) => _f(d, ['server', 'Server', 'hotspot-server', 'NAS-Identifier']);
  String _bytesIn(Map d) => _f(d, ['bytes-in', 'bytes_in', 'BytesIn', 'Acct-Input-Octets']);
  String _bytesOut(Map d) => _f(d, ['bytes-out', 'bytes_out', 'BytesOut', 'Acct-Output-Octets']);

  String _formatBytes(String raw) {
    final n = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n == null || n == 0) return '—';
    if (n < 1024) return '$n B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)} MB';
    return '${(n / 1073741824).toStringAsFixed(2)} GB';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }

  Map<String, List<Map<String, dynamic>>> _groupSessionsByServer() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in _sessions) {
      final key = _server(s);
      final label = key == '—' || key.isEmpty ? 'Other Sessions' : key;
      groups.putIfAbsent(label, () => []).add(s);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Details',
            style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
        actions: [
          if (_lastRefresh != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _timeAgo(_lastRefresh!),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  onPressed: _loadAll,
                ),
        ],
      ),
      body: _loading && _sessions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _sessions.isEmpty
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Could not load sessions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final groups = _groupSessionsByServer();
    final totalSessions = _sessions.length;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          // ── Summary header ───────────────────────────────────────
          _buildSummaryHeader(totalSessions),
          const SizedBox(height: 16),

          if (totalSessions == 0) ...[
            _buildNoSessions(),
          ] else ...[
            ...groups.entries.map((entry) {
              return _buildSessionGroup(
                icon: Icons.router_rounded,
                color: AppTheme.primaryColor,
                title: entry.key,
                subtitle: '${entry.value.length} session${entry.value.length == 1 ? '' : 's'}',
                sessions: entry.value,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor.withOpacity(0.12),
                   AppTheme.primaryColor.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.login_rounded, color: AppTheme.primaryColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total Active Session${total == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor),
                ),
                Text(
                  'Live hotspot users right now',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                        color: Colors.green, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('LIVE', style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSessions() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            const Text('No Active Sessions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 6),
            const Text('No customers are connected right now.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionGroup({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> sessions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: sessions.isNotEmpty,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: subtitle.isNotEmpty
              ? Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: sessions.isEmpty
                      ? Colors.grey.withOpacity(0.1)
                      : Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${sessions.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: sessions.isEmpty ? Colors.grey : Colors.green.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, color: Colors.grey),
            ],
          ),
          children: sessions.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Text('No sessions in this group right now.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ),
                ]
              : sessions
                  .map((s) => _SessionTile(
                        s: s,
                        formatBytes: _formatBytes,
                        username: _username(s),
                        ip: _ip(s),
                        mac: _mac(s),
                        uptime: _uptime(s),
                        server: _server(s),
                        bytesIn: _bytesIn(s),
                        bytesOut: _bytesOut(s),
                      ))
                  .toList(),
        ),
      ),
    );
  }
}

// ── Session Tile ────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> s;
  final String username, ip, mac, uptime, server, bytesIn, bytesOut;
  final String Function(String) formatBytes;

  const _SessionTile({
    required this.s,
    required this.username,
    required this.ip,
    required this.mac,
    required this.uptime,
    required this.server,
    required this.bytesIn,
    required this.bytesOut,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Active pulse dot
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  username,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: username));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Voucher code copied'),
                        duration: Duration(seconds: 1)),
                  );
                },
                child: const Icon(Icons.copy_rounded,
                    size: 15, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (ip != '—') _chip(Icons.computer_rounded, ip, Colors.blue),
              if (mac != '—') _chip(Icons.memory_rounded, mac, Colors.indigo),
              if (uptime != '—')
                _chip(Icons.timer_outlined, uptime, Colors.teal),
              if (server != '—')
                _chip(Icons.dns_outlined, server, Colors.purple),
            ],
          ),
          if (bytesIn != '—' || bytesOut != '—') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (bytesIn != '—')
                  _chip(Icons.arrow_downward_rounded,
                      formatBytes(bytesIn), Colors.green),
                const SizedBox(width: 6),
                if (bytesOut != '—')
                  _chip(Icons.arrow_upward_rounded,
                      formatBytes(bytesOut), Colors.orange),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
