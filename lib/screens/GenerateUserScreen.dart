import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
  final _speedLimitController = TextEditingController();
  final _newLocationController = TextEditingController();

  String? selectedLocation;
  final LocationController locationController = Get.find();

  void _generateUsers() async {
    if (_formKey.currentState!.validate()) {
      final numUsers = int.parse(_numUsersController.text);
      final numDays = double.parse(_numDaysController.text);

      final result = await ApiService.generateUsers(
        numUsers: numUsers,
        numDays: numDays,
        location: selectedLocation!,
        speedLimit: _speedLimitController.text,
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

  void _addLocation() async {
    final newLoc = _newLocationController.text.trim();
    if (newLoc.isEmpty) return;

    try {
      await locationController.addLocation(newLoc);
      _newLocationController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Location added")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void dispose() {
    _numUsersController.dispose();
    _numDaysController.dispose();
    _speedLimitController.dispose();
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
                        labelText: "Add New Location",
                        prefixIcon: Icon(Icons.edit_location_alt),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                    onPressed: _addLocation,
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
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Number of Days (Timeout)",
                  prefixIcon: Icon(Icons.timer),
                ),
                validator: (value) =>
                value == null || value.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _speedLimitController,
                decoration: const InputDecoration(
                  labelText: "Speed Limit (optional)",
                  prefixIcon: Icon(Icons.speed),
                  helperText: "Format: Upload/Download e.g., 5M/2M",
                ),
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
