// screens/valid_users_list_screen.dart
import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';

class ValidUsersListScreen extends StatefulWidget {
  final String location;
  const ValidUsersListScreen({super.key, required this.location});

  @override
  State<ValidUsersListScreen> createState() => _ValidUsersListScreenState();
}

class _ValidUsersListScreenState extends State<ValidUsersListScreen> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() async {
    final users = await ApiService.fetchValidUsers(widget.location);
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  String _formatTimeout(int? seconds) {
    if (seconds == null) return 'N/A';
    final d = Duration(seconds: seconds);
    return "${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Users in ${widget.location}")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? const Center(child: Text("No users found."))
          : ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(user['username'] ?? 'N/A'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("⚡ Speed: ${user['speed_limit'] ?? 'No limit'}"),
                  Text("⏳ Timeout: ${_formatTimeout(user['session_timeout'])}"),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
