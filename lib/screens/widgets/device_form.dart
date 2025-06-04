import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// --- DeviceForm Widget ---
class DeviceForm extends StatefulWidget {
  final VoidCallback onSave;
  final Map<String, dynamic>? device;
  final bool bypassFetchAfterAdd;
  final String selectedZoneName;

  const DeviceForm({
    Key? key,
    required this.onSave,
    this.device,
    this.bypassFetchAfterAdd = false,
    required this.selectedZoneName,
  }) : super(key: key);

  @override
  _DeviceFormState createState() => _DeviceFormState();
}

class _DeviceFormState extends State<DeviceForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameeController = TextEditingController();
  final _macAddressController = TextEditingController();
  final _newSubLocationController = TextEditingController(); // For adding new sub-location
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  String? _selectedType;
  String? _selectedSubLocation; // Renamed from _selectedLocation
  File? _imageFile;
  String? _existingImageUrl; // To keep track of current image if editing
  bool _isSubmitting = false;
  final List<String> _deviceTypes = ['Access Point', 'Router', 'Link', 'Switch', 'Server', 'Camera', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.device != null) {
      _nameeController.text = widget.device!['namee'] ?? '';
      _macAddressController.text = widget.device!['mac_address'] != 'N/A' ? widget.device!['mac_address'] ?? '' : '';
      _selectedType = widget.device!['type'];
      _selectedSubLocation = widget.device!['location'] != 'N/A' ? widget.device!['location'] : null;
      _existingImageUrl = widget.device!['image_url'] as String?;
    }
  }

  Future<ImageSource?> _showImageSourceDialog(BuildContext context) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Pick from Gallery'),
                onTap: () {
                  Navigator.of(context).pop(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(context).pop(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final ImageSource? source = await _showImageSourceDialog(context);
    if (source == null || !mounted) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70, // Adjust quality as needed
        maxWidth: 1024,   // Adjust size as needed
        maxHeight: 1024,
      );
      if (image != null && mounted) {
        setState(() {
          _imageFile = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
        print("Image picking error: $e");
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;
    if (!mounted) return null;

    setState(() => _isSubmitting = true); // Indicate upload process if needed separately
    String fileName = _imageFile!.path.split('/').last;
    final ref = _storage.ref().child('device_images/${DateTime.now().millisecondsSinceEpoch}-$fileName');

    try {
      UploadTask uploadTask = ref.putFile(_imageFile!);
      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Image upload failed: $e")));
      }
      return null;
    } finally {
      if (mounted && _imageFile != null) setState(() => _isSubmitting = false); // Reset only if it was for image
    }
  }

  Future<void> _addOrUpdateSubLocation() async {
    final newSubLocName = _newSubLocationController.text.trim();
    if (newSubLocName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a sub-location name')),
        );
      }
      return;
    }

    if (!mounted) return;
    // Consider a specific loading state for this small operation
    // setState(() => _isAddingSubLocation = true);
    try {
      final querySnapshot = await _firestore
          .collection('deviceLocations')
          .where('zoneName', isEqualTo: widget.selectedZoneName)
          .where('name_lowercase', isEqualTo: newSubLocName.toLowerCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sub-location "$newSubLocName" already exists in this zone.')),
          );
        }
        return;
      }

      await _firestore.collection('deviceLocations').add({
        'name': newSubLocName,
        'name_lowercase': newSubLocName.toLowerCase(),
        'zoneName': widget.selectedZoneName,
        'created_at': FieldValue.serverTimestamp(),
      });
      _newSubLocationController.clear();
      if (mounted) {
        setState(() {
          _selectedSubLocation = newSubLocName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sub-location added. Select it from the dropdown.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add sub-location: $e')),
        );
      }
    } finally {
      // if (mounted) setState(() => _isAddingSubLocation = false);
    }
  }

  Future<void> _saveDevice() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() => _isSubmitting = true);

    String? finalImageUrl = _existingImageUrl; // Start with existing

    try {
      if (_imageFile != null) { // If a new image was picked
        // Delete old image from storage if it exists and is different
        if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
          try {
            if (_existingImageUrl!.startsWith('gs://') || _existingImageUrl!.startsWith('http')) {
              await _storage.refFromURL(_existingImageUrl!).delete().catchError((e) {
                print("Warning: Failed to delete old image (it might not exist or permissions issue): $e");
              });
            }
          } catch (e) {
            print("Error trying to delete old image: $e"); // Log but continue
          }
        }
        finalImageUrl = await _uploadImage(); // Upload new image
        if (finalImageUrl == null && _imageFile != null) { // Upload failed but an image was selected
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image upload failed. Device saved without new image.")));
          finalImageUrl = _existingImageUrl; // Revert to old image if upload failed
        }
      }

      final deviceData = {
        'namee': _nameeController.text.trim(),
        'type': _selectedType!,
        'mac_address': _macAddressController.text.trim().isEmpty ? null : _macAddressController.text.trim().toUpperCase(),
        'location': _selectedSubLocation ?? 'N/A',
        'zoneName': widget.selectedZoneName,
        'image_url': finalImageUrl, // Use the determined final image URL
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (widget.device == null) {
        deviceData['created_at'] = FieldValue.serverTimestamp();
        await _firestore.collection('devices').add(deviceData);
      } else {
        deviceData['created_at'] = widget.device!['created_at'] ?? FieldValue.serverTimestamp();
        await _firestore.collection('devices').doc(widget.device!['id']).update(deviceData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.device == null ? 'Device added successfully' : 'Device updated successfully')),
        );
        Navigator.pop(context);
      }
      if (!widget.bypassFetchAfterAdd) {
        widget.onSave();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save device: $e')),
        );
      }
      print("Error saving device: $e");
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16, // Added extra padding
        left: 16,
        right: 16,
        top: 20, // Added top padding
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  widget.device == null ? 'Add New Device' : 'Edit Device',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Center(child: Text("Zone: ${widget.selectedZoneName}", style: TextStyle(color: Colors.grey.shade700, fontSize: 15))),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameeController,
                decoration: const InputDecoration(
                  labelText: 'Device Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.devices_other_outlined),
                ),
                validator: (value) =>
                value?.trim().isEmpty ?? true ? 'Device name is required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Device Type *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _deviceTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (value) => setState(() => _selectedType = value),
                validator: (value) => value == null ? 'Please select a device type' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _macAddressController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'MAC Address (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.network_wifi_3_bar_outlined),
                  helperText: 'e.g., 00:1A:2B:3C:4D:5E',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
                  if (!macRegex.hasMatch(value.trim())) {
                    return 'Invalid MAC address format';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('deviceLocations')
                    .where('zoneName', isEqualTo: widget.selectedZoneName)
                    .orderBy('name_lowercase')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    print('Error loading sub-locations for form: ${snapshot.error}');
                    return Text('Error: ${snapshot.error}');
                  }

                  String currentHintText = 'Select Sub-Location';
                  List<DropdownMenuItem<String>> subLocationItems = [];

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    currentHintText = 'Loading sub-locations...';
                  } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    currentHintText = 'No sub-locations in this zone yet';
                  } else {
                    final List<String> fetchedSubLocations = [];
                    for (var doc in snapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>?;
                      if (data != null && data.containsKey('name')) {
                        final nameValue = data['name'];
                        if (nameValue is String && nameValue.isNotEmpty) {
                          fetchedSubLocations.add(nameValue);
                        }
                      }
                    }
                    subLocationItems = fetchedSubLocations.map((loc) {
                      return DropdownMenuItem(value: loc, child: Text(loc));
                    }).toList();
                    if (_selectedSubLocation != null && !fetchedSubLocations.contains(_selectedSubLocation) && widget.device != null) {
                      // This case can happen if a sub-location was deleted after device was saved with it.
                      // Decide how to handle: clear selection, show placeholder, or keep the (now invalid) value.
                      // For now, let it be, it might just not appear as selected.
                    }
                  }

                  return DropdownButtonFormField<String>(
                    value: _selectedSubLocation,
                    decoration: InputDecoration(
                      labelText: 'Device Sub-Location',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.pin_drop_outlined),
                    ),
                    items: subLocationItems,
                    onChanged: (value) => setState(() => _selectedSubLocation = value),
                    hint: Text(currentHintText),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _newSubLocationController,
                      decoration: const InputDecoration(
                        labelText: 'Or Add New Sub-Location',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.add_location_alt_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 30),
                    onPressed: _isSubmitting ? null : _addOrUpdateSubLocation,
                    tooltip: 'Add New Sub-Location to this Zone',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_imageFile != null || (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)) ...[
                    Text("Device Image Preview:", style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _imageFile != null
                            ? Image.file(_imageFile!, fit: BoxFit.contain)
                            : Image.network(
                          _existingImageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey,)),
                          loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(_imageFile == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty)
                        ? 'Add Device Image'
                        : 'Change Device Image'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        textStyle: const TextStyle(fontSize: 16)
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : (widget.device == null ? const Icon(Icons.add_circle_outline) : const Icon(Icons.save_alt_outlined)),
                onPressed: _isSubmitting ? null : _saveDevice,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
                label: Text(widget.device == null ? 'Add Device' : 'Update Device'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameeController.dispose();
    _macAddressController.dispose();
    _newSubLocationController.dispose();
    super.dispose();
  }
}