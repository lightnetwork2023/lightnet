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
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (locationController.locations.isEmpty) {
      locationController.loadLocations();
    }
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
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Create Account',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: MediaQuery.of(context).size.height * 0.95,
              width: MediaQuery.of(context).size.width,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: StatefulBuilder(
                    builder: (context, setDialogState) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Create New Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Account Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _emailController,
                                    decoration: InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: const Icon(Icons.email_outlined),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                      filled: true,
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
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                      filled: true,
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
                                    decoration: InputDecoration(
                                      labelText: 'Confirm Password',
                                      prefixIcon: const Icon(Icons.lock_reset),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                      filled: true,
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
                                    decoration: InputDecoration(
                                      labelText: 'Role',
                                      prefixIcon: const Icon(Icons.person_outline),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                      filled: true,
                                    ),
                                    items: <DropdownMenuItem<String>>[
                                      const DropdownMenuItem<String>(value: 'technician', child: Text('Technician')),
                                      const DropdownMenuItem<String>(value: 'agent', child: Text('Agent')),
                                      const DropdownMenuItem<String>(value: 'boss', child: Text('Boss')),
                                    ],
                                    onChanged: (String? value) {
                                      if (value != null) {
                                        setState(() => _selectedRole = value);
                                        setDialogState(() {});
                                      }
                                    },
                                  ),
                                  if (_selectedRole == 'agent') ...[
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _nameController,
                                      decoration: InputDecoration(
                                        labelText: 'Name',
                                        prefixIcon: const Icon(Icons.badge_outlined),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                        filled: true,
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter a name';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    GestureDetector(
                                      onTap: () async {
                                        // Show modal bottom sheet for location selection
                                        final selected = await showModalBottomSheet<String>(
                                          context: context,
                                          isScrollControlled: true,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                          ),
                                          builder: (context) => Container(
                                            height: MediaQuery.of(context).size.height * 0.7,
                                            child: Column(
                                              children: [
                                                const SizedBox(height: 16),
                                                const Text('Select Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                const Divider(),
                                                Expanded(
                                                  child: ListView(
                                                    children: locationController.locations.map((location) => ListTile(
                                                      title: Text(location),
                                                      onTap: () => Navigator.pop(context, location),
                                                      selected: _selectedLocation == location,
                                                      trailing: _selectedLocation == location ? const Icon(Icons.check, color: Colors.blue) : null,
                                                    )).toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                        if (selected != null) {
                                          setState(() => _selectedLocation = selected);
                                          setDialogState(() {});
                                        }
                                      },
                                      child: AbsorbPointer(
                                        child: TextFormField(
                                          decoration: InputDecoration(
                                            labelText: 'Location',
                                            prefixIcon: const Icon(Icons.location_on_outlined),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                            filled: true,
                                            hintText: 'Select Location',
                                          ),
                                          controller: TextEditingController(text: _selectedLocation),
                                          validator: (value) {
                                            if (value == null || value.isEmpty) {
                                              return 'Please select a location';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        icon: const Icon(Icons.refresh),
                                        onPressed: () async {
                                          await locationController.loadLocations();
                                          setDialogState(() {});
                                        },
                                        tooltip: 'Refresh locations',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(120, 48),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                backgroundColor: Colors.blue,
                              ),
                              onPressed: _isLoading ? null : () {
                                Navigator.pop(context);
                                _createNewAccount();
                              },
                              child: _isLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Create', style: TextStyle(fontSize: 18)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim1),
          child: child,
        );
      },
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
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateAccountDialog,
        backgroundColor: Colors.blue,
        shape: const CircleBorder(),
        child: const Icon(Icons.person_add_alt_1, size: 28),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final email = data['email']?.toString() ?? '';
                  final name = data['name']?.toString() ?? '';
                  return email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      name.toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();
                if (users.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: users.length,
                  separatorBuilder: (context, idx) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final userData = user.data() as Map<String, dynamic>;
                    final currentRole = userData['role']?.toString() ?? 'technician';
                    final email = userData['email'] as String? ?? 'No email';
                    final name = userData['name'] as String? ?? '';
                    final badgeColor = currentRole == 'boss'
                        ? Colors.deepPurple
                        : currentRole == 'agent'
                            ? Colors.blue
                            : Colors.green;
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: badgeColor.withOpacity(0.15),
                              child: Icon(
                                currentRole == 'boss'
                                    ? Icons.star
                                    : currentRole == 'agent'
                                        ? Icons.person
                                        : Icons.build,
                                color: badgeColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isNotEmpty ? name : email,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(email, style: const TextStyle(color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          currentRole.toUpperCase(),
                                          style: TextStyle(
                                            color: badgeColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (currentRole == 'agent')
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showEditAgentDialog(user),
                              ),
                            DropdownButton<String>(
                              value: currentRole,
                              underline: const SizedBox(),
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
                      ),
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