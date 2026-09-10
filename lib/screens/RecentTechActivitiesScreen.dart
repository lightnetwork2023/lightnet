import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class RecentTechActivitiesScreen extends StatefulWidget {
  const RecentTechActivitiesScreen({Key? key}) : super(key: key);

  @override
  State<RecentTechActivitiesScreen> createState() =>
      _RecentTechActivitiesScreenState();
}

class _RecentTechActivitiesScreenState
    extends State<RecentTechActivitiesScreen> {
  static const _voucherCol = 'technician_vouchers';

  // uid -> display name resolved from Firestore
  Map<String, String> _techNames = {};

  @override
  void initState() {
    super.initState();
    _loadTechnicianNames();
  }

  Future<void> _loadTechnicianNames() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'technician')
          .get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final name = doc.data()['name'] as String? ?? '';
        final email = doc.data()['email'] as String? ?? '';
        map[doc.id] = name.isNotEmpty ? name : email;
      }
      if (mounted) setState(() => _techNames = map);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent Tech Activities'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(_voucherCol)
            .orderBy('created_at', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, vSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('tech_checkins')
                .orderBy('created_at', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, cSnap) {
              if (vSnap.connectionState == ConnectionState.waiting &&
                  cSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final vouchers = (vSnap.data?.docs ?? [])
                  .map((d) => {'_type': 'voucher', 'id': d.id, ...d.data()})
                  .toList();
              final checkins = (cSnap.data?.docs ?? [])
                  .map((d) => {'_type': 'checkin', 'id': d.id, ...d.data()})
                  .toList();

              final allItems = <Map<String, dynamic>>[...vouchers, ...checkins];
              allItems.sort((a, b) {
                final ta = a['created_at'] as Timestamp?;
                final tb = b['created_at'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return tb.compareTo(ta);
              });

              if (allItems.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No technician activities yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                );
              }

              // Group by date
              final Map<String, List<Map<String, dynamic>>> grouped = {};
              for (final item in allItems) {
                final ts = item['created_at'] as Timestamp?;
                final label = ts != null ? _dayLabel(ts.toDate()) : 'Unknown date';
                grouped.putIfAbsent(label, () => []).add(item);
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: grouped.length,
                itemBuilder: (context, gi) {
                  final dateKey = grouped.keys.elementAt(gi);
                  final items = grouped[dateKey]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              dateKey,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ]),
                      ),
                      ...items.map((item) => item['_type'] == 'checkin'
                          ? _buildCheckinCard(context, item, _techNames)
                          : _buildVoucherCard(context, item, _techNames)),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildVoucherCard(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, String> techNames,
  ) {
    final techId = data['technician_id'] as String? ?? '';
    final storedName = data['technician_name'] as String? ?? '';
    final techName = (techNames[techId]?.isNotEmpty == true)
        ? techNames[techId]!
        : storedName.isNotEmpty ? storedName : 'Technician';
    final agentName = data['agent_name'] as String? ?? 'Unknown Agent';
    final agentLoc = data['agent_location'] as String? ?? '';
    final used = data['used'] as bool? ?? false;
    final ts = data['created_at'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_card, color: Colors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      children: [
                        TextSpan(
                          text: techName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' created a voucher for '),
                        TextSpan(
                          text: agentName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agentLoc.isNotEmpty ? agentLoc : '—',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(timeStr,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: used ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: used ? Colors.green.shade300 : Colors.orange.shade300),
                  ),
                  child: Text(
                    used ? 'Used' : 'Pending',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: used ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckinCard(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, String> techNames,
  ) {
    final techId = data['technician_id'] as String? ?? '';
    final storedName = data['technician_name'] as String? ?? '';
    final techName = (techNames[techId]?.isNotEmpty == true)
        ? techNames[techId]!
        : storedName.isNotEmpty ? storedName : 'Technician';
    final destType = data['destination_type'] as String? ?? '';
    final destName = data['destination_name'] as String? ?? '';
    final issue = data['issue'] as String? ?? '';
    final ts = data['created_at'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '';

    final destTypeLabel = destType == 'agent'
        ? 'Agent'
        : destType == 'home'
            ? 'Home Customer'
            : destType == 'site'
                ? 'Site'
                : destType;

    final destIcon = destType == 'agent'
        ? Icons.person_pin_circle_rounded
        : destType == 'home'
            ? Icons.home_rounded
            : Icons.cell_tower_rounded;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(destIcon, color: Colors.teal, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      children: [
                        TextSpan(
                          text: techName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: ' → $destTypeLabel'),
                        if (destName.isNotEmpty)
                          TextSpan(
                            text: ': $destName',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal),
                          ),
                      ],
                    ),
                  ),
                  if (issue.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.report_problem_outlined,
                            size: 12, color: Colors.red),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            issue,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.red),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Text(timeStr,
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(dt);
  }
}
