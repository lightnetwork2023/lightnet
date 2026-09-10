import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'SaWithdrawScreen.dart';
import 'AgentUsersScreen.dart';
import 'PaymentAnalyticsPage.dart';
import 'SuperAgentPaymentsScreen.dart';
import 'SuperAgentRecentLoginsScreen.dart';
import 'SuperAgentPaymentsByLocationScreen.dart';
import '../services/FieldRegistrationService.dart';
import '../services/MikroTikMonitorService.dart';
import 'SiteOverviewScreen.dart';

class SuperAgentHomeScreen extends StatefulWidget {
  const SuperAgentHomeScreen({super.key});

  @override
  State<SuperAgentHomeScreen> createState() => _SuperAgentHomeScreenState();
}

class _SuperAgentHomeScreenState extends State<SuperAgentHomeScreen> {
  final AuthController _authController = Get.find<AuthController>();
  final LocationController _locationController = Get.find<LocationController>();
  final _db = FirebaseFirestore.instance;
  int _validUsersCount = 0;
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isSubmittingWithdraw = false;
  String _selectedQuantity = '';
  String _selectedProvider = 'Mpesa';
  int _selectedDays = 1;

  // Store GetX workers for proper disposal
  late Worker _bundlesWorker;
  late Worker _locationWorker;

  // This list now only defines which bundles are possible, not their prices.
  final List<String> _masterBundleQuantities = ['40', '12'];

  // List of bundles available to this agent with their specific prices
  List<Map<String, dynamic>> _availableAmountOptions = [];

  final List<String> _providers = [
    'Mpesa', 'Tigo', 'Airtel', 'Halopesa', 'Azampesa'
  ];
  final TextEditingController _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    _buildAvailableBundles(); // Initial setup
    
    // Store workers for proper disposal
    _bundlesWorker = ever(_authController.allowedBundlesStream, (bundles) {
      _buildAvailableBundles();
    });

    _locationWorker = ever(_authController.userLocationStream, (location) {
      _loadValidUsersCount();
    });

    _loadValidUsersCount();
  }

  @override
  void dispose() {
    _bundlesWorker.dispose();
    _locationWorker.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _buildAvailableBundles() {
    final allowedBundles = _authController.allowedBundles;
    
    _availableAmountOptions = allowedBundles.entries.map((entry) {
      final bundle = entry.value;
      return {
        'quantity': entry.key,
        'price': bundle is Map ? bundle['price'] : bundle,
        'days': bundle is Map ? bundle['days'] : 1,
      };
    }).toList();

    if (_availableAmountOptions.isNotEmpty) {
      _selectedQuantity = _availableAmountOptions.first['quantity'];
      _selectedDays = _availableAmountOptions.first['days'];
    } else {
      _selectedQuantity = '';
      _selectedDays = 1;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadValidUsersCount() async {
    if (_authController.userLocation.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final users = await ApiService.fetchValidUsers(_authController.userLocation);
      setState(() {
        _validUsersCount = users.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _validUsersCount = 0;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    // Refresh user count and bundles
    await _loadValidUsersCount();
    _buildAvailableBundles();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data refreshed successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _generateUsers() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedQuantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a bundle quantity')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final selectedBundle = _availableAmountOptions.firstWhere(
        (bundle) => bundle['quantity'] == _selectedQuantity,
      );

      final result = await ApiService.makePayment(
        provider: _selectedProvider,
        phone: _phoneController.text.trim(),
        amount: selectedBundle['price'],
        quantity: int.parse(_selectedQuantity),
        durationSeconds: _selectedDays * 24 * 3600,
        location: _authController.userLocation,
        days: _selectedDays,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment successful! ${result['message']}')),
          );
          _phoneController.clear();
          _loadValidUsersCount();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: ${result['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Widget _buildLocationSwitcher() {
    final userLocations = _authController.userLocations;
    final currentLocation = _authController.userLocation;

    if (userLocations.length <= 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Text(
              currentLocation.isEmpty ? 'No Location' : currentLocation,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentLocation.isEmpty ? null : currentLocation,
          hint: const Text('Select Location'),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blue),
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          items: userLocations.map((location) => DropdownMenuItem<String>(
            value: location,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 16),
                const SizedBox(width: 8),
                Text(location),
              ],
            ),
          )).toList(),
          onChanged: (String? newLocation) {
            if (newLocation != null && newLocation != currentLocation) {
              _authController.setCurrentLocation(newLocation);
              _loadValidUsersCount();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refreshData,
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Data',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _buildLocationSwitcher(),
          ),
        ],
      ),
      drawer: _buildNavigationDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // Welcome Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.blueAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, ${_authController.userName}!',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Super Agent • ${_authController.userLocation.isEmpty ? 'No Location Selected' : _authController.userLocation}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.people, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isLoading ? 'Loading...' : '$_validUsersCount Valid Users',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Quick Actions
              Row(
                children: [
                  Expanded(
                    child: _buildQuickActionCard(
                      'Valid Users',
                      Icons.people,
                      Colors.green,
                      () {
                        if (_authController.userLocation.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AgentUsersScreen(location: _authController.userLocation),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please select a location first')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildQuickActionCard(
                      'Analytics',
                      Icons.analytics,
                      Colors.orange,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PaymentAnalyticsPage(
                              locations: _authController.userLocations,
                              userRole: _authController.userRole,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // My Equipment Section
              const Text(
                'My Equipment',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FieldRegistrationService.streamForOwner(
                    _authController.user!.uid),
                builder: (context, regSnap) {
                  if (!regSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Collect unique MikroTik device_ids
                  final deviceIds = <String>{};
                  for (final doc in regSnap.data!.docs) {
                    final eq =
                        doc.data()['equipment'] as List<dynamic>? ?? [];
                    for (final e in eq) {
                      if (e is Map && e['type'] == 'mikrotik') {
                        final id = e['device_id'] as String?;
                        if (id != null && id.isNotEmpty) deviceIds.add(id);
                      }
                    }
                  }
                  if (deviceIds.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'No MikroTik devices assigned yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }
                  return StreamBuilder<QuerySnapshot>(
                    stream: MikroTikMonitorService.getMikroTikDevicesByIds(
                        deviceIds.toList()),
                    builder: (context, devSnap) {
                      if (!devSnap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final devices = devSnap.data!.docs;
                      return Column(
                        children: devices.map((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final status =
                              data['status'] as String? ?? 'unknown';
                          final name =
                              data['name'] as String? ?? 'Unknown';
                          final ip =
                              data['ipAddress'] as String? ?? '';
                          final location =
                              data['location'] as String? ?? '';
                          Color statusColor;
                          IconData statusIcon;
                          switch (status) {
                            case 'online':
                              statusColor = Colors.green;
                              statusIcon = Icons.check_circle;
                              break;
                            case 'offline':
                              statusColor = Colors.red;
                              statusIcon = Icons.cancel;
                              break;
                            default:
                              statusColor = Colors.orange;
                              statusIcon = Icons.help_outline;
                          }
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => MikroTikClientsBottomSheet(
                                    deviceData: data,
                                    deviceName: name,
                                  ),
                                );
                              },
                              child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              statusColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(statusIcon,
                                            color: statusColor, size: 28),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              ip,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600]),
                                            ),
                                            if (location.isNotEmpty)
                                              Text(
                                                location,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[500]),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color:
                                              statusColor.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // ── Client count hint row ──
                                  () {
                                    final raw = data['connected_clients'];
                                    int count = 0;
                                    if (raw is List) count = raw.length;
                                    else if (raw is Map) count = raw.length;
                                    final updatedAt = data['clients_updated_at'] as Timestamp?;
                                    final isOffline = status.toLowerCase() == 'offline';
                                    // Stale: offline AND has old client data
                                    final isStaleClients = isOffline && count > 0;
                                    final iconColor = isStaleClients
                                        ? Colors.orange
                                        : count > 0 ? Colors.green : Colors.grey;
                                    final label = isStaleClients
                                        ? '$count clients (last known — device offline)'
                                        : count > 0 ? '$count clients connected' : 'No client data yet';
                                    final labelColor = isStaleClients
                                        ? Colors.orange.shade800
                                        : count > 0 ? Colors.green.shade700 : Colors.grey;
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isStaleClients
                                                ? Icons.history_rounded
                                                : Icons.people_outline_rounded,
                                            size: 14,
                                            color: iconColor,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: labelColor,
                                                fontWeight: count > 0 ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (updatedAt != null) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              _relTs(updatedAt.toDate()),
                                              style: TextStyle(fontSize: 10, color: isStaleClients ? Colors.orange.shade300 : Colors.grey[400]),
                                            ),
                                          ],
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_right_rounded,
                                              size: 16, color: Colors.grey),
                                        ],
                                      ),
                                    );
                                  }(),
                                ],
                              ),
                            ),
                          ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 24),

              // Generate Users Section
              if (_authController.userLocation.isNotEmpty) ...[
                const Text(
                  'Generate Users',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bundle Selection
                          const Text('Select Bundle', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          if (_availableAmountOptions.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: const Text(
                                'No bundles available. Contact your administrator.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            )
                          else
                            DropdownButtonFormField<String>(
                              value: _selectedQuantity.isEmpty ? null : _selectedQuantity,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              items: _availableAmountOptions.map((option) {
                                return DropdownMenuItem<String>(
                                  value: option['quantity'],
                                  child: Text('${option['quantity']} Users - TSH ${option['price']} (${option['days']} days)'),
                                );
                              }).toList(),
                              onChanged: (String? value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedQuantity = value;
                                    final selectedBundle = _availableAmountOptions.firstWhere(
                                      (bundle) => bundle['quantity'] == value,
                                    );
                                    _selectedDays = selectedBundle['days'];
                                  });
                                }
                              },
                              validator: (value) => value == null ? 'Please select a bundle' : null,
                            ),

                          const SizedBox(height: 16),

                          // Provider Selection
                          const Text('Payment Provider', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedProvider,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                            items: _providers.map((provider) => DropdownMenuItem<String>(
                              value: provider,
                              child: Text(provider),
                            )).toList(),
                            onChanged: (String? value) {
                              if (value != null) {
                                setState(() => _selectedProvider = value);
                              }
                            },
                          ),

                          const SizedBox(height: 16),

                          // Phone Number
                          const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phoneController,
                            decoration: InputDecoration(
                              hintText: 'Enter phone number',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey[50],
                              prefixIcon: const Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a phone number';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Generate Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isGenerating || _availableAmountOptions.isEmpty ? null : _generateUsers,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isGenerating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'Generate Users',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No Location Selected',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please select a location from the dropdown above to start working.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }

  // ─── Withdrawable Balance Section ─────────────────────────────────────────

  String _fmt(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  Widget _buildWithdrawableBalanceSection() {
    final uid = _authController.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final balance = (data['withdrawable_balance'] as num?)?.toDouble() ?? 0.0;
        final settlement = data['last_monthly_settlement'] as Map<String, dynamic>?;
        final month = settlement?['month'] as String? ?? '';
        final gross = (settlement?['gross_revenue'] as num?)?.toDouble() ?? 0;
        final deductions = (settlement?['deductions'] as num?)?.toDouble() ?? 0;
        final netCredited = (settlement?['net_credited'] as num?)?.toDouble() ?? 0;
        final saPercent = (_authController.commissionSuperAgent * 100).toStringAsFixed(0);

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    const Text('Withdrawable Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'TZS ${_fmt(balance)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold),
                ),
                if (month.isNotEmpty) ...[                  
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Last Settlement: $month',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Revenue ($saPercent%): TZS ${_fmt((gross * _authController.commissionSuperAgent))}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11)),
                            Text('- TZS ${_fmt(deductions)} (SIM)',
                                style: const TextStyle(
                                    color: Colors.orangeAccent, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Net Credited: TZS ${_fmt(netCredited)}',
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: balance <= 0
                        ? null
                        : () => _showWithdrawDialog(balance),
                    icon: const Icon(Icons.arrow_circle_up_rounded, size: 20),
                    label: Text(
                      balance <= 0
                          ? 'No Balance Available'
                          : 'Withdraw',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Withdraw Dialog ───────────────────────────────────────────────────────

  void _showWithdrawDialog(double availableBalance) {
    final amountCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Request Withdrawal',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available:', style: TextStyle(color: Colors.grey)),
                        Text('TZS ${_fmt(availableBalance)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (TZS) *',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.replaceAll(',', '') ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      if (n > availableBalance) return 'Exceeds available balance';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile or Account Number *',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Account Holder Name *',
                      prefixIcon: Icon(Icons.person_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (_isSubmittingWithdraw) ...[                  
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isSubmittingWithdraw ? null : () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white),
              onPressed: _isSubmittingWithdraw
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDS(() => _isSubmittingWithdraw = true);
                      try {
                        final uid = _authController.user?.uid;
                        final amount = double.parse(
                            amountCtrl.text.replaceAll(',', ''));

                        // Check no other pending request exceeds balance
                        final pendingSnap = await _db
                            .collection('sa_withdrawal_requests')
                            .where('user_id', isEqualTo: uid)
                            .where('status', isEqualTo: 'pending')
                            .get();
                        final pendingTotal = pendingSnap.docs.fold<double>(
                          0,
                          (s, d) =>
                              s + ((d.data()['amount'] as num?)?.toDouble() ?? 0),
                        );
                        if (pendingTotal + amount > availableBalance) {
                          throw Exception(
                              'Total pending requests (TZS ${_fmt(pendingTotal + amount)}) would exceed available balance.');
                        }

                        await _db.collection('sa_withdrawal_requests').add({
                          'user_id': uid,
                          'user_name': _authController.userName,
                          'amount': amount,
                          'mobile_or_account': mobileCtrl.text.trim(),
                          'account_name': nameCtrl.text.trim(),
                          'status': 'pending',
                          'created_at': FieldValue.serverTimestamp(),
                        });

                        if (mounted) Navigator.pop(dCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Withdrawal request submitted'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ $e')));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isSubmittingWithdraw = false);
                          setDS(() {});
                        }
                      }
                    },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── My Withdrawal Requests ────────────────────────────────────────────────

  Widget _buildMyWithdrawalRequests() {
    final uid = _authController.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('My Withdrawal Requests',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('sa_withdrawal_requests')
              .where('user_id', isEqualTo: uid)
              .limit(20)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            final sorted = docs.toList()
              ..sort((a, b) {
                final ta = (a.data() as Map)['created_at'] as Timestamp?;
                final tb = (b.data() as Map)['created_at'] as Timestamp?;
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return tb.compareTo(ta);
              });
            if (sorted.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: Text('No withdrawal requests yet',
                        style: TextStyle(color: Colors.grey))),
              );
            }
            return Column(
              children: sorted.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final status = d['status'] as String? ?? 'pending';
                final amount = (d['amount'] as num?)?.toDouble() ?? 0;
                final ts = d['created_at'] as Timestamp?;
                final dateStr = ts != null
                    ? DateFormat('dd MMM yyyy').format(ts.toDate())
                    : '';
                final evidenceUrl = d['evidence_url'] as String?;

                Color statusColor;
                IconData statusIcon;
                switch (status) {
                  case 'approved':
                    statusColor = Colors.green;
                    statusIcon = Icons.check_circle_rounded;
                    break;
                  case 'rejected':
                    statusColor = Colors.red;
                    statusIcon = Icons.cancel_rounded;
                    break;
                  default:
                    statusColor = Colors.orange;
                    statusIcon = Icons.hourglass_top_rounded;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(statusIcon, color: statusColor, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'TZS ${_fmt(amount)}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: statusColor),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(status.toUpperCase(),
                                  style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${d['account_name'] ?? ''} • ${d['mobile_or_account'] ?? ''}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13)),
                        Text(dateStr,
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 11)),
                        // Evidence (if approved)
                        if (status == 'approved' &&
                            evidenceUrl != null &&
                            evidenceUrl.isNotEmpty) ...[                          
                          const SizedBox(height: 10),
                          const Text('Payment Evidence',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: Colors.green)),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _showEvidenceFullscreen(evidenceUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                evidenceUrl,
                                height: 130,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder: (_, child, p) =>
                                    p == null
                                        ? child
                                        : const SizedBox(
                                            height: 130,
                                            child: Center(
                                                child:
                                                    CircularProgressIndicator())),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Tap to view full size',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  void _showEvidenceFullscreen(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image.network(url))),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple, Colors.purpleAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.supervisor_account,
                    size: 35,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _authController.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Super Agent',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.purple),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.people, color: Colors.green),
            title: const Text('Valid Users'),
            onTap: () {
              Navigator.pop(context);
              if (_authController.userLocation.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AgentUsersScreen(location: _authController.userLocation),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a location first')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.payment, color: Colors.blue),
            title: const Text('Recent Payments'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SuperAgentPaymentsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.location_on, color: Colors.orange),
            title: const Text('Payments by Location'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SuperAgentPaymentsByLocationScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.login, color: Colors.teal),
            title: const Text('Recent Logins'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SuperAgentRecentLoginsScreen(
                    locations: _authController.userLocations,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics, color: Colors.orange),
            title: const Text('Analytics'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PaymentAnalyticsPage(
                    locations: _authController.userLocations,
                    userRole: _authController.userRole,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_circle_up_rounded,
                color: Colors.green),
            title: const Text('SuperAgent Withdraw'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SaWithdrawScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () async {
              Navigator.pop(context);
              try {
                await _authController.logout();
                if (mounted) {
                  Get.offAllNamed('/login');
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
    );
  }

  String _relTs(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
