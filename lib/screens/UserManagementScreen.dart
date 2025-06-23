import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/location_controller.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthController authController = Get.find<AuthController>();
  final LocationController locationController = Get.find<LocationController>();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'technician';
  String _selectedLocation = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    print('UserManagementScreen initState - locations count: ${locationController.locations.length}');
    // Ensure locations are loaded, but do not set a default
    if (locationController.locations.isEmpty) {
      print('Locations empty, loading locations...');
      locationController.loadLocations();
    }
    // Set initial location if available
    if (locationController.locations.isNotEmpty) {
      _selectedLocation = locationController.locations.first;
      print('Set initial location: $_selectedLocation');
    }
    
    // Add listener to see when locations are updated
    ever(locationController.locations, (locations) {
      print('Locations updated: ${locations.length} locations');
      if (locations.isNotEmpty && _selectedLocation.isEmpty) {
        setState(() {
          _selectedLocation = locations.first;
          print('Updated selected location to: $_selectedLocation');
        });
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createNewAccount() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await authController.createNewAccount(
          _emailController.text.trim(),
          _passwordController.text,
          _selectedRole,
          name: _selectedRole == 'agent' ? _nameController.text.trim() : null,
          location: _selectedRole == 'agent' ? _selectedLocation : null,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created successfully!')),
          );
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _nameController.clear();
          setState(() {
            _selectedRole = 'technician';
            _selectedLocation = ''; // Reset to blank
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create account: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showCreateAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Account'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an email';
                      }
                      if (!GetUtils.isEmail(value)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(value: 'technician', child: Text('Technician')),
                      const DropdownMenuItem<String>(value: 'agent', child: Text('Agent')),
                      const DropdownMenuItem<String>(value: 'boss', child: Text('Boss')),
                    ],
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() => _selectedRole = value);
                        setDialogState(() {}); // Rebuild dialog
                      }
                    },
                  ),
                  if (_selectedRole == 'agent') ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedLocation.isNotEmpty ? _selectedLocation : null,
                            hint: const Text("Select Location"),
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              border: OutlineInputBorder(),
                            ),
                            items: locationController.locations.isEmpty 
                              ? [
                                  const DropdownMenuItem<String>(
                                    value: null,
                                    child: Text('No locations available'),
                                  )
                                ]
                              : locationController.locations.map((location) {
                                  return DropdownMenuItem<String>(
                                    value: location,
                                    child: Text(location),
                                  );
                                }).toList(),
                            onChanged: locationController.locations.isEmpty ? null : (String? value) {
                              if (value != null) {
                                setState(() => _selectedLocation = value);
                                setDialogState(() {}); // Rebuild dialog
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please select a location';
                              }
                              return null;
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            await locationController.loadLocations();
                            setDialogState(() {
                              // Just rebuild the dialog, don't set a default
                            });
                          },
                          tooltip: 'Refresh locations',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : () {
                Navigator.pop(context);
                _createNewAccount();
              },
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAgentDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final Map<String, num> currentAgentBundles =
        userData.containsKey('allowed_bundles')
            ? Map<String, num>.from(userData['allowed_bundles'])
            : {};
    
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance.collection('bundle_configurations').get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AlertDialog(
                title: Text('Edit Agent Bundles'),
                content: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return AlertDialog(
                title: const Text('Error'),
                content: const Text('Could not load bundle configurations.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
              );
            }

            final allMasterBundles = snapshot.data!.docs;
            final bundleControllers = {
              for (var doc in allMasterBundles)
                doc.id: TextEditingController(
                  text: currentAgentBundles[doc.id]?.toString(),
                )
            };

            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: Text('Edit Agent Bundles & Prices'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: allMasterBundles.map((bundleDoc) {
                        final bundleId = bundleDoc.id;
                        final controller = bundleControllers[bundleId]!;
                        bool isEnabled = currentAgentBundles.containsKey(bundleId);

                        return Column(
                          children: [
                            CheckboxListTile(
                              title: Text('Voucher Bundle $bundleId'),
                              value: isEnabled,
                              onChanged: (bool? isChecked) {
                                setDialogState(() {
                                  if (isChecked == true) {
                                    currentAgentBundles[bundleId] = num.tryParse(controller.text) ?? 0;
                                  } else {
                                    currentAgentBundles.remove(bundleId);
                                  }
                                });
                              },
                            ),
                            if (isEnabled)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: TextFormField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Price for Bundle $bundleId',
                                    prefixText: 'TSH ',
                                  ),
                                  onChanged: (value) {
                                    currentAgentBundles[bundleId] = num.tryParse(value) ?? 0;
                                  },
                                ),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final newBundles = Map<String, num>.from(currentAgentBundles)
                          ..removeWhere((key, value) => value <= 0);

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.id)
                            .update({'allowed_bundles': newBundles});

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Agent bundles updated successfully!')),
                        );
                      },
                      child: Text('Save'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateAccountDialog,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userData = user.data() as Map<String, dynamic>;
              final currentRole = userData['role']?.toString() ?? 'technician';
              final email = userData['email'] as String? ?? 'No email';

              return ListTile(
                title: Text(email),
                subtitle: Text('Role: $currentRole'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentRole == 'agent')
                      IconButton(
                        icon: Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showEditAgentDialog(user),
                      ),
                    DropdownButton<String>(
                      value: currentRole,
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                            value: 'technician', child: Text('Technician')),
                        const DropdownMenuItem<String>(
                            value: 'agent', child: Text('Agent')),
                        const DropdownMenuItem<String>(
                            value: 'boss', child: Text('Boss')),
                      ],
                      onChanged: (String? newRole) {
                        if (newRole != null && newRole != currentRole) {
                          authController.updateUserRole(user.id, newRole);
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
} 