import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:lightnetwork/screens/widgets/FullScreenImageViewer.dart';
import 'package:lightnetwork/screens/widgets/device_form.dart';
// ... other imports (ImagePicker, dart:io, intl) ...

// FullScreenImageViewer definition (as you provided)

// --- NetworkDevicesScreen Widget ---
class NetworkDevicesScreen extends StatefulWidget {
  const NetworkDevicesScreen({Key? key}) : super(key: key);

  @override
  _NetworkDevicesScreenState createState() => _NetworkDevicesScreenState();
}

class _NetworkDevicesScreenState extends State<NetworkDevicesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  List<Map<String, dynamic>> _zones = [];
  bool _isLoadingZones = true;
  String? _selectedZoneName;

  List<Map<String, dynamic>> _devices = [];
  bool _isLoadingDevices = true;

  String? _selectedSubLocationFilter;
  List<String> _subLocationNames = [];
  bool _isLoadingSubLocations = true;

  @override
  void initState() {
    super.initState();
    _fetchZones();
  }

  Future<void> _fetchZones() async {
    if (!mounted) return;
    setState(() {
      _isLoadingZones = true;
      _zones = [];
    });
    try {
      final snapshot = await _firestore.collection('zones').orderBy('name_lowercase').get();
      if (mounted) {
        setState(() {
          _zones = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
          _isLoadingZones = false;
        });
      }
    } catch (e) {
      print("Error fetching zones: $e");
      if (mounted) {
        setState(() => _isLoadingZones = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load zones: $e')),
        );
      }
    }
  }

  Future<void> _fetchSubLocationsForZone() async {
    if (_selectedZoneName == null || !mounted) {
      if (mounted) {
        setState(() {
          _subLocationNames = ['All Sub-Locations'];
          _selectedSubLocationFilter = 'All Sub-Locations';
          _isLoadingSubLocations = false;
        });
      }
      return;
    }
    setState(() => _isLoadingSubLocations = true);
    try {
      final snapshot = await _firestore
          .collection('deviceLocations')
          .where('zoneName', isEqualTo: _selectedZoneName)
          .orderBy('name_lowercase')
          .get();
      final names = snapshot.docs.map((doc) {
        final data = doc.data();
        return (data.containsKey('name') && data['name'] is String) ? data['name'] as String : null;
      }).whereType<String>().toList();

      if (mounted) {
        setState(() {
          _subLocationNames = ['All Sub-Locations', ...names.toSet().toList()];
          _isLoadingSubLocations = false;
          if (_selectedSubLocationFilter != null && !_subLocationNames.contains(_selectedSubLocationFilter)) {
            _selectedSubLocationFilter = 'All Sub-Locations';
          } else if (_selectedSubLocationFilter == null) {
            _selectedSubLocationFilter = 'All Sub-Locations';
          }
        });
      }
    } catch (e) {
      print("Error fetching sub-locations for zone $_selectedZoneName: $e");
      if (mounted) {
        setState(() => _isLoadingSubLocations = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sub-locations: $e')),
        );
      }
    }
  }

  Future<void> _fetchDevicesForZone() async {
    if (_selectedZoneName == null || !mounted) {
      if(mounted) setState(() => _devices = []);
      return;
    }
    setState(() => _isLoadingDevices = true);
    try {
      Query query = _firestore
          .collection('devices')
          .where('zoneName', isEqualTo: _selectedZoneName)
          .orderBy('namee');

      if (_selectedSubLocationFilter != null &&
          _selectedSubLocationFilter != 'All Sub-Locations' &&
          _selectedSubLocationFilter!.isNotEmpty) {
        query = query.where('location', isEqualTo: _selectedSubLocationFilter);
      }

      final snapshot = await query.get();
      final invalidDocs = <String, Map<String, dynamic>>{};
      final List<Map<String, dynamic>> validDevices = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final hasValidNamee = data.containsKey('namee') && data['namee'] != null && data['namee'] is String && (data['namee'] as String).trim().isNotEmpty;
        final hasValidType = data.containsKey('type') && data['type'] != null && data['type'] is String && (data['type'] as String).trim().isNotEmpty;

        if (hasValidNamee && hasValidType) {
          validDevices.add({
            'id': doc.id,
            'namee': data['namee'] as String,
            'type': data['type'] as String,
            'mac_address': data['mac_address'] as String? ?? 'N/A',
            'location': data['location'] as String? ?? 'N/A',
            'zoneName': data['zoneName'] as String? ?? _selectedZoneName,
            'image_url': data['image_url'] as String?,
            'created_at': data['created_at'] as Timestamp?,
            'updated_at': data['updated_at'] as Timestamp?,
          });
        } else {
          invalidDocs[doc.id] = data;
        }
      }

      if (invalidDocs.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${invalidDocs.length} invalid device(s). Consider cleaning data.'),
            action: SnackBarAction(
              label: 'Attempt Clean Up',
              onPressed: () => _cleanUpInvalidDevices(invalidDocs.keys.toList()),
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _devices = validDevices;
          _isLoadingDevices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDevices = false);
      }
      print('Fetch devices error for zone $_selectedZoneName: $e');
      if(e.toString().contains('firestore/failed-precondition') && e.toString().contains('index')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Firestore query requires an index. Please create it in Firebase console.'), duration: Duration(seconds: 5),),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load devices: $e')),
        );
      }
    }
  }

  Future<void> _cleanUpInvalidDevices(List<String> invalidDocIds) async {
    try {
      final batch = _firestore.batch();
      for (var docId in invalidDocIds) {
        final docRef = _firestore.collection('devices').doc(docId);
        batch.delete(docRef);
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attempted to remove invalid devices successfully')),
        );
      }
      _fetchDevicesForZone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clean up invalid devices: $e')),
        );
      }
    }
  }

  void _showDeviceFormDialog({Map<String, dynamic>? device}) {
    if (_selectedZoneName == null) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a zone first to add a device.')),
        );
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DeviceForm(
        onSave: () {
          _fetchDevicesForZone();
          _fetchSubLocationsForZone();
        },
        device: device,
        selectedZoneName: _selectedZoneName!,
      ),
    );
  }

  Future<void> _deleteDevice(String deviceId, String? imageUrl) async {
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        if (imageUrl.startsWith('gs://') || imageUrl.startsWith('http')) {
          await _storage.refFromURL(imageUrl).delete().catchError((e) {
            print("Error deleting image from storage, might not exist or permissions issue: $e");
          });
        } else {
          print("Invalid image URL format, cannot delete from storage: $imageUrl");
        }
      }
      await _firestore.collection('devices').doc(deviceId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device deleted successfully')),
        );
      }
      _fetchDevicesForZone();
    } catch (e) {
      print('Error deleting device or image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete device: $e')),
        );
      }
    }
  }

  void _showAddZoneDialog() {
    final TextEditingController zoneNameController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Zone'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: zoneNameController,
              decoration: const InputDecoration(labelText: 'Zone Name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Zone name cannot be empty';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final zoneName = zoneNameController.text.trim();
                  Navigator.pop(context);
                  await _addZoneToFirestore(zoneName);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addZoneToFirestore(String zoneName) async {
    if (!mounted) return;
    try {
      final existingZone = await _firestore
          .collection('zones')
          .where('name_lowercase', isEqualTo: zoneName.toLowerCase())
          .limit(1)
          .get();

      if (existingZone.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zone "$zoneName" already exists.')),
          );
        }
        return;
      }

      await _firestore.collection('zones').add({
        'name': zoneName,
        'name_lowercase': zoneName.toLowerCase(),
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zone "$zoneName" added successfully')),
        );
      }
      _fetchZones();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add zone: $e')),
        );
      }
    }
  }

  Widget _buildZonesList() {
    if (_isLoadingZones) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_zones.isEmpty) {
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.map_outlined, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No zones found.', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add Your First Zone'),
                onPressed: _showAddZoneDialog,
              )
            ],
          )
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _zones.length,
      itemBuilder: (context, index) {
        final zone = _zones[index];
        final zoneName = zone['name'] as String? ?? 'Unnamed Zone';
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColorLight.withOpacity(0.3),
              child: Icon(Icons.public_outlined, color: Theme.of(context).primaryColor),
            ),
            title: Text(zoneName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 17)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.grey),
            onTap: () {
              setState(() {
                _selectedZoneName = zoneName;
                _devices = [];
                _subLocationNames = ['All Sub-Locations'];
                _selectedSubLocationFilter = 'All Sub-Locations';
                _isLoadingDevices = true;
                _isLoadingSubLocations = true;
              });
              _fetchSubLocationsForZone();
              _fetchDevicesForZone();
            },
          ),
        );
      },
    );
  }

  Widget _buildDevicesInZoneList() {
    return Column(
      children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
            child: _isLoadingSubLocations
                ? const LinearProgressIndicator()
                : (_subLocationNames.length <= 1
                ? const SizedBox.shrink()
                : DropdownButtonFormField<String>(
              value: _subLocationNames.contains(_selectedSubLocationFilter) ? _selectedSubLocationFilter : 'All Sub-Locations',
              hint: const Text('Filter by Sub-Location'),
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                prefixIcon: const Icon(Icons.pin_drop_outlined),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _subLocationNames.map((String subLocationName) {
                return DropdownMenuItem<String>(
                  value: subLocationName,
                  child: Text(subLocationName, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedSubLocationFilter = newValue;
                });
                _fetchDevicesForZone();
              },
            )
            )
        ),
        Expanded(
          child: _isLoadingDevices
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.devices_other_outlined, size: 60, color: Colors.grey),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    _selectedSubLocationFilter != null && _selectedSubLocationFilter != 'All Sub-Locations'
                        ? 'No devices found for "${_selectedSubLocationFilter}" in this zone.'
                        : 'No devices found in this zone. Add one!',
                    style: const TextStyle(fontSize: 17),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Device'),
                  onPressed: () => _showDeviceFormDialog(),
                )
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.only(left:16, right:16, bottom: 16, top:8),
            itemCount: _devices.length,
            itemBuilder: (context, index) {
              final device = _devices[index];
              final String? imageUrl = device['image_url'] as String?;
              final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

              final dateSaved = device['created_at'] != null
                  ? DateFormat('MMM d, yyyy HH:mm')
                  .format((device['created_at'] as Timestamp).toDate())
                  : 'N/A';

              return Card(
                elevation: 2.5,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  leading: hasImage ?
                  GestureDetector(
                    onTap: () => Navigator.push(context,MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrl: imageUrl!),),),
                    child: Hero(
                      tag: "device_image_${device['id']}",
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.network(
                          imageUrl!,
                          width: 55,
                          height: 55,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => const Icon(Icons.broken_image, size: 40),
                        ),
                      ),
                    ),
                  )
                      : CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Icon(Icons.router_outlined, size: 28, color: Theme.of(context).primaryColor),
                  ),
                  title: Text(
                    device['namee'] ?? 'Unnamed Device',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Type: ${device['type'] ?? 'N/A'}', style: const TextStyle(fontSize: 13)),
                        Text('Sub-Location: ${device['location'] ?? 'N/A'}', style: const TextStyle(fontSize: 13)),
                        if(device['mac_address'] != 'N/A' && (device['mac_address'] as String?)?.isNotEmpty == true)
                          Text('MAC: ${device['mac_address']}', style: const TextStyle(fontSize: 13)),
                        Text('Added: $dateSaved', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showDeviceFormDialog(device: device);
                      } else if (value == 'delete') {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Device'),
                            content: Text('Are you sure you want to delete "${device['namee'] ?? 'this device'}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteDevice(device['id'], imageUrl);
                                },
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      } else if (value == 'view_image' && hasImage) {
                        Navigator.push(context,MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrl: imageUrl!),),);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      if(hasImage)
                        const PopupMenuItem<String>(
                          value: 'view_image',
                          child: ListTile(leading: Icon(Icons.fullscreen), title: Text('View Image')),
                        ),
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red))),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _selectedZoneName == null ? Colors.white : Colors.grey[100],
      appBar: AppBar(
        elevation: _selectedZoneName == null ? 0.5 : 1.0,
        backgroundColor: _selectedZoneName == null ? Colors.white : Theme.of(context).primaryColor,
        foregroundColor: _selectedZoneName == null ? Colors.black87 : Colors.white,
        leading: _selectedZoneName != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _selectedZoneName = null;
              _devices = [];
              _subLocationNames = [];
              _selectedSubLocationFilter = null;
            });
          },
        )
            : null,
        title: Text(_selectedZoneName ?? 'Network Zones', style: TextStyle(fontWeight: _selectedZoneName == null ? FontWeight.w500: FontWeight.normal)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (){
              if (_selectedZoneName == null) {
                _fetchZones();
              } else {
                _fetchSubLocationsForZone();
                _fetchDevicesForZone();
              }
            },
            tooltip: _selectedZoneName == null ? 'Refresh Zones' : 'Refresh Devices & Sub-Locations',
          ),
        ],
      ),
      body: _selectedZoneName == null ? _buildZonesList() : _buildDevicesInZoneList(),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(_selectedZoneName == null ? 'New Zone' : 'New Device'),
        onPressed: () {
          if (_selectedZoneName == null) {
            _showAddZoneDialog();
          } else {
            _showDeviceFormDialog();
          }
        },
        tooltip: _selectedZoneName == null ? 'Add Zone' : 'Add Device to Zone',
      ),
    );
  }
}
