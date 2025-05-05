import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lightnetwork/screens/valid_user_list.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ValidUsersScreen extends StatefulWidget {
  @override
  State<ValidUsersScreen> createState() => _ValidUsersScreenState();
}

class _ValidUsersScreenState extends State<ValidUsersScreen> {
  final LocationController locationController = Get.find();
  final Map<String, int> userCounts = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => loading = true);

    if (locationController.locations.isEmpty) {
      locationController.loadLocations();
    }

    await _loadUserCounts();
  }

  Future<void> _loadUserCounts() async {
    final counts = <String, int>{};

    for (final location in locationController.locations) {
      try {
        final users = await ApiService.fetchValidUsers(location);
        counts[location] = users.length;
      } catch (e) {
        counts[location] = 0;
      }
    }

    setState(() {
      userCounts
        ..clear()
        ..addAll(counts);
      loading = false;
    });
  }

  Future<void> _shareLocationUsersPdf(String location) async {
    final users = await ApiService.fetchValidUsers(location);

    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No users found for $location")),
      );
      return;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text("Valid Users - $location", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: ["Username", "Speed Limit", "Location", "Session Timeout"],
            data: users.map((user) => [
              user['username'] ?? '',
              user['speed_limit'] ?? 'No limit',
              user['location'] ?? 'N/A',
              user['session_timeout'] != null
                  ? _formatTimeout(user['session_timeout'])
                  : 'N/A',
            ]).toList(),
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/$location-valid-users.pdf");
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles([XFile(file.path)], text: 'Valid users for $location');
  }

  String _formatTimeout(int seconds) {
    final days = seconds ~/ (24 * 3600);
    final hours = (seconds % (24 * 3600)) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${days}d ${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("📍 Valid Users by Location")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: locationController.locations.length,
        itemBuilder: (context, index) {
          final location = locationController.locations[index];
          final count = userCounts[location] ?? 0;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.location_on),
              title: Text(location),
              subtitle: Text("👥 $count users"),
              trailing: Wrap(
                spacing: 12,
                children: [
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.green),
                    onPressed: () => _shareLocationUsersPdf(location),
                  ),
                  const Icon(Icons.arrow_forward_ios),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ValidUsersListScreen(location: location),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
