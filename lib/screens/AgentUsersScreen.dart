import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../controllers/auth_controller.dart';
import '../controllers/ApiService.dart';

class AgentUsersScreen extends StatefulWidget {
  const AgentUsersScreen({super.key});

  @override
  State<AgentUsersScreen> createState() => _AgentUsersScreenState();
}

class _AgentUsersScreenState extends State<AgentUsersScreen> {
  final AuthController _authController = Get.find<AuthController>();
  List<dynamic> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await ApiService.fetchValidUsers(_authController.userLocation);
      if (response != null) {
        setState(() {
          _users = response as List;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _shareUsersPdf() async {
    if (_users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No users to share")),
      );
      return;
    }

    final pdf = pw.Document();
    final location = _authController.userLocation;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text("Valid Users - $location", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Table.fromTextArray(
            headers: ["Username", "Speed Limit", "Session Timeout"],
            data: _users.map((user) {
              final timeout = user['session_timeout'];
              return [
                user['username'] ?? 'N/A',
                user['speed_limit'] ?? 'No limit',
                timeout != null ? _formatTimeout(timeout as int) : 'N/A',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/$location-valid-users.pdf");
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles([XFile(file.path)], text: 'Valid users for $location');
  }

  String _formatTimeout(int? seconds) {
    if (seconds == null) return 'N/A';
    final d = Duration(seconds: seconds);
    return "${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_authController.userLocation} Users (${_users.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareUsersPdf,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "No users found",
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _fetchUsers,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retry"),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchUsers,
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(user['username'] ?? 'N/A'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  "⚡ Speed: ${user['speed_limit'] ?? 'No limit'}"),
                              Text(
                                  "⏳ Timeout: ${_formatTimeout(user['session_timeout'] as int?)}"),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
} 