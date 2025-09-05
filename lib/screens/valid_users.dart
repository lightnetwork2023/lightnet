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
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class ValidUsersScreen extends StatefulWidget {
  @override
  State<ValidUsersScreen> createState() => _ValidUsersScreenState();
}

class _ValidUsersScreenState extends State<ValidUsersScreen> {
  final LocationController locationController = Get.find();
  final AuthController authController = Get.find<AuthController>();
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
    if (!authController.isBoss) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only boss can generate PDF reports")),
      );
      return;
    }

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
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Valid Users by Location',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.primaryGradient,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _initialize,
            tooltip: 'Refresh Locations',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Header Section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location Overview',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'View valid users by location',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                ModernBadge(
                  text: '${locationController.locations.length}',
                  backgroundColor: Colors.white.withOpacity(0.2),
                  textColor: Colors.white,
                ),
              ],
            ),
          ),
          
          // Content Section
          Expanded(
            child: loading
                ? const ModernLoading(
                    message: 'Loading locations...',
                  )
                : locationController.locations.isEmpty
                    ? EmptyState(
                        icon: Icons.location_off_outlined,
                        title: 'No Locations Found',
                        subtitle: 'No locations are available to display',
                      )
                    : RefreshIndicator(
                        onRefresh: _initialize,
                        color: AppTheme.primaryColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: locationController.locations.length,
                          itemBuilder: (context, index) {
                            final location = locationController.locations[index];
                            final count = userCounts[location] ?? 0;
                            
                            return _buildLocationCard(location, count);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLocationCard(String location, int count) {
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count active users',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // User Count Badge
              ModernBadge(
                text: count.toString(),
                backgroundColor: count > 0 ? AppTheme.successColor : AppTheme.textTertiary,
                textColor: Colors.white,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: authController.isBoss ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ValidUsersListScreen(location: location),
                      ),
                    );
                  } : null,
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  label: const Text('View Users'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.5)),
                  ),
                ),
              ),
              if (authController.isBoss) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareLocationUsersPdf(location),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('Export PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.successColor,
                      side: BorderSide(color: AppTheme.successColor.withOpacity(0.5)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
