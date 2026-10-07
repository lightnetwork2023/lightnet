import 'package:lightnetwork/services/app_db.dart';
import 'package:flutter/material.dart';

import '../services/MikroTikMonitorService.dart';
import '../theme/app_theme.dart';
import 'access_points_sheet.dart';

/// MikroTik device list + summary (no AppBar). Shared by [HomeScreen] and [TechnicianHomeScreen].
class MikroTikMonitorContent extends StatefulWidget {
  /// When true (default), list and filter chips start on offline devices.
  final bool startWithOfflineFilter;

  const MikroTikMonitorContent({super.key, this.startWithOfflineFilter = true});

  @override
  State<MikroTikMonitorContent> createState() => MikroTikMonitorContentState();
}

class MikroTikMonitorContentState extends State<MikroTikMonitorContent>
    with AutomaticKeepAliveClientMixin {
  late String _filterStatus;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _devicesStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _filterStatus = widget.startWithOfflineFilter ? 'offline' : 'all';
    _devicesStream = MikroTikMonitorService.getMikroTikDevices();
  }

  Future<void> refresh() async {
    setState(() {
      _devicesStream = MikroTikMonitorService.getMikroTikDevices();
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildFilterChips(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            color: AppTheme.primaryColor,
            child: _buildDevicesBody(),
          ),
        ),
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
    return Material(
      color: isSelected ? AppTheme.primaryColor : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filterStatus = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesBody() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _devicesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              Center(child: Text('Error: ${snapshot.error}')),
            ],
          );
        }

        if (!snapshot.hasData) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Center(child: CircularProgressIndicator()),
            ],
          );
        }

        final devices = snapshot.data!.docs;
        final onlineCount = devices.where((d) => d['status'] == 'online').length;
        final offlineCount = devices.where((d) => d['status'] == 'offline').length;
        final unknownCount = devices.where((d) => d['status'] == 'unknown').length;

        return Column(
          children: [
            _buildSummaryCards(onlineCount, offlineCount, unknownCount),
            Expanded(child: _buildDevicesList(devices)),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(int onlineCount, int offlineCount, int unknownCount) {
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

  Widget _buildDevicesList(List<QueryDocumentSnapshot<Map<String, dynamic>>> devices) {
    var filtered = devices;
    if (_filterStatus != 'all') {
      filtered = devices.where((d) => d['status'] == _filterStatus).toList();
    }

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.router_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No MikroTik devices found',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildDeviceCard(filtered[index]),
    );
  }

  Widget _buildDeviceCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF1F4)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showAccessPointsSheet(context, doc.id, data),
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
                    AccessPointLink(key: ValueKey(doc.id), deviceId: doc.id, data: data),
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
