import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import 'package:intl/intl.dart';

import 'AgentUsersScreen.dart';
import 'PaymentAnalyticsPage.dart';
import 'SuperAgentPaymentsScreen.dart';
import 'SuperAgentRecentLoginsScreen.dart';
import 'SuperAgentPaymentsByLocationScreen.dart';

class SuperAgentHomeScreen extends StatefulWidget {
  const SuperAgentHomeScreen({super.key});

  @override
  State<SuperAgentHomeScreen> createState() => _SuperAgentHomeScreenState();
}

class _SuperAgentHomeScreenState extends State<SuperAgentHomeScreen> {
  final AuthController _authController = Get.find<AuthController>();
  final LocationController _locationController = Get.find<LocationController>();
  int _validUsersCount = 0;
  bool _isLoading = true;
  bool _isGenerating = false;
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
}
