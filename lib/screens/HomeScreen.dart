import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lightnetwork/screens/payments.dart';
import 'package:lightnetwork/screens/valid_users.dart';
import 'package:get/get.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import 'GenerateUserScreen.dart';
import 'LoginScreen.dart';
import 'VouchersScreen.dart';
import 'VouchersByLocationScreen.dart';
import 'active_sessions.dart';
import 'delete_screen.dart';
import '../controllers/auth_controller.dart';
import 'UserManagementScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'NetworkDevicesScreen.dart';
import 'ActiveMacsScreen.dart';
import 'OfflineDevicesScreen.dart';
import 'BundleManagementScreen.dart';
import 'PurchaseForAgentScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthController _authController = Get.find<AuthController>();
  int activeSessionsCount = 0;
  int recentLoginsCount = 0;
  int todayLoginsCount = 0;
  int last24hLoginsCount = 0;
  int recentPaymentsCount = 0;
  int todayPaymentsCount = 0;
  int last24hPaymentsCount = 0;
  Map<String, int> paymentsByLocation = {};
  Map<String, int> recentPaymentsByLocation = {};
  Map<String, int> todayPaymentsByLocation = {};
  Map<String, int> yesterdayPaymentsByLocation = {};
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");
  List<dynamic> activeMacs = [];
  int offlineDevicesCount = 0;
  List<Map<String, dynamic>> allDevices = [];

  @override
  void initState() {
    super.initState();
    _loadActiveMacs();
    _loadOfflineDevices();
    _loadActiveSessions();
    _loadRecentLogins();
    _loadRecentPayments();
    _cacheAllValidUsers();
  }

  Future<void> _loadActiveMacs() async {
    try {
      final data = await ApiService.fetchActiveMacs();
      setState(() => activeMacs = data);
    } catch (e) {
      setState(() => activeMacs = []);
    }
  }

  Future<void> _loadOfflineDevices() async {
    final snapshot = await FirebaseFirestore.instance.collection('devices').get();
    final all = snapshot.docs.map((doc) => {
      'id': doc.id,
      ...doc.data(),
    }).toList();
    final offline = all.where((d) => d['status'] == 'offline').toList();
    setState(() {
      offlineDevicesCount = offline.length;
      allDevices = all;
    });
  }

  Future<void> _loadActiveSessions() async {
    final data = await ApiService.fetchActiveSessions();
    setState(() => activeSessionsCount = data.length);
  }

  Future<void> _loadRecentLogins() async {
    try {
      final recentVouchers = await ApiService.fetchRecentVouchers();
      final todayVouchers = await ApiService.fetchVouchersToday();

      setState(() {
        todayLoginsCount = todayVouchers.length;
        last24hLoginsCount = recentVouchers.length;
      });
    } catch (e) {
      debugPrint('Error loading logins: $e');
      setState(() {
        todayLoginsCount = 0;
        last24hLoginsCount = 0;
      });
    }
  }

  Future<void> _loadRecentPayments() async {
    try {
      final recentPayments = await ApiService.fetchRecentPayments();
      final todayPayments = await ApiService.fetchPaymentsToday();
      
      Map<String, int> tempTodayPaymentsByLocation = {};
      Map<String, int> tempLast24hPaymentsByLocation = {};
      
      // Process today's payments by location
      for (var payment in todayPayments) {
        final location = payment['location']?.toString() ?? 'Unknown';
        tempTodayPaymentsByLocation[location] = (tempTodayPaymentsByLocation[location] ?? 0) + 1;
      }
      
      // Process last 24h payments by location
      for (var payment in recentPayments) {
        final location = payment['location']?.toString() ?? 'Unknown';
        tempLast24hPaymentsByLocation[location] = (tempLast24hPaymentsByLocation[location] ?? 0) + 1;
      }
      
      setState(() {
        todayPaymentsCount = todayPayments.length;
        last24hPaymentsCount = recentPayments.length;
        todayPaymentsByLocation = tempTodayPaymentsByLocation;
        recentPaymentsByLocation = tempLast24hPaymentsByLocation;
      });
    } catch (e) {
      debugPrint('Error loading payments: $e');
      setState(() {
        todayPaymentsCount = 0;
        last24hPaymentsCount = 0;
        todayPaymentsByLocation = {};
        recentPaymentsByLocation = {};
      });
    }
  }

  Future<void> _cacheAllValidUsers() async {
    final locationController = Get.find<LocationController>();
    // Ensure locations are loaded
    if (locationController.locations.isEmpty) {
      await locationController.loadLocations();
    }
    await ApiService.fetchAllValidUsers(locationController.locations);
  }

  Future<void> _refreshData() async {
    ApiService.clearCache(); // Clear cache before refresh
    try {
      await Future.wait([
        _loadActiveMacs(),
        _loadOfflineDevices(),
        _loadActiveSessions(),
        _loadRecentLogins(),
        _loadRecentPayments(),
      ]);
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Text('lightNET', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            if (_authController.isBoss) ...[
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Generate Users'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenerateUserScreen())),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Valid Users'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ValidUsersScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Vouchers by Location'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VouchersByLocationScreen())),
            ),
            if (_authController.isBoss) ...[
              ListTile(
                leading: const Icon(Icons.card_membership),
                title: const Text('Vouchers'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VouchersScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('User Management'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2),
                title: const Text('Manage Bundles'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BundleManagementScreen())),
              ),
            ],
            if (_authController.isBoss || _authController.userRole == 'technician') ...[
              ListTile(
                leading: const Icon(Icons.shopping_cart),
                title: const Text('Purchase for Agent'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseForAgentScreen())),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('View Payments'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.computer),
              title: const Text('Active Sessions'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.router),
              title: const Text('Network Devices'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NetworkDevicesScreen())),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                try {
                  await _authController.logout();
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Logout failed: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text("lightNET"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh all counters',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.computer, size: 40, color: Colors.green),
                title: const Text("Active Devices"),
                subtitle: Text("${activeMacs.length} devices online"),
                onTap: activeMacs.isNotEmpty
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActiveMacsScreen(activeMacs: activeMacs),
                          ),
                        );
                      }
                    : null,
              ),
            ),
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.login, size: 40, color: Colors.blue),
                title: const Text("Logins"),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$todayLoginsCount logins today"),
                    Text("$last24hLoginsCount logins in last 24h"),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VouchersScreen(
                      showOnlyUsed: !_authController.isBoss,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.payment, size: 40, color: Colors.orange),
                title: const Text("Payments"),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$todayPaymentsCount payments today"),
                    Text("$last24hPaymentsCount payments in last 24h"),
                  ],
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen())),
              ),
            ),
            Card(
              elevation: 4,
              child: Column(
                children: [
                  if (todayPaymentsByLocation.isNotEmpty || recentPaymentsByLocation.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Payments by Location:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...todayPaymentsByLocation.entries.map((entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${entry.value} today",
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                          ...recentPaymentsByLocation.entries.map((entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${entry.value} last 24h",
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text('Current Role: ${_authController.userRole == "technician" ? "Technician" : _authController.userRole}'),
            const SizedBox(height: 20),
            if (_authController.isBoss) ...[
              ElevatedButton(
                onPressed: () {
                  Get.to(() => const UserManagementScreen());
                },
                child: const Text('User Management'),
              ),
            ],
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.warning, size: 40, color: Colors.red),
                title: const Text("Offline Devices"),
                subtitle: Text(
                  "$offlineDevicesCount devices offline",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTap: allDevices.isNotEmpty
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OfflineDevicesScreen(devices: allDevices),
                          ),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}