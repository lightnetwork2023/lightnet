import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/auth_controller.dart';
import '../controllers/ApiService.dart';

class PurchaseForAgentScreen extends StatefulWidget {
  const PurchaseForAgentScreen({super.key});

  @override
  State<PurchaseForAgentScreen> createState() => _PurchaseForAgentScreenState();
}

class _PurchaseForAgentScreenState extends State<PurchaseForAgentScreen> {
  final AuthController _authController = Get.find<AuthController>();
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  
  bool _isLoading = true;
  bool _isGenerating = false;
  String _selectedAgentId = '';
  String _selectedQuantity = '';
  String _selectedProvider = 'Mpesa';
  
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _availableAmountOptions = [];
  
  final List<String> _providers = [
    'Mpesa', 'Tigo', 'Airtel', 'Halopesa', 'Azampesa'
  ];

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    setState(() => _isLoading = true);
    try {
      // Get all agents from Firestore
      final agentsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'agent')
          .get();

      final agents = agentsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Unknown',
          'email': data['email'] ?? '',
          'location': data['location'] ?? '',
          'allowed_bundles': data['allowed_bundles'] ?? {},
        };
      }).toList();

      setState(() {
        _agents = agents;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading agents: $e')),
        );
      }
    }
  }

  void _onAgentSelected(String agentId) {
    setState(() {
      _selectedAgentId = agentId;
      _selectedQuantity = ''; // Reset bundle selection
    });
    _buildAvailableBundles();
  }

  void _buildAvailableBundles() {
    if (_selectedAgentId.isEmpty) {
      setState(() {
        _availableAmountOptions = [];
        _selectedQuantity = '';
      });
      return;
    }

    final selectedAgent = _agents.firstWhere(
      (agent) => agent['id'] == _selectedAgentId,
      orElse: () => {},
    );

    if (selectedAgent.isEmpty) return;

    final allowedBundlesMap = Map<String, num>.from(selectedAgent['allowed_bundles'] ?? {});
    
    setState(() {
      _availableAmountOptions = allowedBundlesMap.entries.map((entry) {
        return {'quantity': entry.key, 'price': entry.value};
      }).toList();

      // Set default selection if available
      if (_availableAmountOptions.isNotEmpty) {
        _selectedQuantity = _availableAmountOptions.first['quantity'];
      } else {
        _selectedQuantity = '';
      }
    });
  }

  Future<void> _generateVouchers() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedAgentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an agent')),
      );
      return;
    }

    if (_selectedQuantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a bundle')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    
    try {
      final selectedAgent = _agents.firstWhere(
        (agent) => agent['id'] == _selectedAgentId,
      );
      
      final selectedOption = _availableAmountOptions.firstWhere(
        (option) => option['quantity'] == _selectedQuantity,
      );
      
      final int price = selectedOption['price'];
      final int quantity = int.parse(selectedOption['quantity']);
      final int durationSeconds = 86400; // 1 day
      final String phone = _phoneController.text.trim();
      final String provider = _selectedProvider;
      final String location = selectedAgent['location'];

      // Make payment first
      final paymentResult = await ApiService.makePayment(
        provider: provider,
        phone: phone,
        amount: price,
        quantity: quantity,
        durationSeconds: durationSeconds,
        location: location,
      );
      
      if (paymentResult['error'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: ${paymentResult['error']}')),
          );
        }
        return;
      }

      // Payment successful
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bundle purchased successfully for ${selectedAgent['name']}!'),
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
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase for Agent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAgents,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAgents,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Agent Selection Card
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Agent',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedAgentId.isEmpty ? null : _selectedAgentId,
                                decoration: const InputDecoration(
                                  labelText: 'Choose Agent',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                                items: _agents.map<DropdownMenuItem<String>>((agent) {
                                  return DropdownMenuItem<String>(
                                    value: agent['id'],
                                    child: Text(
                                      agent['location'],
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    _onAgentSelected(value);
                                  }
                                },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please select an agent';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Bundle Selection Card
                      if (_selectedAgentId.isNotEmpty)
                        Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select Bundle',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (_availableAmountOptions.isEmpty)
                                  const Card(
                                    color: Colors.orange,
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Icon(Icons.warning, color: Colors.white),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'No bundles available for this agent. Please contact the boss to assign bundles.',
                                              style: TextStyle(color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  DropdownButtonFormField<String>(
                                    value: _selectedQuantity.isEmpty ? null : _selectedQuantity,
                                    decoration: const InputDecoration(
                                      labelText: 'Choose Bundle',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.inventory_2),
                                    ),
                                    items: _availableAmountOptions.map<DropdownMenuItem<String>>((option) {
                                      return DropdownMenuItem<String>(
                                        value: option['quantity'],
                                        child: Text(
                                          '${option['quantity']} vouchers - ${option['price']} TSH',
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _selectedQuantity = value);
                                      }
                                    },
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please select a bundle';
                                      }
                                      return null;
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Payment Details Card
                      if (_selectedAgentId.isNotEmpty && _selectedQuantity.isNotEmpty)
                        Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Payment Details',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                // Phone Number
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone Number',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.phone),
                                    hintText: 'e.g., 0765108208',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter phone number';
                                    }
                                    if (value.length < 9) {
                                      return 'Please enter a valid phone number';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Payment Provider
                                DropdownButtonFormField<String>(
                                  value: _selectedProvider,
                                  decoration: const InputDecoration(
                                    labelText: 'Payment Provider',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.payment),
                                  ),
                                  items: _providers.map<DropdownMenuItem<String>>((provider) {
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

                                // Purchase Button
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
                                      'Purchase Bundle',
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
                    ],
                  ),
                ),
              ),
            ),
    );
  }
} 