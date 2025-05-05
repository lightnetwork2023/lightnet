// screens/active_sessions_screen.dart
import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';

class ActiveSessionsScreen extends StatefulWidget {
  @override
  _ActiveSessionsScreenState createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  List<dynamic> _sessions = [];
  bool _loading = false;

  void _fetchSessions() async {
    setState(() => _loading = true);
    final data = await ApiService.fetchActiveSessions();
    setState(() {
      _sessions = data;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🖥️ Active Sessions")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
          ? const Center(child: Text("No active sessions found."))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.person_outline, size: 36, color: Colors.blue),
              title: Text(
                session['username'] ?? 'N/A',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text("⏱️ Start Time: ${session['login_start_time']}"),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
