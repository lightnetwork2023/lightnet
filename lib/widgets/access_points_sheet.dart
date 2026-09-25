import 'package:flutter/material.dart';
import 'package:lightnetwork/services/app_db.dart';

import '../services/MikroTikMonitorService.dart';
import '../theme/app_theme.dart';

class AccessPointView {
  final String mac;
  final String ip;
  final String hostname;
  final String status;
  final String lastSeen;
  final int lastSeenSeconds;
  final bool present;
  final String name;

  const AccessPointView({
    required this.mac,
    required this.ip,
    required this.hostname,
    required this.status,
    required this.lastSeen,
    required this.lastSeenSeconds,
    required this.present,
    required this.name,
  });

  bool get isOnline => status == 'online';
}

String normalizeBeaconMac(String mac) {
  final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length != 12) return mac.trim().toUpperCase();
  return List.generate(6, (i) => hex.substring(i * 2, i * 2 + 2)).join(':');
}

List<AccessPointView> accessPointsFrom(Map<String, dynamic> data) {
  final rawNames = data['access_point_names'];
  final names = rawNames is Map ? rawNames : const {};
  final raw = data['access_points'];
  if (raw is! List) return const [];
  final points = <AccessPointView>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final mac = normalizeBeaconMac('${item['mac'] ?? ''}');
    if (mac.isEmpty) continue;
    final custom = names[mac] ?? names[mac.toLowerCase()];
    points.add(AccessPointView(
      mac: mac,
      ip: '${item['ip'] ?? ''}',
      hostname: '${item['hostname'] ?? ''}',
      status: '${item['status'] ?? 'offline'}',
      lastSeen: '${item['last_seen'] ?? ''}',
      lastSeenSeconds: int.tryParse('${item['last_seen_seconds'] ?? ''}') ?? -1,
      present: item['present'] != false,
      name: custom == null ? '' : '$custom'.trim(),
    ));
  }
  points.sort((a, b) {
    int rank(AccessPointView ap) {
      if (!ap.present || ap.lastSeenSeconds < 0) return 1 << 30;
      return ap.lastSeenSeconds;
    }
    final byAge = rank(b).compareTo(rank(a));
    if (byAge != 0) return byAge;
    return accessPointLabel(a).compareTo(accessPointLabel(b));
  });
  return points;
}

String accessPointLabel(AccessPointView ap) => ap.name.isNotEmpty ? ap.name : ap.mac;

Widget _accessPointCountLabel(int online, int offline, bool empty) {
  const size = TextStyle(fontSize: 12);
  if (empty) {
    return const Text('No access points', style: TextStyle(fontSize: 12, color: Colors.grey));
  }
  if (offline == 0) {
    return Text('$online access points online', style: size.copyWith(color: Colors.green));
  }
  if (online == 0) {
    return Text('$offline access points offline', style: size.copyWith(color: Colors.red));
  }
  return Text.rich(
    TextSpan(
      style: size,
      children: [
        TextSpan(text: '$online online', style: const TextStyle(color: Colors.green, fontSize: 12)),
        const TextSpan(text: ' · ', style: TextStyle(color: Colors.grey, fontSize: 12)),
        TextSpan(text: '$offline offline', style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
    ),
  );
}

class AccessPointLink extends StatelessWidget {
  final String deviceId;
  final Map<String, dynamic> data;

  const AccessPointLink({super.key, required this.deviceId, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data['access_points'] is! List) return const SizedBox.shrink();
    final points = accessPointsFrom(data);
    final offline = points.where((p) => !p.isOnline).length;
    final online = points.length - offline;
    final iconColor = points.isEmpty
        ? Colors.grey
        : online > 0
            ? Colors.green
            : Colors.red;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => showAccessPointsSheet(context, deviceId, data),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(Icons.wifi_tethering, size: 14, color: iconColor),
        label: _accessPointCountLabel(online, offline, points.isEmpty),
      ),
    );
  }
}

void showAccessPointsSheet(BuildContext context, String deviceId, Map<String, dynamic> data) {
  final name = '${data['name'] ?? 'Router'}';
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AccessPointsSheet(deviceId: deviceId, deviceName: name),
  );
}

class AccessPointsSheet extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const AccessPointsSheet({super.key, required this.deviceId, required this.deviceName});

  @override
  State<AccessPointsSheet> createState() => _AccessPointsSheetState();
}

class _AccessPointsSheetState extends State<AccessPointsSheet> {
  Map<String, dynamic>? _fresh;
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final result = await MikroTikMonitorService.refreshAccessPoints(widget.deviceId);
      if (!mounted) return;
      setState(() {
        _fresh = {
          'access_points': result['access_points'] ?? const [],
          'access_point_names': result['access_point_names'] ?? const {},
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.72;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: MikroTikMonitorService.getMikroTikDevice(widget.deviceId),
        builder: (context, snap) {
          final data = _fresh ?? snap.data?.data() ?? const <String, dynamic>{};
          final points = accessPointsFrom(data);
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_tethering, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Access points · ${widget.deviceName}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Turn one access point off, wait a few minutes, then tap Refresh. The one heard longest ago is the one you turned off. Tap a row to name it.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
              Expanded(
                child: points.isEmpty
                    ? Center(child: Text('No access points on this router yet', style: TextStyle(color: Colors.grey[600])))
                    : ListView.separated(
                        itemCount: points.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final ap = points[index];
                          final color = ap.isOnline ? Colors.green : Colors.red;
                          final heard = !ap.present
                              ? 'No DHCP lease'
                              : ap.lastSeen.isEmpty
                                  ? 'No last-seen from the router'
                                  : 'Heard ${ap.lastSeen} ago';
                          return ListTile(
                            leading: Icon(ap.isOnline ? Icons.wifi : Icons.wifi_off, color: color),
                            title: Text(accessPointLabel(ap), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('$heard\n${ap.mac}${ap.ip.isEmpty ? '' : ' · ${ap.ip}'}'),
                            isThreeLine: true,
                            trailing: const Icon(Icons.edit_outlined, size: 18),
                            onTap: () async {
                              final saved = await _renameAccessPoint(context, widget.deviceId, ap);
                              if (saved == null || !mounted) return;
                              setState(() {
                                final base = Map<String, dynamic>.from(data);
                                final names = Map<String, dynamic>.from(base['access_point_names'] ?? {});
                                if (saved.trim().isEmpty) {
                                  names.remove(ap.mac);
                                } else {
                                  names[ap.mac] = saved.trim();
                                }
                                base['access_point_names'] = names;
                                _fresh = base;
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<String?> _renameAccessPoint(BuildContext context, String deviceId, AccessPointView ap) async {
  final ctrl = TextEditingController(text: ap.name);
  final saved = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Name this access point'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ap.mac, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          if (ap.ip.isNotEmpty) Text(ap.ip, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Shop name or room',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Clear')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
      ],
    ),
  );
  ctrl.dispose();
  if (saved == null || !context.mounted) return null;
  try {
    await MikroTikMonitorService.setAccessPointName(
      deviceId: deviceId,
      mac: ap.mac,
      name: saved,
    );
    return saved;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save name: $e')));
    }
    return null;
  }
}
