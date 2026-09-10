import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/MikroTikMonitorService.dart';
import '../theme/app_theme.dart';

class MikroTikMonitorScreen extends StatefulWidget {
  const MikroTikMonitorScreen({Key? key}) : super(key: key);

  @override
  State<MikroTikMonitorScreen> createState() => _MikroTikMonitorScreenState();
}

class _MikroTikMonitorScreenState extends State<MikroTikMonitorScreen> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MikroTik Monitoring'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          _buildSummaryCards(),
          Expanded(child: _buildDevicesList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDeviceDialog,
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 'all'),
            const SizedBox(width: 8),
            _buildFilterChip('Online', 'online'),
            const SizedBox(width: 8),
            _buildFilterChip('Offline', 'offline'),
            const SizedBox(width: 8),
            _buildFilterChip('Unknown', 'unknown'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => setState(() => _filterStatus = value),
      backgroundColor: Colors.grey[200],
      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot>(
      stream: MikroTikMonitorService.getMikroTikDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 80);
        }

        final devices = snapshot.data!.docs;
        final onlineCount = devices.where((d) => d['status'] == 'online').length;
        final offlineCount = devices.where((d) => d['status'] == 'offline').length;
        final unknownCount = devices.where((d) => d['status'] == 'unknown').length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Online',
                  onlineCount.toString(),
                  Colors.green,
                  Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Offline',
                  offlineCount.toString(),
                  Colors.red,
                  Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Unknown',
                  unknownCount.toString(),
                  Colors.orange,
                  Icons.help_outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _filterStatus == 'all'
          ? MikroTikMonitorService.getMikroTikDevices()
          : MikroTikMonitorService.getMikroTikDevicesByStatus(_filterStatus),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final devices = snapshot.data!.docs;

        if (devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.router_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No MikroTik devices found',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first device to start monitoring',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: devices.length,
          itemBuilder: (context, index) => _buildDeviceCard(devices[index]),
        );
      },
    );
  }

  Widget _buildDeviceCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'unknown';
    final name = data['name'] ?? 'Unknown';
    final ipAddress = data['ipAddress'] ?? '';
    final location = data['location'] ?? '';
    final lastSeen = data['lastSeen'] as Timestamp?;
    final lastChecked = data['lastChecked'] as Timestamp?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'online':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'offline':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDeviceDetails(doc),
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
                child: Icon(statusIcon, color: statusColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          location,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.router_outlined, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          ipAddress,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    Builder(builder: (_) {
                      final wanStats = data['wan_stats'] as Map<String, dynamic>?;
                      if (wanStats == null) {
                        return FutureBuilder<Map<String, dynamic>?>(
                          future: MikroTikMonitorService.fetchRadacctStats(ipAddress),
                          builder: (ctx, ras) {
                            if (ras.connectionState == ConnectionState.waiting) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(children: [
                                  SizedBox(width: 11, height: 11,
                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey[400])),
                                  const SizedBox(width: 6),
                                  Text('Loading usage…',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                                ]),
                              );
                            }
                            final r = ras.data;
                            if (r == null) {
                              if (status != 'online') return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(children: [
                                  Icon(Icons.info_outline, size: 13, color: Colors.grey[400]),
                                  const SizedBox(width: 4),
                                  Text('No usage data found',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                                ]),
                              );
                            }
                            final download   = r['rx_bytes'] as int? ?? 0;
                            final upload     = r['tx_bytes'] as int? ?? 0;
                            final avgBps     = r['avg_bps'] as int? ?? 0;
                            final daytimeBps = r['daytime_avg_bps'] as int? ?? 0;
                            final recentBps  = r['recent_avg_bps'] as int? ?? 0;
                            final sessions   = r['sessions'] as int? ?? 0;
                            final active     = r['active_sessions'] as int? ?? 0;
                            final hasRecent  = recentBps > 0;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                // ── NOW row (15-min near-realtime) ─────────────────
                                if (hasRecent) Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.purple.withOpacity(0.45)),
                                    ),
                                    child: const Text('NOW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple)),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(Icons.bolt_rounded, size: 13, color: Colors.purple[700]),
                                  const SizedBox(width: 2),
                                  Text(_formatSpeed(recentBps),
                                      style: TextStyle(fontSize: 13, color: Colors.purple[800], fontWeight: FontWeight.w800)),
                                  const SizedBox(width: 6),
                                  Text('(~15 min · accounting)', style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                                ]),
                                if (hasRecent) const SizedBox(height: 3),
                                // ── 24h consumption ────────────────────────────────
                                Row(children: [
                                  const Icon(Icons.arrow_circle_down_rounded, size: 13, color: Colors.blue),
                                  const SizedBox(width: 3),
                                  Text(_formatBytes(download),
                                      style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 6),
                                  Text('↑ ${_formatBytes(upload)}',
                                      style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 5),
                                  Text('(24h)', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                                ]),
                                const SizedBox(height: 2),
                                Row(children: [
                                  Icon(Icons.speed_rounded, size: 12, color: Colors.green[700]),
                                  const SizedBox(width: 3),
                                  Text('${_formatSpeed(avgBps)} 24h avg',
                                      style: TextStyle(fontSize: 10, color: Colors.green[700])),
                                  if (daytimeBps > 0) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.wb_sunny_rounded, size: 10, color: Colors.deepOrange),
                                    const SizedBox(width: 2),
                                    Text('~${_formatSpeed(daytimeBps)} day',
                                        style: const TextStyle(fontSize: 10, color: Colors.deepOrange)),
                                  ],
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(
                                    '$sessions sess${active > 0 ? " · $active live" : ""}',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                    overflow: TextOverflow.ellipsis,
                                  )),
                                ]),
                              ]),
                            );
                          },
                        );
                      }
                      return Builder(builder: (_) {
                        final rxBps   = wanStats['rx_bps']   as int? ?? 0;
                        final txBps   = wanStats['tx_bps']   as int? ?? 0;
                        final rxBytes = wanStats['rx_bytes'] as int? ?? 0;
                        final txBytes = wanStats['tx_bytes'] as int? ?? 0;
                        final liveMbps = (rxBps + txBps) / 1000000;
                        final liveColor = liveMbps >= 50
                            ? Colors.red
                            : liveMbps >= 20
                                ? Colors.deepOrange
                                : Colors.green[700]!;
                        // staleness from wan_updated_at
                        final updatedAt = data['wan_updated_at'];
                        String staleLabel = '';
                        if (updatedAt is Timestamp) {
                          final diffMin = DateTime.now().difference(updatedAt.toDate()).inMinutes;
                          if (diffMin >= 5) staleLabel = ' · ${diffMin}m ago';
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: liveColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: liveColor.withOpacity(0.5)),
                                ),
                                child: Text('SOS LIVE$staleLabel', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: liveColor)),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_circle_down_rounded, size: 13, color: Colors.blue),
                              const SizedBox(width: 3),
                              Text(_formatSpeed(rxBps),
                                  style: const TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w800)),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_circle_up_rounded, size: 13, color: Colors.orange),
                              const SizedBox(width: 3),
                              Text(_formatSpeed(txBps),
                                  style: const TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w800)),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              '↓${_formatBytes(rxBytes)}  ↑${_formatBytes(txBytes)}  (cumulative WAN)',
                              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                            ),
                          ]),
                        );
                      });
                    }),
                    if (lastSeen != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Last seen: ${_formatTimestamp(lastSeen)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'ping',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 20),
                        SizedBox(width: 12),
                        Text('Check Status'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _showEditDeviceDialog(doc);
                      break;
                    case 'ping':
                      _checkDeviceStatus(doc.id, ipAddress);
                      break;
                    case 'delete':
                      _confirmDelete(doc.id, name);
                      break;
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return DateFormat('MMM d, HH:mm').format(date);
  }

  String _formatSpeed(int bps) {
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} Kbps';
    return '$bps bps';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  void _showAddDeviceDialog() {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final vpnCtrl = TextEditingController(text: 'wireguard');
    final descCtrl = TextEditingController();
    final userCtrl = TextEditingController(text: 'admin');
    final passCtrl = TextEditingController();
    final wanIfaceCtrl = TextEditingController(text: 'ether1');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add MikroTik Device'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Device Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(labelText: 'IP Address *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                decoration: const InputDecoration(labelText: 'Location *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vpnCtrl,
                decoration: const InputDecoration(labelText: 'VPN Interface'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: 'RouterOS Username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'RouterOS Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wanIfaceCtrl,
                decoration: const InputDecoration(
                    labelText: 'WAN Interface',
                    hintText: 'e.g. ether1, pppoe-out1'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || ipCtrl.text.isEmpty || locationCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill required fields')),
                );
                return;
              }

              try {
                await MikroTikMonitorService.addMikroTikDevice(
                  name: nameCtrl.text.trim(),
                  ipAddress: ipCtrl.text.trim(),
                  location: locationCtrl.text.trim(),
                  vpnInterface: vpnCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                  wanInterface: wanIfaceCtrl.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device added successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDeviceDialog(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final nameCtrl = TextEditingController(text: data['name']);
    final ipCtrl = TextEditingController(text: data['ipAddress']);
    final locationCtrl = TextEditingController(text: data['location']);
    final vpnCtrl = TextEditingController(text: data['vpnInterface'] ?? 'wireguard');
    final descCtrl = TextEditingController(text: data['description'] ?? '');
    final userCtrl = TextEditingController(text: data['username'] ?? 'admin');
    final passCtrl = TextEditingController(text: data['password'] ?? '');
    final wanIfaceCtrl = TextEditingController(text: data['wanInterface'] ?? 'ether1');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Device'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Device Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(labelText: 'IP Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vpnCtrl,
                decoration: const InputDecoration(labelText: 'VPN Interface'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: 'RouterOS Username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'RouterOS Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wanIfaceCtrl,
                decoration: const InputDecoration(
                    labelText: 'WAN Interface',
                    hintText: 'e.g. ether1, pppoe-out1'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await MikroTikMonitorService.updateMikroTikDevice(
                  deviceId: doc.id,
                  name: nameCtrl.text.trim(),
                  ipAddress: ipCtrl.text.trim(),
                  location: locationCtrl.text.trim(),
                  vpnInterface: vpnCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                  wanInterface: wanIfaceCtrl.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device updated successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String deviceId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Are you sure you want to delete $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await MikroTikMonitorService.deleteMikroTikDevice(deviceId);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeviceDetails(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['name'] ?? 'Device Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('IP Address', data['ipAddress'] ?? 'N/A'),
              _detailRow('Location', data['location'] ?? 'N/A'),
              _detailRow('VPN Interface', data['vpnInterface'] ?? 'N/A'),
              _detailRow('Status', data['status'] ?? 'unknown'),
              if (data['description'] != null && data['description'].toString().isNotEmpty)
                _detailRow('Description', data['description']),
              if (data['lastSeen'] != null)
                _detailRow('Last Seen', _formatTimestamp(data['lastSeen'])),
              if (data['lastChecked'] != null)
                _detailRow('Last Checked', _formatTimestamp(data['lastChecked'])),
              _detailRow('WAN Interface', data['wanInterface'] ?? 'ether1'),
              _detailRow('RouterOS User', data['username'] ?? 'admin'),
              if (data['wan_stats'] != null) ...[
                const Divider(height: 20),
                const Text('WAN Statistics',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                _detailRow('Download Speed',
                    _formatSpeed((data['wan_stats']['rx_bps'] as int?) ?? 0)),
                _detailRow('Upload Speed',
                    _formatSpeed((data['wan_stats']['tx_bps'] as int?) ?? 0)),
                _detailRow('Total RX',
                    _formatBytes((data['wan_stats']['rx_bytes'] as int?) ?? 0)),
                _detailRow('Total TX',
                    _formatBytes((data['wan_stats']['tx_bytes'] as int?) ?? 0)),
                if (data['wan_updated_at'] != null)
                  _detailRow('Stats Updated',
                      _formatTimestamp(data['wan_updated_at'] as Timestamp)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _checkDeviceStatus(String deviceId, String ipAddress) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Checking status of $ipAddress...')),
    );

    try {
      final result = await Process.run('ping', ['-n', '2', ipAddress]);
      final isOnline = result.exitCode == 0;

      await MikroTikMonitorService.updateDeviceStatus(
        deviceId: deviceId,
        status: isOnline ? 'online' : 'offline',
        lastSeen: isOnline ? DateTime.now() : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOnline ? 'Device is ONLINE' : 'Device is OFFLINE'),
            backgroundColor: isOnline ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking status: $e')),
        );
      }
    }
  }
}
