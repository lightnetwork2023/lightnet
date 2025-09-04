import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../screens/GenerateUserScreen.dart';
import '../screens/VoucherManagementScreen.dart';
import '../screens/valid_users.dart';
import '../screens/VouchersByLocationScreen.dart';
import '../screens/VouchersScreen.dart';
import '../screens/UserManagementScreen.dart';
import '../screens/BundleManagementScreen.dart';
import '../screens/PurchaseForAgentScreen.dart';
import '../screens/payments.dart';
import '../screens/PaymentAnalyticsPage.dart';
import '../screens/NetworkDevicesScreen.dart';
import '../screens/LoginScreen.dart';

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
                  // Boss-only items
                  Obx(() {
                    if (authController.isBoss) {
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
                            onTap: () => _navigateTo(context, const UserManagementScreen()),
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
                            icon: Icons.card_membership_outlined,
                            title: 'Vouchers',
                            subtitle: 'View all vouchers',
                            onTap: () => _navigateTo(context, const VouchersScreen()),
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
                  _buildDrawerItem(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Vouchers by Location',
                    subtitle: 'Location-based vouchers',
                    onTap: () => _navigateTo(context, const VouchersByLocationScreen()),
                  ),
                  
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
                  _buildDrawerItem(
                    context,
                    icon: Icons.payment_outlined,
                    title: 'View Payments',
                    subtitle: 'Payment history',
                    onTap: () => _navigateTo(context, PaymentsScreen()),
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.analytics_outlined,
                    title: 'Payment Analytics',
                    subtitle: 'Financial insights',
                    onTap: () => _navigateTo(context, const PaymentAnalyticsPage()),
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.router_outlined,
                    title: 'Network Devices',
                    subtitle: 'Device monitoring',
                    onTap: () => _navigateTo(context, NetworkDevicesScreen()),
                  ),
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
