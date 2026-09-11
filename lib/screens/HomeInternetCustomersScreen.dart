import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/models/home_customer.dart';
import 'AddHomeCustomerScreen.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'CustomerPaymentsScreen.dart';
import 'HomeCustomerPeriodsScreen.dart';
import 'EditHomeCustomerScreen.dart';
import 'HomeInternetDropdownsScreen.dart';
import 'HomeInternetAnalyticsScreen.dart';
import 'ArchivedHomeCustomersScreen.dart';
import 'FieldDetailsScreen.dart';

class HomeInternetCustomersScreen extends StatefulWidget {
  const HomeInternetCustomersScreen({super.key});

  @override
  State<HomeInternetCustomersScreen> createState() => _HomeInternetCustomersScreenState();
}

class _HomeInternetCustomersScreenState extends State<HomeInternetCustomersScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final Stream<List<HomeCustomer>> _customersStream;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _customersStream = HomeInternetService.streamCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HomeCustomer> _filterCustomers(List<HomeCustomer> customers) {
    if (_searchQuery.isEmpty) return customers;
    
    final query = _searchQuery.toLowerCase();
    return customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
             customer.phone.contains(query) ||
             customer.id.contains(query) ||
             customer.zone.toLowerCase().contains(query) ||
             customer.customerType.toLowerCase().contains(query) ||
             customer.location.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      Get.snackbar(
        'Error',
        'Could not launch phone dialer',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppTheme.errorColor.withOpacity(0.9),
        colorText: Colors.white,
      );
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Internet Users'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          if (Get.find<AuthController>().isBoss)
            IconButton(
              tooltip: 'Archived Customers',
              icon: const Icon(Icons.inventory_2_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ArchivedHomeCustomersScreen(),
                ),
              ),
            ),
          if (Get.find<AuthController>().isBoss)
            IconButton(
              tooltip: 'Payments Analytics',
              icon: const Icon(Icons.insights_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HomeInternetAnalyticsScreen(),
                ),
              ),
            ),
          if (Get.find<AuthController>().isBoss)
            IconButton(
              tooltip: 'Dropdown Options',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HomeInternetDropdownsScreen(),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.to(() => const AddHomeCustomerScreen()),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('New Customer'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: ModernSearchBar(
              controller: _searchController,
              hintText: 'Search by name, phone, ID, zone...',
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onClear: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
            ),
          ),
          
          // Results count
          Expanded(
            child: StreamBuilder<List<HomeCustomer>>(
        stream: _customersStream,
        builder: (context, snapshot) {
          // Show cached data immediately, no loading spinner
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Trigger rebuild
                      (context as Element).markNeedsBuild();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          final customers = snapshot.data ?? [];
          final filteredCustomers = _filterCustomers(customers);
          
          if (customers.isEmpty && snapshot.connectionState != ConnectionState.waiting) {
            return const _EmptyState();
          }
          
          final toShow = filteredCustomers;

          if (toShow.isEmpty && _searchQuery.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off_rounded, size: 64, color: AppTheme.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No customers found',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No customers match "$_searchQuery"',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Clear Search'),
                  ),
                ],
              ),
            );
          }
          
          return ListView.builder(
            itemCount: toShow.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final customer = toShow[index];
              return _CustomerCard(
                key: ValueKey(customer.id),
                customer: customer,
                onPhoneCall: _makePhoneCall,
              );
            },
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatefulWidget {
  final HomeCustomer customer;
  final Function(String) onPhoneCall;
  final Map<String, dynamic>? initialStatus;
  
  const _CustomerCard({
    super.key,
    required this.customer,
    required this.onPhoneCall,
    this.initialStatus,
  });

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {
  Map<String, dynamic>? _status;
  bool _loadingStatus = false;

  @override
  void initState() {
    super.initState();
    if (widget.customer.status != null) {
      _status = widget.customer.status;
    } else if (widget.initialStatus != null) {
      _status = widget.initialStatus;
    }
  }

  Future<void> _loadStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final status = await HomeInternetService.computeCustomerStatus(widget.customer.id);
      if (mounted) {
        setState(() {
          _status = status;
          _loadingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final fmt = NumberFormat('#,##0');
    
    final overdue = _status?['overdue'] == true;
    final outstandingRaw = _status?['outstanding_amount'];
    final outstanding = (outstandingRaw is num)
        ? outstandingRaw.toDouble()
        : double.tryParse('$outstandingRaw') ?? 0.0;
    final currency = _status?['currency'] ?? customer.currency;

    final borderColor = overdue
        ? AppTheme.errorColor.withOpacity(0.35)
        : Colors.transparent;
    final bgTint = overdue
        ? AppTheme.errorColor.withOpacity(0.06)
        : Colors.white;
    final badgeColor = overdue
        ? AppTheme.errorColor
        : AppTheme.successColor;
    final badgeText = overdue ? 'OVERDUE' : 'ON TIME';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerPaymentsScreen(
              customerId: customer.id,
              customerName: customer.name,
            ),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bgTint,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    child: const Icon(Icons.person, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                customer.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (Get.find<AuthController>().isAdminLevel) ...[
                              const SizedBox(width: 6),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, size: 20),
                                tooltip: 'Options',
                                onSelected: (val) async {
                                  if (val == 'edit') {
                                    final changed = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditHomeCustomerScreen(customerId: customer.id),
                                      ),
                                    );
                                    if (changed == true && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Customer updated')),
                                      );
                                    }
                                  } else if (val == 'field') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FieldDetailsScreen(
                                          ownerId: customer.id,
                                          ownerName: customer.name,
                                          ownerRole: 'homeuser',
                                          ownerLocation: customer.location.isNotEmpty
                                              ? customer.location
                                              : customer.zone,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit_rounded),
                                      title: Text('Edit Customer'),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'field',
                                    child: ListTile(
                                      leading: Icon(Icons.assignment_ind_outlined, color: Colors.teal),
                                      title: Text('Field Details'),
                                      dense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ID: ${customer.id}  •  ${customer.customerType}  •  Zone ${customer.zone}',
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                            if (customer.phone.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Material(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => widget.onPhoneCall(customer.phone),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.phone,
                                      size: 18,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (customer.phone.isNotEmpty)
                    GestureDetector(
                      onTap: () => widget.onPhoneCall(customer.phone),
                      child: _chip(Icons.phone_rounded, customer.phone, color: AppTheme.primaryColor),
                    ),
                  _chip(Icons.speed_rounded, '${customer.speedMbps} Mbps'),
                  _chip(Icons.receipt_long_rounded, 'Plan: ${fmt.format(customer.planAmount)} $currency'),
                  if (_status == null)
                    _chip(Icons.query_stats_rounded, 'Status: computing...')
                  else ...[
                    _chip(
                      outstanding > 0 ? Icons.warning_rounded : Icons.check_circle_rounded,
                      outstanding > 0
                          ? 'Outstanding: ${fmt.format(outstanding)} $currency'
                          : (outstanding < 0
                              ? 'Credit: ${fmt.format(outstanding.abs())} $currency'
                              : 'Outstanding: 0 $currency'),
                      color: outstanding > 0 ? AppTheme.errorColor : AppTheme.successColor,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HomeCustomerPeriodsScreen(
                            customerId: customer.id,
                            customerName: customer.name,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: const Text('Billing Periods'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerPaymentsScreen(
                            customerId: customer.id,
                            customerName: customer.name,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.payments_rounded),
                      label: const Text('Payments'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ));
  }
}

Widget _chip(IconData icon, String text, {Color? color}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (color ?? AppTheme.textSecondary).withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color ?? AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.people_outline, size: 48, color: AppTheme.textTertiary),
            SizedBox(height: 12),
            Text('No customers yet', style: TextStyle(color: AppTheme.textSecondary)),
            SizedBox(height: 4),
            Text('Tap "New Customer" to add one.', style: TextStyle(color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}
