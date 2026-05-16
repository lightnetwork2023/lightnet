import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/ApiService.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/mikrotik_monitor_tab.dart';
import '../widgets/modern_components.dart';
import '../widgets/modern_drawer.dart';
import 'HomeInternetCustomersScreen.dart';
import 'NetworkDevicesScreen.dart';
import 'OfflineDevicesScreen.dart';
import 'PurchaseForAgentScreen.dart';
import 'TechnicianCommissionPage.dart';
import 'TechnicianExpensesScreen.dart';
import 'TechnicianGenerateUserScreen.dart';
import 'VouchersScreen.dart';
import 'payments.dart';

/// Home dashboard for users with role `technician`. Capabilities match [ModernDrawer] technician entries.
class TechnicianHomeScreen extends StatefulWidget {
  const TechnicianHomeScreen({super.key});

  @override
  State<TechnicianHomeScreen> createState() => _TechnicianHomeScreenState();
}

class _TechnicianHomeScreenState extends State<TechnicianHomeScreen> {
  final AuthController _auth = Get.find<AuthController>();

  int offlineDevicesCount = 0;
  List<Map<String, dynamic>> allDevices = [];

  @override
  void initState() {
    super.initState();
    _loadOfflineDevices();
  }

  Future<void> _loadOfflineDevices() async {
    final snapshot = await FirebaseFirestore.instance.collection('devices').get();
    final all = snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList();
    final offline = all.where((d) => d['status'] == 'offline').length;
    setState(() {
      offlineDevicesCount = offline;
      allDevices = all;
    });
  }

  Future<void> _refreshData() async {
    ApiService.clearCache();
    try {
      await _loadOfflineDevices();
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing data: $e'), duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  void _nav(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 1, // Open MikroTik tab first (same as boss home)
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        drawer: const ModernDrawer(),
        appBar: AppBar(
          title: Text(
            'Technician',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _refreshData,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
              Tab(icon: Icon(Icons.router_rounded), text: 'MikroTik'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _refreshData,
              color: AppTheme.primaryColor,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Technician workspace',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Obx(() => Text(
                                      _auth.userName.isNotEmpty ? _auth.userName : 'Signed in',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: StatCard(
                                  title: 'Offline devices',
                                  value: offlineDevicesCount.toString(),
                                  subtitle: 'Need attention',
                                  icon: Icons.warning_rounded,
                                  iconColor: AppTheme.errorColor,
                                  onTap: allDevices.isNotEmpty
                                      ? () => _nav(OfflineDevicesScreen(devices: allDevices))
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatCard(
                                  title: 'Vouchers',
                                  value: 'Search',
                                  subtitle: 'Search by username',
                                  icon: Icons.confirmation_number_outlined,
                                  iconColor: AppTheme.infoColor,
                                  onTap: () => _nav(const VouchersScreen(userRole: 'technician')),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: StatCard(
                                  title: 'Payments',
                                  value: 'Search',
                                  subtitle: 'Search by phone number',
                                  icon: Icons.payment_rounded,
                                  iconColor: AppTheme.warningColor,
                                  onTap: () => _nav(PaymentsScreen()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatCard(
                                  title: 'Network',
                                  subtitle: 'View devices',
                                  value: 'Open',
                                  icon: Icons.router_rounded,
                                  iconColor: AppTheme.primaryColor,
                                  onTap: () => _nav(NetworkDevicesScreen()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'Shortcuts',
                      subtitle: 'Common tasks',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.15,
                      ),
                      delegate: SliverChildListDelegate([
                        _shortcutTile(
                          context,
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Generate one user',
                          color: AppTheme.primaryColor,
                          onTap: () => _nav(const TechnicianGenerateUserScreen()),
                        ),
                        _shortcutTile(
                          context,
                          icon: Icons.confirmation_number_outlined,
                          label: 'Vouchers',
                          color: AppTheme.infoColor,
                          onTap: () => _nav(const VouchersScreen(userRole: 'technician')),
                        ),
                        _shortcutTile(
                          context,
                          icon: Icons.home_rounded,
                          label: 'Home customers',
                          color: AppTheme.successColor,
                          onTap: () => _nav(const HomeInternetCustomersScreen()),
                        ),
                        _shortcutTile(
                          context,
                          icon: Icons.shopping_cart_outlined,
                          label: 'Purchase for agent',
                          color: AppTheme.primaryColor,
                          onTap: () => _nav(const PurchaseForAgentScreen()),
                        ),
                        _shortcutTile(
                          context,
                          icon: Icons.calculate_rounded,
                          label: 'My commission',
                          color: AppTheme.infoColor,
                          onTap: () => _nav(const TechnicianCommissionPage()),
                        ),
                        _shortcutTile(
                          context,
                          icon: Icons.receipt_long_outlined,
                          label: 'My expenses',
                          color: AppTheme.successColor,
                          onTap: () => _nav(const TechnicianExpensesScreen()),
                        ),
                        _shortcutTile(
                          context,
                          icon: Icons.payments_outlined,
                          label: 'View payments',
                          color: AppTheme.warningColor,
                          onTap: () => _nav(PaymentsScreen()),
                        ),
                      ]),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
            const MikroTikMonitorContent(),
          ],
        ),
      ),
    );
  }

  Widget _shortcutTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ModernCard(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
