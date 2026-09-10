import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../screens/GenerateUserScreen.dart';
import '../screens/VoucherManagementScreen.dart';
import '../screens/VouchersScreen.dart';
import '../screens/VouchersByLocationScreen.dart';
import '../screens/valid_users.dart';
import '../screens/SuperAgentPaymentsScreen.dart';
import '../screens/SuperAgentPaymentsByLocationScreen.dart';
import '../screens/BundleManagementScreen.dart';
import '../screens/PurchaseForAgentScreen.dart';
import '../screens/payments.dart';
import '../screens/PaymentAnalyticsPage.dart';
import '../screens/NetworkDevicesScreen.dart';
import '../screens/BossTechnicianAnalyticsScreen.dart';
import '../screens/LocationDataScreen.dart';
import '../screens/LocationAnalyticsScreen.dart';
import '../screens/LoginScreen.dart';
import '../screens/TechnicianCommissionPage.dart';
import '../screens/HomeInternetCustomersScreen.dart';
import '../screens/UserManagementScreen.dart';
import '../screens/BossSuperAgentAnalyticsScreen.dart';
import '../screens/HomePaymentApprovalsScreen.dart';
import '../screens/ExpenseCreationScreen.dart';
import '../screens/ExpenseApprovalScreen.dart';
import '../screens/ExpenseAnalyticsScreen.dart';
import '../screens/TechnicianExpensesScreen.dart';
import '../screens/UniFiAPManagementScreen.dart';
import '../screens/PayablesManagementScreen.dart';
import '../screens/ReceivablesManagementScreen.dart';
import '../screens/MikroTikMonitorScreen.dart';
import '../screens/NokiaBeaconScreen.dart';
import '../screens/LoginDetailsScreen.dart';
import '../screens/SimCardManagementScreen.dart';
import '../screens/DeviceInventoryScreen.dart';
import '../screens/TechnicianAgentListScreen.dart';
import '../screens/TechnicianVoucherScreen.dart';
import '../screens/DevicesInStoreScreen.dart';
import '../screens/InternetPaymentsScreen.dart';
import '../screens/MyAccountScreen.dart';
import '../services/WifiBeaconScannerService.dart';

class ModernDrawer extends StatelessWidget {
  const ModernDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final AuthController authController = Get.find<AuthController>();
    
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F9FA),
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: Column(
          children: [
            // Modern Header
            Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: AppGradients.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // App Logo/Icon
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.network_wifi,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // App Name
                      Text(
                        'lightNET',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // User Role
                      Obx(() => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          authController.userRole.isEmpty 
                              ? 'Loading...' 
                              : authController.userRole.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            ),
            
            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  // Boss and MD items
                  Obx(() {
                    if (authController.isAdminLevel) {
                      return Column(
                        children: [
                          _buildSectionHeader('Management'),
                          _buildDrawerItem(
                            context,
                            icon: Icons.person_add_outlined,
                            title: 'Generate Users',
                            subtitle: 'Create new user accounts',
                            onTap: () => _navigateTo(context, GenerateUserScreen()),
                          ),
                          _buildDrawerItem(
                            context,
                            icon: Icons.vpn_key_outlined,
                            title: 'Voucher by Mac',
                            subtitle: 'Manage device vouchers',
                            onTap: () => _navigateTo(context, const VoucherManagementScreen()),
                          ),
                          _buildDrawerItem(
                            context,
                            icon: Icons.admin_panel_settings_outlined,
                            title: 'User Management',
                            subtitle: 'Manage user accounts',
                            onTap: () => _navigateTo(context, UserManagementScreen()),
                          ),
                          _buildDrawerItem(
                            context,
                            icon: Icons.inventory_2_outlined,
                            title: 'Manage Bundles',
                            subtitle: 'Configure data bundles',
                            onTap: () => _navigateTo(context, const BundleManagementScreen()),
                          ),
                          _buildDrawerItem(
                            context,
                            icon: Icons.sim_card_outlined,
                            title: 'Simcards',
                            subtitle: 'Manage SIM cards',
                            onTap: () => _navigateTo(context, const SimCardManagementScreen()),
                          ),
                          _buildDrawerItem(
                            context,
                            icon: Icons.card_membership_outlined,
                            title: 'Vouchers',
                            subtitle: 'View all vouchers',
                            onTap: () => _navigateTo(context, VouchersScreen(userRole: authController.userRole)),
                          ),
                          _buildExpandableSection(
                            context,
                            title: 'Network Infrastructure',
                            icon: Icons.router_outlined,
                            children: [
                              _buildDrawerItem(
                                context,
                                icon: Icons.wifi_tethering_outlined,
                                title: 'UniFi Access Points',
                                subtitle: 'Manage UniFi APs',
                                onTap: () => _navigateTo(context, const UniFiAPManagementScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.devices_outlined,
                                title: 'MikroTik Monitoring',
                                subtitle: 'Monitor router status',
                                onTap: () => _navigateTo(context, const MikroTikMonitorScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.cell_tower_rounded,
                                title: 'Nokia Beacon Monitor',
                                subtitle: 'Bridge-mode AP online/offline',
                                onTap: () => _navigateTo(context, const NokiaBeaconScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.manage_accounts_rounded,
                                title: 'Login Details',
                                subtitle: 'Live hotspot sessions & users',
                                onTap: () => _navigateTo(context, const LoginDetailsScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.router_outlined,
                                title: 'Network Devices',
                                subtitle: 'Device monitoring',
                                onTap: () => _navigateTo(context, NetworkDevicesScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.inventory_outlined,
                                title: 'Device Inventory',
                                subtitle: 'All field devices & registrations',
                                onTap: () => _navigateTo(context, const DeviceInventoryScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.warehouse_outlined,
                                title: 'Devices in Store',
                                subtitle: 'Stock not yet installed',
                                onTap: () => _navigateTo(context, const DevicesInStoreScreen()),
                              ),
                            ],
                          ),
                          _buildDrawerItem(
                            context,
                            icon: Icons.wifi_rounded,
                            title: 'Internet Payments',
                            subtitle: 'Monthly ISP bill tracker',
                            onTap: () => _navigateTo(context, const InternetPaymentsScreen()),
                          ),
                          _buildExpandableSection(
                            context,
                            title: 'Debt Management',
                            icon: Icons.account_balance_outlined,
                            children: [
                              _buildDrawerItem(
                                context,
                                icon: Icons.payment_outlined,
                                title: 'Payables (We Owe)',
                                subtitle: 'Track money we owe',
                                onTap: () => _navigateTo(context, const PayablesManagementScreen()),
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.account_balance_wallet_outlined,
                                title: 'Receivables (They Owe)',
                                subtitle: 'Track money owed to us',
                                onTap: () => _navigateTo(context, const ReceivablesManagementScreen()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  
                  // Common items
                  _buildSectionHeader('Operations'),
                  _buildDrawerItem(
                    context,
                    icon: Icons.people_outline,
                    title: 'Valid Users',
                    subtitle: 'View active users',
                    onTap: () => _navigateTo(context, ValidUsersScreen()),
                  ),
                  _buildExpandableSection(
                    context,
                    title: 'Home Internet',
                    icon: Icons.home_rounded,
                    children: [
                      _buildDrawerItem(
                        context,
                        icon: Icons.people_alt_outlined,
                        title: 'Home Customers',
                        subtitle: 'Manage home users',
                        onTap: () => _navigateTo(context, const HomeInternetCustomersScreen()),
                      ),
                      Obx(() => authController.isAdminLevel
                          ? _buildDrawerItem(
                              context,
                              icon: Icons.verified_rounded,
                              title: 'Payment Approvals',
                              subtitle: 'Approve receipts',
                              onTap: () => _navigateTo(context, const HomePaymentApprovalsScreen()),
                            )
                          : const SizedBox.shrink()),
                    ],
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Vouchers by Location',
                    subtitle: 'Location-based vouchers',
                    onTap: () => _navigateTo(context, const VouchersByLocationScreen()),
                  ),
                  // Location Analytics - Boss and MD
                  Obx(() => authController.isAdminLevel
                      ? _buildExpandableSection(
                          context,
                          title: 'Location Management',
                          icon: Icons.location_on_rounded,
                          children: [
                            _buildDrawerItem(
                              context,
                              icon: Icons.map_outlined,
                              title: 'Location Data',
                              subtitle: 'View location details',
                              onTap: () => _navigateTo(context, const LocationDataScreen()),
                            ),
                            _buildDrawerItem(
                              context,
                              icon: Icons.analytics_outlined,
                              title: 'Location Analytics',
                              subtitle: 'Performance by location',
                              onTap: () => _navigateTo(context, const LocationAnalyticsScreen()),
                            ),
                          ],
                        )
                      : const SizedBox.shrink()),
                  // SuperAgent Payments (SuperAgent only)
                  Obx(() {
                    print('DEBUG: User role: ${authController.userRole}');
                    print('DEBUG: Is SuperAgent: ${authController.isSuperAgent}');
                    return authController.isSuperAgent
                        ? _buildExpandableSection(
                            context,
                            title: 'My Payments',
                            icon: Icons.payment_rounded,
                            children: [
                              _buildDrawerItem(
                                context,
                                icon: Icons.history_outlined,
                                title: 'Recent Payments',
                                subtitle: 'View payment history',
                                onTap: () {
                                  Navigator.pop(context);
                                  Get.to(() => SuperAgentPaymentsScreen());
                                },
                              ),
                              _buildDrawerItem(
                                context,
                                icon: Icons.location_on_outlined,
                                title: 'Payments by Location',
                                subtitle: 'Counts per location',
                                onTap: () {
                                  Navigator.pop(context);
                                  Get.to(() => const SuperAgentPaymentsByLocationScreen());
                                },
                              ),
                            ],
                          )
                        : const SizedBox.shrink();
                  }),
                  
                  // Boss and Technician items
                  Obx(() {
                    if (authController.isBoss || authController.userRole == 'technician') {
                      return _buildDrawerItem(
                        context,
                        icon: Icons.shopping_cart_outlined,
                        title: 'Purchase for Agent',
                        subtitle: 'Agent purchase management',
                        onTap: () => _navigateTo(context, const PurchaseForAgentScreen()),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  
                  const SizedBox(height: 16),
                  _buildSectionHeader('Analytics & Reports'),
                  _buildExpandableSection(
                    context,
                    title: 'Payment Analytics',
                    icon: Icons.analytics_outlined,
                    children: [
                      _buildDrawerItem(
                        context,
                        icon: Icons.payment_outlined,
                        title: 'View Payments',
                        subtitle: 'Payment history',
                        onTap: () => _navigateTo(context, PaymentsScreen()),
                      ),
                      Obx(() {
                        if (authController.userRole != 'technician') {
                          return _buildDrawerItem(
                            context,
                            icon: Icons.bar_chart_outlined,
                            title: 'Financial Insights',
                            subtitle: 'Analytics dashboard',
                            onTap: () {
                              if (authController.isBoss) {
                                _navigateTo(context, PaymentAnalyticsPage(
                                  userRole: authController.userRole,
                                ));
                              } else if (authController.isSuperAgent) {
                                _navigateTo(context, PaymentAnalyticsPage(
                                  userRole: authController.userRole,
                                  locations: authController.userLocations,
                                ));
                              } else if (authController.isAgent) {
                                _navigateTo(context, PaymentAnalyticsPage(
                                  userRole: authController.userRole,
                                  location: authController.userLocation,
                                ));
                              } else {
                                _navigateTo(context, PaymentAnalyticsPage(
                                  userRole: authController.userRole,
                                ));
                              }
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                      // Technician Commission (Technician only)
                      Obx(() => authController.userRole == 'technician'
                          ? _buildDrawerItem(
                              context,
                              icon: Icons.calculate_rounded,
                              title: 'My Commission',
                              subtitle: 'Your earnings',
                              onTap: () => _navigateTo(context, const TechnicianCommissionPage()),
                            )
                          : const SizedBox.shrink()),
                      // Nokia Beacons (Technician only)
                      Obx(() => authController.userRole == 'technician'
                          ? _buildDrawerItem(
                              context,
                              icon: Icons.cell_tower_rounded,
                              title: 'Nokia Beacons',
                              subtitle: 'Monitor & scan beacons',
                              onTap: () => _navigateTo(context, const NokiaBeaconScreen()),
                            )
                          : const SizedBox.shrink()),
                    ],
                  ),
                  // Field Details & Device Inventory (Technician only)
                  Obx(() => authController.userRole == 'technician'
                      ? Column(
                          children: [
                            const SizedBox(height: 16),
                            _buildSectionHeader('Field Work'),
                            _buildDrawerItem(
                              context,
                              icon: Icons.assignment_outlined,
                              title: 'Field Details',
                              subtitle: 'View & add agent field records',
                              onTap: () => _navigateTo(context, const TechnicianAgentListScreen()),
                            ),
                            _buildDrawerItem(
                              context,
                              icon: Icons.inventory_outlined,
                              title: 'Device Inventory',
                              subtitle: 'All field devices',
                              onTap: () => _navigateTo(context, const DeviceInventoryScreen()),
                            ),
                            _buildDrawerItem(
                              context,
                              icon: Icons.add_card_outlined,
                              title: 'Create Voucher',
                              subtitle: 'Generate agent vouchers',
                              onTap: () => _navigateTo(context, const TechnicianVoucherScreen()),
                            ),
                          ],
                        )
                      : const SizedBox.shrink()),
                  // Boss and MD: Staff Analytics
                  Obx(() => authController.isAdminLevel
                      ? _buildExpandableSection(
                          context,
                          title: 'Staff Analytics',
                          icon: Icons.people_alt_outlined,
                          children: [
                            _buildDrawerItem(
                              context,
                              icon: Icons.supervisor_account_rounded,
                              title: 'SuperAgent Analytics',
                              subtitle: 'View by SuperAgent',
                              onTap: () => _navigateTo(context, BossSuperAgentAnalyticsScreen()),
                            ),
                            _buildDrawerItem(
                              context,
                              icon: Icons.handyman_rounded,
                              title: 'Technician Analytics',
                              subtitle: 'View by Technician',
                              onTap: () => _navigateTo(context, const BossTechnicianAnalyticsScreen()),
                            ),
                          ],
                        )
                      : const SizedBox.shrink()),
                  // Expense Management Section
                  const SizedBox(height: 16),
                  _buildSectionHeader('Expense Management'),
                  Obx(() {
                    if (authController.userRole == 'technician') {
                      return _buildDrawerItem(
                        context,
                        icon: Icons.receipt_long_outlined,
                        title: 'My Requests',
                        subtitle: 'View & manage my requests',
                        onTap: () => _navigateTo(context, const TechnicianExpensesScreen()),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  // My Account – Boss and MD
                  Obx(() {
                    if (authController.isAdminLevel) {
                      return _buildDrawerItem(
                        context,
                        icon: Icons.account_balance_wallet_rounded,
                        title: 'My Account',
                        subtitle: 'Float management & transactions',
                        onTap: () => _navigateTo(context, const MyAccountScreen()),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  const SizedBox(height: 16),
                  _buildSectionHeader('App Settings'),
                  const _ScanToggleTile(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            
            // Bottom section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  _buildDrawerItem(
                    context,
                    icon: Icons.logout_outlined,
                    title: 'Logout',
                    subtitle: 'Sign out of account',
                    iconColor: AppTheme.errorColor,
                    textColor: AppTheme.errorColor,
                    onTap: () => _showLogoutDialog(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: AppTheme.textTertiary.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
          trailing: const Icon(Icons.expand_more, color: AppTheme.textTertiary),
          children: children,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppTheme.primaryColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor ?? AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: textColor ?? AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppTheme.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _ScanToggleTile extends StatefulWidget {
  const _ScanToggleTile();

  @override
  State<_ScanToggleTile> createState() => _ScanToggleTileState();
}

class _ScanToggleTileState extends State<_ScanToggleTile> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    WifiBeaconScannerService.isScanningEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTechnician = Get.find<AuthController>().userRole == 'technician';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTechnician
              ? AppTheme.primaryColor.withOpacity(0.45)
              : (_enabled
                  ? AppTheme.primaryColor.withOpacity(0.25)
                  : Colors.grey.shade200),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.wifi_find_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nokia Beacon Scanning',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    isTechnician
                        ? '🔒 Always ON · scanning every 1 min'
                        : (_enabled
                            ? 'Detecting nearby Nokia Beacons'
                            : 'WiFi beacon scanning paused'),
                    style: TextStyle(
                      color: isTechnician
                          ? AppTheme.primaryColor
                          : (_enabled ? AppTheme.primaryColor : Colors.grey),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isTechnician)
              const Icon(Icons.lock_rounded,
                  color: AppTheme.primaryColor, size: 20)
            else
              Switch(
                value: _enabled,
                activeColor: AppTheme.primaryColor,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  WifiBeaconScannerService.setScanningEnabled(v);
                },
              ),
          ],
        ),
      ),
    );
  }
}

extension on ModernDrawer {
  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.pop(context); // Close drawer
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close drawer
                final authController = Get.find<AuthController>();
                authController.logout();
                Get.offAll(() => const LoginScreen());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}
