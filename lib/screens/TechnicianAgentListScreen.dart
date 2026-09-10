import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import 'FieldDetailsScreen.dart';

class TechnicianAgentListScreen extends StatefulWidget {
  const TechnicianAgentListScreen({Key? key}) : super(key: key);

  @override
  State<TechnicianAgentListScreen> createState() =>
      _TechnicianAgentListScreenState();
}

class _TechnicianAgentListScreenState
    extends State<TechnicianAgentListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Details – Select Agent'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
              gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search agents / super agents…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', whereIn: ['agent', 'superagent'])
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                var docs = snap.data?.docs ?? [];
                if (_search.isNotEmpty) {
                  docs = docs.where((d) {
                    final name =
                        (d.data()['name'] as String? ?? '').toLowerCase();
                    final email =
                        (d.data()['email'] as String? ?? '').toLowerCase();
                    final loc =
                        (d.data()['location'] as String? ?? '').toLowerCase();
                    return name.contains(_search) ||
                        email.contains(_search) ||
                        loc.contains(_search);
                  }).toList();
                }
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No agents found',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final name = data['name'] as String? ?? 'Unknown';
                    final role = data['role'] as String? ?? '';
                    final location = data['location'] as String? ?? '';
                    final email = data['email'] as String? ?? '';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: role == 'superagent'
                              ? Colors.purple.shade100
                              : Colors.blue.shade100,
                          child: Icon(
                            role == 'superagent'
                                ? Icons.supervisor_account
                                : Icons.person,
                            color: role == 'superagent'
                                ? Colors.purple
                                : Colors.blue,
                          ),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (location.isNotEmpty)
                              Text(location,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            if (email.isNotEmpty)
                              Text(email,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: role == 'superagent'
                                ? Colors.purple.shade50
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            role == 'superagent'
                                ? 'Super Agent'
                                : 'Agent',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: role == 'superagent'
                                  ? Colors.purple
                                  : Colors.blue,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FieldDetailsScreen(
                              ownerId: d.id,
                              ownerName: name,
                              ownerRole: role,
                              ownerLocation: location,
                              canEdit: false,
                              canDelete: false,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
