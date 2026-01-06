import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/ApiService.dart';
import '../controllers/location_controller.dart';

class GenerateUserScreen extends StatefulWidget {
  @override
  _GenerateUserScreenState createState() => _GenerateUserScreenState();
}

class _GenerateUserScreenState extends State<GenerateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numUsersController = TextEditingController();
  final _numDaysController = TextEditingController();
  final _newLocationController = TextEditingController();

  String? selectedLocation;
  String? selectedSpeedLimit;
  String? selectedParentLocation;
  final LocationController locationController = Get.find();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<String> _mainLocations = [];
  bool _isLoadingMainLocations = true;

  // Speed limit options from 10M/10M to 100M/100M
  final List<String> speedLimitOptions = List.generate(
    10,
    (index) {
      final speed = (index + 1) * 10;
      return '${speed}M/${speed}M';
    },
  );

  void _generateUsers() async {
    if (_formKey.currentState!.validate()) {
      final numUsers = int.parse(_numUsersController.text);
      final numDays = double.parse(_numDaysController.text);

      final result = await ApiService.generateUsers(
        numUsers: numUsers,
        numDays: numDays,
        location: selectedLocation!,
        speedLimit: selectedSpeedLimit,
      );

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('✅ Users Generated'),
          content: Text(result['message'] ?? 'Success'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<List<String>> _getMainLocations() async {
    try {
      final snapshot = await _firestore.collection('locations').get();
      final mainLocations = <String>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Include locations with type='main' or locations without type field (backward compatible)
        if (data['type'] == 'main' || !data.containsKey('type')) {
          mainLocations.add(doc.id);
        }
      }
      
      return mainLocations;
    } catch (e) {
      print('Error fetching main locations: $e');
      return [];
    }
  }

  void _addLocation() async {
    final newLoc = _newLocationController.text.trim();
    if (newLoc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please enter location name")),
      );
      return;
    }

    if (selectedParentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please select a parent main location")),
      );
      return;
    }

    try {
      await locationController.addLocation(
        newLoc,
        type: 'sublocation',
        parentLocation: selectedParentLocation,
      );
      _newLocationController.clear();
      setState(() {
        selectedParentLocation = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Sublocation added")),
      );
      // Reload locations in case user wants to select it for generating users
      await locationController.loadLocations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMainLocations();
  }

  Future<void> _loadMainLocations() async {
    final locations = await _getMainLocations();
    setState(() {
      _mainLocations = locations;
      _isLoadingMainLocations = false;
    });
  }

  @override
  void dispose() {
    _numUsersController.dispose();
    _numDaysController.dispose();
    _newLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("👥 Generate Users")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                "📍 Location",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Obx(() => DropdownButtonFormField<String>(
                value: selectedLocation,
                hint: const Text("Select Location"),
                icon: const Icon(Icons.location_on),
                onChanged: (value) => setState(() => selectedLocation = value),
                items: locationController.locations
                    .map((loc) => DropdownMenuItem(value: loc, child: Text(loc)))
                    .toList(),
                validator: (value) => value == null ? "Please select a location" : null,
              )),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _newLocationController,
                      decoration: const InputDecoration(
                        labelText: "Add New Sublocation",
                        prefixIcon: Icon(Icons.edit_location_alt),
                        helperText: "Only sublocations can be added here",
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                    onPressed: _addLocation,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Parent Location Selection (always visible now)
              if (_isLoadingMainLocations)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedParentLocation,
                      decoration: const InputDecoration(
                        labelText: "Select Main Location *",
                        prefixIcon: Icon(Icons.account_tree),
                        helperText: "Choose which main location this sublocation belongs to",
                      ),
                      items: _mainLocations
                          .map((loc) => DropdownMenuItem(
                                value: loc,
                                child: Text(loc),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedParentLocation = value;
                        });
                      },
                    ),
                    if (_mainLocations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 12),
                        child: Row(
                          children: [
                            Icon(Icons.warning, size: 16, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No main locations available. Create a main location first in Location Analytics.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              const Divider(height: 32),
              TextFormField(
                controller: _numUsersController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Number of Users",
                  prefixIcon: Icon(Icons.group_add),
                ),
                validator: (value) =>
                value == null || value.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _numDaysController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Number of Days (Timeout)",
                  prefixIcon: Icon(Icons.timer),
                  helperText: "Accepts decimal values (e.g., 0.5 for 12 hours)",
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return "Required";
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) return "Enter a valid positive number";
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedSpeedLimit,
                hint: const Text("Select Speed Limit (optional)"),
                icon: const Icon(Icons.speed),
                decoration: const InputDecoration(
                  labelText: "Speed Limit",
                  prefixIcon: Icon(Icons.speed),
                  helperText: "Select upload/download speed limit",
                ),
                onChanged: (value) => setState(() => selectedSpeedLimit = value),
                items: speedLimitOptions
                    .map((speed) => DropdownMenuItem(value: speed, child: Text(speed)))
                    .toList(),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                onPressed: _generateUsers,
                label: const Text("Generate Users"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}