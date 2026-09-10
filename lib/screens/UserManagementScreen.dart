import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/location_controller.dart';
import '../services/SiteService.dart';
import 'FieldDetailsScreen.dart';
import 'SiteRegistrationScreen.dart';
import 'SiteOverviewScreen.dart';
import 'TechnicianDivisorsScreen.dart';

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
  final _commissionDivisorController = TextEditingController(text: '30000');
  String _selectedRole = 'technician';
  String _selectedLocation = '';
  List<String> _selectedLocations = [];
  List<String> _technicianSelectedLocations = [];
  String _searchQuery = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableAmountOptions = [];
  String _selectedQuantity = '';

  @override
  void initState() {
    super.initState();
    if (locationController.locations.isEmpty) {
      locationController.loadLocations();
    }
  }

  void _showEditTechnicianDivisorDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final userName = (userData['name'] ?? userData['email'] ?? 'Technician').toString();

    // Pre-populate: use saved commission_locations, else fall back to user's assigned locations
    final savedCommissionLocs = List<String>.from(userData['commission_locations'] ?? []);
    final assignedLocs        = List<String>.from(userData['locations'] ?? []);
    final singleLoc           = (userData['location'] ?? '').toString();
    final defaultSel = savedCommissionLocs.isNotEmpty
        ? savedCommissionLocs
        : assignedLocs.isNotEmpty
            ? assignedLocs
            : (singleLoc.isNotEmpty ? [singleLoc] : <String>[]);

    // Read existing divisor to avoid overwriting a manually-set custom value
    final rawDiv = userData['commission_divisor'];
    final existingDivisor = rawDiv is num ? rawDiv.toDouble() : null;
    final prevLocCount    = savedCommissionLocs.length.toDouble();

    // All available locations from location controller
    final allLocs = locationController.locations.toList();

    // Ensure anything already selected is visible even if not in allLocs
    final fullList = {...allLocs, ...defaultSel}.toList()..sort();

    final Set<String> selected = Set<String>.from(defaultSel);
    final TextEditingController searchCtrl = TextEditingController();
    String searchQ = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (ctx, setLocal) {
        final count = selected.length;
        const samplePayments = 300000.0;
        final sampleCommission = count > 0 ? samplePayments / count : 0.0;

        final visible = fullList
            .where((l) => searchQ.isEmpty || l.toLowerCase().contains(searchQ))
            .toList();

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_rounded, color: Colors.deepPurple),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Commission Locations', style: TextStyle(fontSize: 17)),
                Text('For: $userName', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            )),
          ]),
          content: SizedBox(
            width: 400,
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Formula explanation
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: const Text(
                    'Select the locations to include in this technician\'s commission.\n'
                    'Formula: Commission = Payments total ÷ number of selected locations',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ),
                const SizedBox(height: 10),
                // Search + select-all row
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search locations…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setLocal(() => searchQ = v.toLowerCase().trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setLocal(() {
                      if (selected.length == visible.length) {
                        selected.removeAll(visible);
                      } else {
                        selected.addAll(visible);
                      }
                    }),
                    child: Text(selected.length == visible.length ? 'None' : 'All',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 6),
                // Selected count badge
                Text('$count location${count == 1 ? '' : 's'} selected  ·  Divisor = $count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: count > 0 ? Colors.deepPurple : Colors.red,
                    )),
                const SizedBox(height: 6),
                // Location checkboxes
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final loc = visible[i];
                      final isSel = selected.contains(loc);
                      return CheckboxListTile(
                        dense: true,
                        value: isSel,
                        title: Text(loc, style: const TextStyle(fontSize: 13)),
                        activeColor: Colors.deepPurple,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (_) => setLocal(() {
                          if (isSel) selected.remove(loc); else selected.add(loc);
                        }),
                      );
                    },
                  ),
                ),
                const Divider(height: 8),
                // Preview
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calculate_rounded, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      count > 0
                          ? 'Preview: 300,000 TZS ÷ $count = ${sampleCommission.toStringAsFixed(2)} TZS'
                          : 'Select at least one location',
                      style: TextStyle(
                        fontSize: 12,
                        color: count > 0 ? Colors.green[800] : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    )),
                  ]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
              onPressed: () async {
                if (selected.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Select at least one location')),
                  );
                  return;
                }
                final selList = selected.toList()..sort();
                try {
                  // Only reset divisor to location count if it was auto-set or unset.
                  // Preserve a custom divisor (e.g. 33) that differs from old location count.
                  final newDivisor = (existingDivisor == null || existingDivisor == prevLocCount)
                      ? selList.length.toDouble()
                      : existingDivisor;
                  await FirebaseFirestore.instance.collection('users').doc(user.id).update({
                    'commission_locations': selList,
                    'commission_divisor': newDivisor,
                    'commission_divisor_updated_at': FieldValue.serverTimestamp(),
                    'commission_divisor_updated_by': authController.user?.uid,
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Commission: ${selList.length} locations set for $userName'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      }),
    );
  }

  void _showEditCommissionDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    // Read existing commission (support map or legacy percent)
    double saShare = 0.63;
    double coShare = 0.37;
    try {
      final comm = userData['commission'];
      if (comm != null && comm is Map) {
        final sa = _parseShare(comm['superagent']);
        final co = _parseShare(comm['company']);
        if (sa != null) saShare = sa;
        coShare = co ?? (1.0 - saShare);
      } else if (userData['superagent_percent'] != null) {
        final legacy = _parseShare(userData['superagent_percent']);
        if (legacy != null) {
          saShare = legacy;
          coShare = 1.0 - saShare;
        }
      }
      saShare = saShare.clamp(0.0, 1.0);
      coShare = (1.0 - saShare).clamp(0.0, 1.0);
    } catch (_) {}

    double saPct = (saShare * 100).clamp(0, 100);
    final controller = TextEditingController(text: saPct.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit SuperAgent Commission'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Set the revenue split for this superagent'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('SuperAgent %'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'e.g., 63',
                        ),
                        onChanged: (val) {
                          final v = double.tryParse(val) ?? saPct;
                          setStateDialog(() {
                            saPct = v.clamp(0, 100);
                            controller.value = controller.value.copyWith(
                              text: saPct.toStringAsFixed(0),
                              selection: TextSelection.fromPosition(TextPosition(offset: saPct.toStringAsFixed(0).length)),
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Slider(
                  value: saPct,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${saPct.toStringAsFixed(0)}%',
                  onChanged: (v) {
                    setStateDialog(() {
                      saPct = v;
                      controller.text = saPct.toStringAsFixed(0);
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Company %: ${(100 - saPct).toStringAsFixed(0)}'),
                    const Text('Total: 100%'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final saFraction = (saPct / 100.0).clamp(0.0, 1.0);
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.id)
                      .update({
                    'commission': {
                      'superagent': saFraction,
                      'company': (1.0 - saFraction),
                    }
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Commission updated successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update commission: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  double? _parseShare(dynamic v) {
    if (v == null) return null;
    double? d;
    if (v is num) {
      d = v.toDouble();
    } else if (v is String) {
      d = double.tryParse(v);
    }
    if (d == null) return null;
    if (d > 1.0) return d / 100.0;
    if (d < 0.0) return 0.0;
    return d;
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _commissionDivisorController.dispose();
    super.dispose();
  }

  Future<void> _createNewAccount() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final double? techDivisor = _selectedRole == 'technician'
            ? (double.tryParse(_commissionDivisorController.text.trim()) ?? 30000.0)
            : null;
        await authController.createNewAccount(
          _emailController.text.trim(),
          _passwordController.text,
          _selectedRole,
          name: (_selectedRole == 'agent' || _selectedRole == 'superagent' || _selectedRole == 'technician')
              ? _nameController.text.trim()
              : null,
          location: _selectedRole == 'agent' ? _selectedLocation : null,
          locations: _selectedRole == 'superagent'
              ? _selectedLocations
              : (_selectedRole == 'technician' ? _technicianSelectedLocations : null),
          commissionDivisor: techDivisor,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created successfully!')),
          );
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _nameController.clear();
          _commissionDivisorController.text = '30000';
          setState(() {
            _selectedRole = 'technician';
            _selectedLocation = '';
            _selectedLocations.clear();
            _technicianSelectedLocations.clear();
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
                                      const DropdownMenuItem<String>(value: 'superagent', child: Text('Super Agent')),
                                      const DropdownMenuItem<String>(value: 'boss', child: Text('Boss')),
                                      const DropdownMenuItem<String>(value: 'md', child: Text('Main Director (MD)')),
                                    ],
                                    onChanged: (String? value) {
                                      if (value != null) {
                                        setState(() => _selectedRole = value);
                                        setDialogState(() {});
                                      }
                                    },
                                  ),
                                  if (_selectedRole == 'agent' || _selectedRole == 'superagent') ...[
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
                                    if (_selectedRole == 'agent') 
                                      // Single location selection for agent
                                      GestureDetector(
                                        onTap: () async {
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
                                      )
                                    else if (_selectedRole == 'superagent')
                                      // Multiple location selection for superagent
                                      GestureDetector(
                                        onTap: () async {
                                          await showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                            ),
                                            builder: (context) => StatefulBuilder(
                                              builder: (context, setBottomSheetState) => Container(
                                                height: MediaQuery.of(context).size.height * 0.7,
                                                child: Column(
                                                  children: [
                                                    const SizedBox(height: 16),
                                                    const Text('Select Locations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                    const Text('Super Agent can work in multiple locations', style: TextStyle(color: Colors.grey)),
                                                    const Divider(),
                                                    Expanded(
                                                      child: ListView(
                                                        children: locationController.locations.map((location) => CheckboxListTile(
                                                          title: Text(location),
                                                          value: _selectedLocations.contains(location),
                                                          onChanged: (bool? value) {
                                                            setBottomSheetState(() {
                                                              if (value == true) {
                                                                _selectedLocations.add(location);
                                                              } else {
                                                                _selectedLocations.remove(location);
                                                              }
                                                            });
                                                          },
                                                        )).toList(),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets.all(16.0),
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text('${_selectedLocations.length} locations selected'),
                                                          ElevatedButton(
                                                            onPressed: () {
                                                              Navigator.pop(context);
                                                              setDialogState(() {});
                                                            },
                                                            child: const Text('Done'),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        child: AbsorbPointer(
                                          child: TextFormField(
                                            decoration: InputDecoration(
                                              labelText: 'Locations',
                                              prefixIcon: const Icon(Icons.location_on_outlined),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                              filled: true,
                                              hintText: 'Select Multiple Locations',
                                            ),
                                            controller: TextEditingController(
                                              text: _selectedLocations.isEmpty 
                                                ? '' 
                                                : '${_selectedLocations.length} location${_selectedLocations.length == 1 ? '' : 's'} selected'
                                            ),
                                            validator: (value) {
                                              if (_selectedLocations.isEmpty) {
                                                return 'Please select at least one location';
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
                                if (_selectedRole == 'technician') ...[
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
                                      if (value == null || value.isEmpty) return 'Please enter a name';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  GestureDetector(
                                    onTap: () async {
                                      await showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                        ),
                                        builder: (context) => StatefulBuilder(
                                          builder: (context, setSheetState) => Container(
                                            height: MediaQuery.of(context).size.height * 0.7,
                                            child: Column(
                                              children: [
                                                const SizedBox(height: 16),
                                                const Text('Select Locations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                const Text('Technician can cover multiple locations', style: TextStyle(color: Colors.grey)),
                                                const Divider(),
                                                Expanded(
                                                  child: ListView(
                                                    children: locationController.locations.map((loc) => CheckboxListTile(
                                                      title: Text(loc),
                                                      value: _technicianSelectedLocations.contains(loc),
                                                      onChanged: (bool? val) {
                                                        setSheetState(() {
                                                          if (val == true) {
                                                            _technicianSelectedLocations.add(loc);
                                                          } else {
                                                            _technicianSelectedLocations.remove(loc);
                                                          }
                                                        });
                                                      },
                                                    )).toList(),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.all(16.0),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text('${_technicianSelectedLocations.length} locations selected'),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          Navigator.pop(context);
                                                          setDialogState(() {});
                                                        },
                                                        child: const Text('Done'),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    child: AbsorbPointer(
                                      child: TextFormField(
                                        decoration: InputDecoration(
                                          labelText: 'Locations',
                                          prefixIcon: const Icon(Icons.location_on_outlined),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                          filled: true,
                                          hintText: 'Select Locations',
                                        ),
                                        controller: TextEditingController(
                                          text: _technicianSelectedLocations.isEmpty
                                              ? ''
                                              : '${_technicianSelectedLocations.length} location${_technicianSelectedLocations.length == 1 ? '' : 's'} selected',
                                        ),
                                        validator: (value) {
                                          if (_technicianSelectedLocations.isEmpty) return 'Please select at least one location';
                                          return null;
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _commissionDivisorController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Commission Divisor',
                                      hintText: 'e.g. 30000',
                                      helperText: 'Commission = Payments total ÷ Divisor',
                                      prefixIcon: const Icon(Icons.calculate_outlined),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                      filled: true,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) return 'Enter a divisor';
                                      final v = double.tryParse(value);
                                      if (v == null || v <= 0) return 'Must be a positive number';
                                      return null;
                                    },
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

  Future<void> _confirmAndDeleteAppUser(DocumentSnapshot userDoc) async {
    final data = userDoc.data() as Map<String, dynamic>;
    final email = (data['email'] ?? '').toString();
    final name = (data['name'] ?? '').toString();
    final isSelf = authController.user?.uid == userDoc.id;

    if (isSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete your own account.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text('Are you sure you want to delete ${name.isNotEmpty ? '"$name" ' : ''}<$email>? This will remove the user from Firebase Auth and Firestore.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await authController.deleteAppUser(uid: userDoc.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete user: $e')),
        );
      }
    }
  }


  void _showEditUserDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final currentRole = userData['role']?.toString() ?? 'agent';
    final userName = userData['name']?.toString() ?? userData['email']?.toString() ?? '';
    final userLocation = userData['location']?.toString() ?? '';
    final userLocations = List<String>.from(userData['locations'] ?? []);
    final resolvedLocation = userLocations.isNotEmpty ? userLocations.first : userLocation;

    String roleLabel;
    switch (currentRole) {
      case 'superagent': roleLabel = 'Super Agent'; break;
      case 'technician': roleLabel = 'Technician'; break;
      case 'md': roleLabel = 'Main Director'; break;
      default: roleLabel = 'Agent';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $roleLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentRole == 'agent')
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Edit Bundles & Pricing'),
                subtitle: const Text('Manage allowed voucher bundles'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditAgentDialog(user);
                },
              ),
            if (currentRole != 'md')
              ListTile(
                leading: const Icon(Icons.location_on),
                title: Text('Edit ${(currentRole == 'superagent' || currentRole == 'technician') ? 'Locations' : 'Location'}'),
                subtitle: Text('Manage assigned ${(currentRole == 'superagent' || currentRole == 'technician') ? 'locations' : 'location'}'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditLocationDialog(user);
                },
              ),
            if (currentRole == 'technician')
              Builder(builder: (_) {
                final ud = user.data() as Map<String, dynamic>;
                double cur = 30000.0;
                final raw = ud['commission_divisor'];
                if (raw is num) cur = raw.toDouble();
                if (raw is String) cur = double.tryParse(raw) ?? cur;
                if (cur <= 0) cur = 30000.0;
                return ListTile(
                  leading: const Icon(Icons.calculate_rounded, color: Colors.deepPurple),
                  title: const Text('Set Commission Divisor'),
                  subtitle: Text(
                    'Current: ${cur.toStringAsFixed(0)}  ·  Commission = Payments ÷ ${cur.toStringAsFixed(0)}',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('÷${cur.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.deepPurple, fontSize: 12)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditTechnicianDivisorDialog(user);
                  },
                );
              }),
            if (currentRole == 'superagent')
              ListTile(
                leading: const Icon(Icons.percent),
                title: const Text('Edit Commission'),
                subtitle: const Text('Configure superagent/company split'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCommissionDialog(user);
                },
              ),
            if (currentRole == 'agent' || currentRole == 'superagent')
              ListTile(
                leading: const Icon(Icons.assignment_ind_outlined, color: Colors.teal),
                title: const Text('Field Details'),
                subtitle: const Text('Client sites, coordinates & equipment'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FieldDetailsScreen(
                        ownerId: user.id,
                        ownerName: userName,
                        ownerRole: currentRole,
                        ownerLocation: resolvedLocation,
                      ),
                    ),
                  );
                },
              ),
            if (authController.isBoss)
              ListTile(
                leading: const Icon(Icons.visibility_rounded, color: Colors.blueGrey),
                title: const Text('View Password'),
                subtitle: const Text('See the stored account password'),
                onTap: () {
                  Navigator.pop(context);
                  _showViewPasswordDialog(user.id, userName);
                },
              ),
            if ((authController.isBoss || (authController.isMD && currentRole != 'boss')) &&
                authController.user?.uid != user.id)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                title: const Text('Delete Account'),
                subtitle: const Text('Remove from Auth and Firestore'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmAndDeleteAppUser(user);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showViewPasswordDialog(String userId, String userName) {
    bool _obscure = true;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.lock_person_rounded, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Password — $userName', overflow: TextOverflow.ellipsis)),
                ],
              ),
              content: FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 60,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Text('User not found.');
                  }
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final password = data['password']?.toString() ?? '';
                  if (password.isEmpty) {
                    return const Text(
                      'No password stored.\nThis account was created before password storage was enabled.',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Account Password:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _obscure ? '•' * password.length : password,
                                style: const TextStyle(fontSize: 16, fontFamily: 'monospace', letterSpacing: 1.5),
                              ),
                            ),
                            IconButton(
                              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                              onPressed: () => setDialogState(() => _obscure = !_obscure),
                              tooltip: _obscure ? 'Reveal' : 'Hide',
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: password));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Password copied to clipboard')),
                                );
                              },
                              tooltip: 'Copy',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showChangePasswordDialog(userId, userName);
                  },
                  child: const Text('Change Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangePasswordDialog(String userId, String userName) {
    final _newPassController = TextEditingController();
    final _confirmPassController = TextEditingController();
    bool _obscureNew = true;
    bool _obscureConfirm = true;
    final _formKey = GlobalKey<FormState>();
    bool _isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.lock_reset_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Change Password — $userName', overflow: TextOverflow.ellipsis)),
                ],
              ),
              content: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _newPassController,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setDialogState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter new password';
                        if (v.length < 6) return 'Minimum 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPassController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setDialogState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v != _newPassController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) return;
                          setDialogState(() => _isLoading = true);
                          try {
                            final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
                            final email = (userDoc.data() as Map<String, dynamic>)['email']?.toString() ?? '';
                            final authController = Get.find<AuthController>();
                            final response = await authController.callResetUserPassword(
                              email: email,
                              newPassword: _newPassController.text,
                            );
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(response ? 'Password changed for $userName' : 'Failed to change password'),
                                  backgroundColor: response ? Colors.green : Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => _isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                  child: _isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditLocationDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final currentRole = userData['role']?.toString() ?? 'agent';
    
    if (currentRole == 'superagent' || currentRole == 'technician') {
      _showEditSuperAgentLocationsDialog(user);
    } else {
      _showEditAgentLocationDialog(user);
    }
  }

  void _showEditAgentLocationDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final currentLocation = userData['location']?.toString() ?? '';
    String selectedLocation = currentLocation;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Agent Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select new location for this agent:'),
            const SizedBox(height: 16),
            Obx(() {
              final locations = locationController.locations;
              return DropdownButtonFormField<String>(
                value: selectedLocation.isEmpty ? null : selectedLocation,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
                items: locations.map((location) => DropdownMenuItem<String>(
                  value: location,
                  child: Text(location),
                )).toList(),
                onChanged: (String? newLocation) {
                  selectedLocation = newLocation ?? '';
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedLocation.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.id)
                    .update({'location': selectedLocation});
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Agent location updated successfully!')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showEditSuperAgentLocationsDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final currentRole = userData['role']?.toString() ?? 'agent';
    final isTechnician = currentRole == 'technician';
    final currentLocations = List<String>.from(userData['locations'] ?? []);
    final selectedLocations = Set<String>.from(currentLocations);
    // Seed with single 'location' if present (common for agents/technicians)
    final singleLocation = (userData['location']?.toString() ?? '');
    if (singleLocation.isNotEmpty) {
      selectedLocations.add(singleLocation);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isTechnician ? 'Edit Technician Locations' : 'Edit Super Agent Locations'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isTechnician ? 'Select locations for this technician:' : 'Select locations for this super agent:'),
                const SizedBox(height: 16),
                Flexible(
                  child: Obx(() {
                    final locations = locationController.locations;
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: locations.length,
                      itemBuilder: (context, index) {
                        final location = locations[index];
                        final isSelected = selectedLocations.contains(location);
                        return CheckboxListTile(
                          title: Text(location),
                          value: isSelected,
                          onChanged: (bool? checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedLocations.add(location);
                              } else {
                                selectedLocations.remove(location);
                              }
                            });
                          },
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedLocations.isEmpty ? null : () async {
                final updates = <String, dynamic>{
                  'locations': selectedLocations.toList(),
                };
                if (isTechnician) {
                  updates['location'] = selectedLocations.isNotEmpty ? selectedLocations.first : '';
                }
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.id)
                    .update(updates);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isTechnician ? 'Technician locations updated successfully!' : 'Super agent locations updated successfully!')),
                );
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAgentDialog(DocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    final allowedBundlesMap = Map<String, dynamic>.from(userData['allowed_bundles'] ?? {});
    setState(() {
      _availableAmountOptions = allowedBundlesMap.entries.map((entry) {
        final bundle = entry.value;
        return {
          'quantity': entry.key,
          'price': bundle is Map ? bundle['price'] : bundle,
          'days': bundle is Map ? bundle['days'] : 1,
        };
      }).toList();

      if (_availableAmountOptions.isNotEmpty) {
        _selectedQuantity = _availableAmountOptions.first['quantity'];
      } else {
        _selectedQuantity = '';
      }
    });
    
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
            final priceControllers = {
              for (var doc in allMasterBundles)
                doc.id: TextEditingController(
                  text: allowedBundlesMap[doc.id] is Map ?
                    (allowedBundlesMap[doc.id]['price']?.toString() ?? '') :
                    (allowedBundlesMap[doc.id]?.toString() ?? ''),
                )
            };
            final daysControllers = {
              for (var doc in allMasterBundles)
                doc.id: TextEditingController(
                  text: allowedBundlesMap[doc.id] is Map ?
                    (allowedBundlesMap[doc.id]['days']?.toString() ?? '1') :
                    '1',
                )
            };

            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: Text('Edit Agent Bundles, Prices & Days'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: allMasterBundles.map((bundleDoc) {
                        final bundleId = bundleDoc.id;
                        final priceController = priceControllers[bundleId]!;
                        final daysController = daysControllers[bundleId]!;
                        bool isEnabled = allowedBundlesMap.containsKey(bundleId);

                        return Column(
                          children: [
                            CheckboxListTile(
                              title: Text('Voucher Bundle $bundleId'),
                              value: isEnabled,
                              onChanged: (bool? isChecked) {
                                setDialogState(() {
                                  if (isChecked == true) {
                                    allowedBundlesMap[bundleId] = {
                                      'price': num.tryParse(priceController.text) ?? 0,
                                      'days': int.tryParse(daysController.text) ?? 1,
                                    };
                                  } else {
                                    allowedBundlesMap.remove(bundleId);
                                  }
                                });
                              },
                            ),
                            if (isEnabled)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: priceController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Price for Bundle $bundleId',
                                        prefixText: 'TSH ',
                                      ),
                                      onChanged: (value) {
                                        allowedBundlesMap[bundleId] = {
                                          'price': num.tryParse(value) ?? 0,
                                          'days': int.tryParse(daysController.text) ?? 1,
                                        };
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: daysController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Days for Bundle $bundleId',
                                        prefixIcon: Icon(Icons.calendar_today),
                                      ),
                                      onChanged: (value) {
                                        allowedBundlesMap[bundleId] = {
                                          'price': num.tryParse(priceController.text) ?? 0,
                                          'days': int.tryParse(value) ?? 1,
                                        };
                                      },
                                    ),
                                  ],
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
                        // Remove bundles with price <= 0 or days <= 0
                        final newBundles = Map<String, dynamic>.from(allowedBundlesMap)
                          ..removeWhere((key, value) =>
                            (value is Map && ((value['price'] ?? 0) <= 0 || (value['days'] ?? 0) <= 0))
                          );
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

  void _showSitesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_city_rounded, color: Colors.teal, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Manage Sites', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Create and manage site profiles visible on the dashboard.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SiteRegistrationScreen()));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Site'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: SiteService.streamAll(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return const Center(child: Text('No sites registered yet.\nTap "Add New Site" to create one.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)));
                    }
                    return ListView.builder(
                      controller: sc,
                      itemCount: snap.data!.docs.length,
                      itemBuilder: (context, i) {
                        final doc = snap.data!.docs[i];
                        final d = doc.data();
                        final name = d['name'] as String? ?? 'Site';
                        final loc = d['main_location'] as String? ?? '';
                        final agentCount = (d['agent_ids'] as List?)?.length ?? 0;
                        final custCount = (d['home_customer_ids'] as List?)?.length ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.teal.withOpacity(0.1), child: const Icon(Icons.location_city_rounded, color: Colors.teal)),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('$loc  •  $agentCount agents  •  $custCount customers'),
                            trailing: PopupMenuButton(
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility_outlined, size: 18), SizedBox(width: 10), Text('View')])),
                                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Edit')])),
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text('Delete', style: TextStyle(color: Colors.red))])),
                              ],
                              onSelected: (val) async {
                                if (val == 'view') {
                                  Navigator.pop(ctx);
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => SiteOverviewScreen(siteId: doc.id)));
                                } else if (val == 'edit') {
                                  Navigator.pop(ctx);
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => SiteRegistrationScreen(existingId: doc.id, existingData: d)));
                                } else if (val == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Delete Site'),
                                      content: Text('Delete "$name"? This cannot be undone.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await SiteService.delete(doc.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$name" deleted.')));
                                    }
                                  }
                                }
                              },
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
        ),
      ),
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
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TechnicianDivisorsScreen()),
            ),
            icon: const Icon(Icons.calculate_rounded, color: Colors.deepPurple),
            label: const Text('Divisors', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(
            onPressed: () => _showSitesSheet(context),
            icon: const Icon(Icons.location_city_rounded, color: Colors.teal),
            label: const Text('Sites', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600)),
          ),
        ],
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
                        : currentRole == 'md'
                            ? Colors.amber.shade700
                            : currentRole == 'superagent'
                                ? Colors.purple
                                : currentRole == 'agent'
                                    ? Colors.blue
                                    : currentRole == 'homeuser'
                                        ? Colors.orange
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
                                    : currentRole == 'md'
                                        ? Icons.admin_panel_settings
                                        : currentRole == 'superagent'
                                            ? Icons.supervisor_account
                                            : currentRole == 'agent'
                                                ? Icons.person
                                                : currentRole == 'homeuser'
                                                    ? Icons.home
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
                        if (currentRole != 'boss' &&
                            !(authController.isMD && currentRole == 'boss'))
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditUserDialog(user),
                          ),
                        if (currentRole != 'boss')
                        DropdownButton<String>(
                              value: currentRole,
                              underline: const SizedBox(),
                              items: <DropdownMenuItem<String>>[
                                const DropdownMenuItem<String>(
                                    value: 'technician', child: Text('Technician')),
                                const DropdownMenuItem<String>(
                                    value: 'agent', child: Text('Agent')),
                                const DropdownMenuItem<String>(
                                    value: 'superagent', child: Text('Super Agent')),
                                const DropdownMenuItem<String>(
                                    value: 'boss', child: Text('Boss')),
                                const DropdownMenuItem<String>(
                                    value: 'homeuser', child: Text('Home User')),
                                const DropdownMenuItem<String>(
                                    value: 'md', child: Text('MD')),
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