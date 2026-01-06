import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lightnetwork/screens/payments.dart';
import 'package:lightnetwork/screens/PaymentAnalyticsPage.dart';
import 'package:get/get.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import '../controllers/auth_controller.dart';
import 'UserManagementScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'NetworkDevicesScreen.dart';
import 'ActiveMacsScreen.dart';
import 'OfflineDevicesScreen.dart';
import 'VouchersScreen.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import '../widgets/modern_drawer.dart';
import 'HomeInternetCustomersScreen.dart';

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
    // Cache users in background without blocking UI
    _cacheAllValidUsers().catchError((e) => debugPrint('Background caching error: $e'));
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
    try {
      final data = await ApiService.fetchActiveSessions();
      setState(() => activeSessionsCount = data.length);
    } catch (e) {
      debugPrint('Error loading active sessions: $e');
      setState(() => activeSessionsCount = 0);
    }
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
      backgroundColor: AppTheme.backgroundColor,
      drawer: const ModernDrawer(),
      appBar: AppBar(
        title: Text(
          'Dashboard',
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
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          slivers: [
            // Welcome Header
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.dashboard_rounded,
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
                                'Welcome back!',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Obx(() => Text(
                                'Role: ${_authController.userRole.isEmpty ? "Loading..." : _authController.userRole.toUpperCase()}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Quick Stats Grid
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_authController.userRole != 'technician')
                          Expanded(
                            child: StatCard(
                              title: 'Active Sessions',
                              value: activeMacs.length.toString(),
                              subtitle: 'Connected users',
                              icon: Icons.wifi_rounded,
                              iconColor: AppTheme.successColor,
                              onTap: activeMacs.isNotEmpty
                                  ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ActiveMacsScreen(activeMacs: activeMacs),
                                ),
                              )
                                  : null,
                            ),
                          ),
                        if (_authController.userRole != 'technician')
                          const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            title: 'Offline Devices',
                            value: offlineDevicesCount.toString(),
                            subtitle: 'Need attention',
                            icon: Icons.warning_rounded,
                            iconColor: AppTheme.errorColor,
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'Today Logins',
                            value: _authController.userRole == 'technician' ? '' : todayLoginsCount.toString(),
                            subtitle: _authController.userRole == 'technician' ? 'View login vouchers' : '$last24hLoginsCount in 24h',
                            icon: Icons.login_rounded,
                            iconColor: AppTheme.infoColor,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => VouchersScreen(userRole: _authController.userRole)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            title: 'Today Payments',
                            value: _authController.userRole == 'technician' ? '' : todayPaymentsCount.toString(),
                            subtitle: _authController.userRole == 'technician' ? 'View all payments' : '$last24hPaymentsCount in 24h',
                            icon: Icons.payment_rounded,
                            iconColor: AppTheme.warningColor,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => PaymentsScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Payments by Location Section
            if (_authController.userRole != 'technician' && recentPaymentsByLocation.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Payments by Location',
                  subtitle: 'Last 24 hours activity',
                ),
              ),
              SliverToBoxAdapter(
                child: ModernCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: recentPaymentsByLocation.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.warningColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: AppTheme.warningColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            ModernBadge(
                              text: '${entry.value}',
                              backgroundColor: AppTheme.warningColor,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            
            // Quick Actions Section
            const SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Quick Actions',
                subtitle: 'Frequently used features',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_authController.userRole != 'technician')
                          Expanded(
                            child: ModernCard(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => PaymentAnalyticsPage(
                                  userRole: _authController.userRole,
                                )),
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.infoColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.analytics_rounded,
                                      color: AppTheme.infoColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Analytics',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: ModernCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => NetworkDevicesScreen()),
                            ),
                            margin: const EdgeInsets.only(left: 6),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.router_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Devices',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ModernCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const HomeInternetCustomersScreen()),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.successColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.home_rounded,
                                    color: AppTheme.successColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Home Internet Users',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_authController.isBoss) ...[
                      const SizedBox(height: 12),
                      ModernCard(
                        onTap: () => Get.to(() => const UserManagementScreen()),
                        gradient: AppGradients.primaryGradient,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.admin_panel_settings_rounded,
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
                                    'User Management',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Manage user accounts and permissions',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white.withOpacity(0.8),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 32),
            ),
          ],
        ),
      ),
    );
  }
}