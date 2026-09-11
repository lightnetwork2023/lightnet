import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/MikroTikMonitorScreen.dart';
import '../services/MikroTikMonitorService.dart';
import '../theme/app_theme.dart';

/// MikroTik device list + summary (no AppBar). Shared by [HomeScreen] and [TechnicianHomeScreen].
class MikroTikMonitorContent extends StatefulWidget {
  /// When true (default), list and filter chips start on offline devices.
  final bool startWithOfflineFilter;

  const MikroTikMonitorContent({super.key, this.startWithOfflineFilter = true});

  @override
  State<MikroTikMonitorContent> createState() => _MikroTikMonitorContentState();
}

class _MikroTikMonitorContentState extends State<MikroTikMonitorContent> {
  late String _filterStatus;
  late final Stream<QuerySnapshot> _devicesStream;

  @override
  void initState() {
    super.initState();
    _filterStatus = widget.startWithOfflineFilter ? 'offline' : 'all';
    _devicesStream = MikroTikMonitorService.getMikroTikDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterChips(),
        _buildSummaryCards(),
        Expanded(child: _buildDevicesList()),
      ],
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
      stream: _devicesStream,
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
      stream: _devicesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var devices = snapshot.data!.docs;
        if (_filterStatus != 'all') {
          devices = devices.where((d) => d['status'] == _filterStatus).toList();
        }

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
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MikroTikMonitorScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Device'),
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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MikroTikMonitorScreen()),
        ),
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
}
