import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OfflineDevicesScreen extends StatelessWidget {
  final List<Map<String, dynamic>> devices;
  const OfflineDevicesScreen({Key? key, required this.devices}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Sort devices: offline first, then online
    final sortedDevices = List<Map<String, dynamic>>.from(devices);
    sortedDevices.sort((a, b) {
      final aOffline = a['status'] == 'offline';
      final bOffline = b['status'] == 'offline';
      if (aOffline && !bOffline) return -1;
      if (!aOffline && bOffline) return 1;
      return 0;
    });

    return Scaffold(
      appBar: AppBar(title: const Text('All Devices')),
      body: sortedDevices.isEmpty
          ? const Center(child: Text('No devices found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sortedDevices.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final device = sortedDevices[index];
                final isOffline = device['status'] == 'offline';
                final isOnline = device['status'] == 'online';
                // Compute lastSeenStr for each device, check multiple field names and Firestore Timestamp
                String? lastSeenStr;
                final lastSeenRaw = device['lastSeen'] ?? device['last_seen'] ?? device['last_seen_at'];
                if (lastSeenRaw != null) {
                  try {
                    DateTime dt;
                    if (lastSeenRaw is Timestamp) {
                      dt = lastSeenRaw.toDate();
                    } else if (lastSeenRaw is String) {
                      dt = DateTime.tryParse(lastSeenRaw) ?? DateTime.now();
                    } else if (lastSeenRaw is int) {
                      dt = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw);
                    } else if (lastSeenRaw is DateTime) {
                      dt = lastSeenRaw;
                    } else if (lastSeenRaw is Map && (lastSeenRaw.containsKey('_seconds') || lastSeenRaw.containsKey('seconds'))) {
                      final seconds = lastSeenRaw['_seconds'] ?? lastSeenRaw['seconds'];
                      dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
                    } else {
                      dt = DateTime.now();
                    }
                    lastSeenStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
                  } catch (e) {
                    lastSeenStr = null;
                  }
                }
                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isOffline ? Colors.red.shade100 : Colors.green.shade100,
                      child: Icon(
                        isOffline ? Icons.warning : Icons.check_circle,
                        color: isOffline ? Colors.red.shade800 : Colors.green.shade800,
                      ),
                    ),
                    title: Text(
                      device['namee'] ?? 'Unnamed Device',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.router, size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 4),
                            Text('MAC: ${device['mac_address'] ?? 'N/A'}'),
                          ],
                        ),
                        if (isOnline && (device['ip_address'] != null && device['ip_address'].toString().isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(left: 24.0, top: 2.0),
                            child: Row(
                              children: [
                                const Icon(Icons.lan, size: 16, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text('IP: ${device['ip_address']}'),
                              ],
                            ),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text('Location: ${device['location'] ?? 'N/A'}'),
                          ],
                        ),
                        if (lastSeenStr != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 24.0, top: 2.0),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text('Last Seen: $lastSeenStr'),
                              ],
                            ),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isOffline ? Icons.cloud_off : Icons.cloud_done,
                              size: 16,
                              color: isOffline ? Colors.red : Colors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(isOffline ? 'Offline' : 'Online'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
} 