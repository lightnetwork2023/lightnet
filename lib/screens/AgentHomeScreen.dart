import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import 'package:intl/intl.dart';

import 'AgentUsersScreen.dart';
import 'PaymentAnalyticsPage.dart';

class AgentHomeScreen extends StatefulWidget {
  const AgentHomeScreen({super.key});

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  final AuthController _authController = Get.find<AuthController>();
  final LocationController _locationController = Get.find<LocationController>();
  int _validUsersCount = 0;
  bool _isLoading = true;
  bool _isGenerating = false;
  String _selectedQuantity = '';
  String _selectedProvider = 'Mpesa';
  int _selectedDays = 1; // Track selected days for the bundle

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
    _bundlesWorker = ever(_authController.allowedBundlesStream, (_) {
      if (mounted) {
        _buildAvailableBundles();
      }
    });

    // Use a listener to load data when userLocation is available
    _locationWorker = ever(_authController.userLocationStream, (String location) {
      if (mounted && location.isNotEmpty) {
        _loadData();
      }
    });
    
    // Initial load just in case location is already available
    if (_authController.userLocation.isNotEmpty) {
      _loadData();
    }
  }

  @override
  void dispose() {
    // Dispose GetX workers to prevent memory leaks
    _bundlesWorker.dispose();
    _locationWorker.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _buildAvailableBundles() {
    if (!mounted) return; // Check if widget is still mounted
    final allowedBundlesMap = _authController.allowedBundles;
    setState(() {
      _availableAmountOptions = allowedBundlesMap.entries.map((entry) {
        final bundle = entry.value;
        return {
          'quantity': entry.key,
          'price': bundle['price'],
          'days': bundle['days'],
        };
      }).toList();
      if (_availableAmountOptions.isNotEmpty) {
        if (_selectedQuantity.isEmpty || !_availableAmountOptions.any((opt) => opt['quantity'] == _selectedQuantity)) {
          _selectedQuantity = _availableAmountOptions.first['quantity'];
          _selectedDays = _availableAmountOptions.first['days'];
        } else {
          final selected = _availableAmountOptions.firstWhere((opt) => opt['quantity'] == _selectedQuantity);
          _selectedDays = selected['days'];
        }
      } else {
        _selectedQuantity = '';
        _selectedDays = 1;
      }
    });
  }

  Future<void> _loadData() async {
    // Ensure we have a location before fetching
    if (_authController.userLocation.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Load valid users count for agent's location
      final response = await ApiService.fetchValidUsers(_authController.userLocation);
      if (response != null) {
        final users = response as List;
        setState(() {
          _validUsersCount = users.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateVouchers() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isGenerating = true;
    });
    try {
      final selectedOption = _availableAmountOptions.firstWhere(
        (option) => option['quantity'] == _selectedQuantity
      );
      final int price = selectedOption['price'];
      final int quantity = int.parse(selectedOption['quantity']);
      final int days = selectedOption['days'];
      final double durationSeconds = days * 86400;
      final String phone = _phoneController.text.trim();
      final String provider = _selectedProvider;
      final String location = _authController.userLocation;

      // Make payment first
      final paymentResult = await ApiService.makePayment(
        provider: provider,
        phone: phone,
        amount: price,
        quantity: quantity,
        durationSeconds: durationSeconds,
        location: location,
        days: days,
      );
      if (paymentResult['error'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: ${paymentResult['error']}')),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Confirm by Entering your PIN'),
            backgroundColor: Colors.green,
          ),
        );
        _phoneController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating vouchers: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Text(
                'Agent Panel',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Valid Users'),
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const AgentUsersScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('View Payments'),
              onTap: () {
                Navigator.pop(context);
                // Navigate to payments screen filtered by agent's location
              },
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                try {
                  await _authController.logout();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Agent Info Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Agent Information',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Name: ${_authController.userName}'),
                          Text('Location: ${_authController.userLocation}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Valid Users Card
                  GestureDetector(
                    onTap: () {
                      Get.to(() => const AgentUsersScreen());
                    },
                    child: Card(
                      elevation: 4,
                      child: ListTile(
                        leading: const Icon(Icons.people, size: 40, color: Colors.blue),
                        title: const Text('Valid Users'),
                        subtitle: Text('$_validUsersCount users in your location'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Generate Vouchers Section
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Generate Vouchers',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedQuantity,
                              decoration: const InputDecoration(
                                labelText: 'Select Bundle',
                                border: OutlineInputBorder(),
                              ),
                              items: _availableAmountOptions.map<DropdownMenuItem<String>>((option) {
                                return DropdownMenuItem<String>(
                                  value: option['quantity'],
                                  child: Text(
                                    '	${option['quantity']} vouchers - ${option['price']} TSH - ${option['days']} day${option['days'] > 1 ? 's' : ''}',
                                  ),
                                );
                              }).toList(),
                              onChanged: _availableAmountOptions.isEmpty ? null : (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedQuantity = value;
                                    final selected = _availableAmountOptions.firstWhere((opt) => opt['quantity'] == value);
                                    _selectedDays = selected['days'];
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _selectedProvider,
                              decoration: const InputDecoration(
                                labelText: 'Select Provider',
                                border: OutlineInputBorder(),
                              ),
                              items: _providers.map((provider) {
                                return DropdownMenuItem<String>(
                                  value: provider,
                                  child: Text(provider),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedProvider = value);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                border: OutlineInputBorder(),
                                hintText: 'e.g. 0765908208',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a phone number';
                                }
                                if (value.length < 9 || value.length > 10) {
                                  return 'Phone number must be 9 or 10 digits';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isGenerating ? null : _generateVouchers,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: Colors.green,
                                ),
                                child: _isGenerating
                                    ? const CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      )
                                    : const Text(
                                  'Generate Vouchers',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 