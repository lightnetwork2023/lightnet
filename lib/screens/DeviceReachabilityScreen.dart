import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart' as Crypto;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../controllers/ApiService.dart';


class DeviceReachabilityScreen extends StatefulWidget {
  const DeviceReachabilityScreen({Key? key}) : super(key: key);

  @override
  _DeviceReachabilityScreenState createState() => _DeviceReachabilityScreenState();
}

class _DeviceReachabilityScreenState extends State<DeviceReachabilityScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _onlineMacs = [];
  bool _isLoading = true;
  bool _isChecking = false;
  Map<String, Map<String, dynamic>> _deviceStatus = {};

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    _fetchOnlineMacs();
  }

  Future<void> _fetchDevices() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore.collection('devices').get();
      if (mounted) {
        setState(() {
          _devices = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching devices: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load devices: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchOnlineMacs() async {
    try {
      final data = await ApiService.fetchOnlineMacs();
      if (mounted) {
        setState(() {
          _onlineMacs = data.map((mac) => Map<String, dynamic>.from(mac)).toList();
        });
      }
    } catch (e) {
      print("Error fetching online MACs: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load online MACs: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _checkAllDevices() async {
    if (!mounted) return;
    setState(() {
      _isChecking = true;
      _deviceStatus.clear();
    });

    int onlineCount = 0;
    int offlineCount = 0;
    int errorCount = 0;

    for (var device in _devices) {
      if (!mounted) break;
      final String? statusField = device['status'] as String?;
      final status = statusField == 'online'
          ? {
              'reachable': true,
              'error': null,
              'details': 'Device is online',
              'ip_address': device['ip_address'],
            }
          : {
              'reachable': false,
              'error': null,
              'details': 'Device is offline',
              'ip_address': device['ip_address'],
            };
        if (mounted) {
          setState(() {
            _deviceStatus[device['id']] = status;
            if (status['reachable'] == true) {
              onlineCount++;
            } else {
              offlineCount++;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${device['namee'] ?? 'Device'}: ${status['reachable'] ? 'Online' : 'Offline'}'),
              duration: const Duration(seconds: 1),
              backgroundColor: status['reachable'] ? Colors.green : Colors.red,
            ),
          );
      }
    }

    if (mounted) {
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check complete. Online: $onlineCount, Offline: $offlineCount, Errors: $errorCount'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Reachability'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isChecking ? null : _checkAllDevices,
            tooltip: 'Check Device Status',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? const Center(child: Text('No devices found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    // Sort devices so offline are at the top
                    final sortedDevices = List<Map<String, dynamic>>.from(_devices);
                    sortedDevices.sort((a, b) {
                      final aStatus = _deviceStatus[a['id']];
                      final bStatus = _deviceStatus[b['id']];
                      final aOffline = aStatus != null && aStatus['reachable'] == false;
                      final bOffline = bStatus != null && bStatus['reachable'] == false;
                      if (aOffline && !bOffline) return -1;
                      if (!aOffline && bOffline) return 1;
                      return 0;
                    });
                    final device = sortedDevices[index];
                    final hasMacAddress = device['mac_address'] != null &&
                        device['mac_address'] != 'N/A' &&
                        device['mac_address'].toString().isNotEmpty;
                    final deviceId = device['id'];
                    final status = _deviceStatus[deviceId];

                    Color statusColor = Colors.grey;
                    IconData statusIcon = Icons.help_outline;
                    String statusText = 'Status: Not checked';

                    if (status != null) {
                      if (status['error'] != null) {
                        statusColor = Colors.orange;
                        statusIcon = Icons.error_outline;
                        statusText = 'Status: Error - ${status['error']}';
                      } else if (status['reachable'] == true) {
                        statusColor = Colors.green;
                        statusIcon = Icons.check_circle_outline;
                        statusText = 'Status: Online';
                      } else {
                        statusColor = Colors.red;
                        statusIcon = Icons.highlight_off;
                        statusText = 'Status: Offline';
                      }
                    }

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor,
                          child: Icon(statusIcon, color: Colors.white),
                        ),
                        title: Text(
                          device['namee'] ?? 'Unnamed Device',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Type: ${device['type'] ?? 'N/A'}'),
                            Text('Location: ${device['location'] ?? 'N/A'}'),
                            if (hasMacAddress) Text('MAC: ${device['mac_address']}'),
                            if (status != null) ...[
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (status['details'] != null)
                                Text(
                                  status['details'],
                                  style: TextStyle(
                                    color: statusColor.withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              if (status['ip_address'] != null)
                                Text(
                                  'IP: ${status['ip_address']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],
                          ],
                        ),
                        trailing: _isChecking && status == null && hasMacAddress
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}