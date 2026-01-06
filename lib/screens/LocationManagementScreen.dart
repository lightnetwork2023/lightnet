import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationManagementScreen extends StatefulWidget {
  @override
  _LocationManagementScreenState createState() => _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<LocationItem> _locations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() => _isLoading = true);
    
    try {
      final snapshot = await _firestore.collection('locations').get();
      final locations = <LocationItem>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        locations.add(LocationItem(
          id: doc.id,
          name: doc.id,
          type: data['type'] as String?,
          parentLocation: data['parent_location'] as String?,
        ));
      }
      
      // Sort: main locations first, then sublocations
      locations.sort((a, b) {
        final aIsMain = a.type == 'main' || a.type == null;
        final bIsMain = b.type == 'main' || b.type == null;
        if (aIsMain && !bIsMain) return -1;
        if (!aIsMain && bIsMain) return 1;
        return a.name.compareTo(b.name);
      });
      
      setState(() {
        _locations = locations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading locations: $e')),
      );
    }
  }

  Future<void> _editLocation(LocationItem location) async {
    String? selectedType = location.type ?? 'main';
    String? selectedParent = location.parentLocation;
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Get available main locations for parent selection
          final mainLocations = _locations
              .where((loc) => 
                  (loc.type == 'main' || loc.type == null) && 
                  loc.id != location.id)
              .map((loc) => loc.name)
              .toList();
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit_location, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Edit Location',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location Name Display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.blue[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Location Name',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                location.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Location Type Selection
                  Text(
                    'Location Type',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Icon(Icons.business, size: 18, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        const Text('Main Location'),
                      ],
                    ),
                    subtitle: const Text('Independent location'),
                    value: 'main',
                    groupValue: selectedType,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedType = value;
                        if (value == 'main') {
                          selectedParent = null;
                        }
                      });
                    },
                  ),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Icon(Icons.account_tree, size: 18, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        const Text('Sublocation'),
                      ],
                    ),
                    subtitle: const Text('Belongs to a main location'),
                    value: 'sublocation',
                    groupValue: selectedType,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedType = value;
                      });
                    },
                  ),
                  
                  // Parent Location Selection (if sublocation)
                  if (selectedType == 'sublocation') ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Parent Main Location *',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (mainLocations.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No main locations available',
                                style: TextStyle(
                                  color: Colors.orange[900],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: mainLocations.contains(selectedParent) ? selectedParent : null,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.account_tree),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        hint: const Text('Select parent location'),
                        items: mainLocations
                            .map((loc) => DropdownMenuItem(
                                  value: loc,
                                  child: Text(loc),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedParent = value;
                          });
                        },
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              // Delete button on the left
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteLocation(location);
                },
                icon: Icon(Icons.delete, color: Colors.red[700]),
                label: Text(
                  'Delete',
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
              const Spacer(),
              // Cancel and Save on the right
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Validate
                  if (selectedType == 'sublocation' && selectedParent == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ Please select a parent location')),
                    );
                    return;
                  }
                  
                  Navigator.pop(context, {
                    'type': selectedType,
                    'parentLocation': selectedParent,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
    
    if (result != null) {
      await _updateLocation(
        location.id,
        result['type'] as String,
        result['parentLocation'] as String?,
      );
    }
  }

  Future<void> _updateLocation(String locationId, String type, String? parentLocation) async {
    try {
      final data = <String, dynamic>{'type': type};
      
      if (type == 'sublocation' && parentLocation != null) {
        data['parent_location'] = parentLocation;
      } else {
        // Remove parent_location if converting to main
        data['parent_location'] = FieldValue.delete();
      }
      
      await _firestore.collection('locations').doc(locationId).update(data);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Location updated successfully')),
      );
      
      // Reload locations
      await _loadLocations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error updating location: $e')),
      );
    }
  }

  Future<void> _deleteLocation(LocationItem location) async {
    // Check if location has sublocations
    final hasSublocations = _locations.any((loc) => loc.parentLocation == location.id);
    
    if (hasSublocations) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Cannot delete location with sublocations. Remove sublocations first.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 12),
            const Text('Delete Location?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Text(
                location.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await _firestore.collection('locations').doc(location.id).delete();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Location deleted successfully')),
        );
        
        await _loadLocations();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error deleting location: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Management'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No locations found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLocations,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _locations.length,
                    itemBuilder: (context, index) {
                      final location = _locations[index];
                      final isMain = location.type == 'main' || location.type == null;
                      final hasSublocations = _locations.any((loc) => loc.parentLocation == location.id);
                      final sublocationCount = _locations.where((loc) => loc.parentLocation == location.id).length;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isMain ? Colors.blue[200]! : Colors.orange[200]!,
                            width: 1.5,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _editLocation(location),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Type Icon
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isMain ? Colors.blue[50] : Colors.orange[50],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        isMain ? Icons.business : Icons.account_tree,
                                        color: isMain ? Colors.blue[700] : Colors.orange[700],
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    
                                    // Location Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            location.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isMain ? Colors.blue[100] : Colors.orange[100],
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isMain ? 'MAIN' : 'SUB',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isMain ? Colors.blue[900] : Colors.orange[900],
                                                  ),
                                                ),
                                              ),
                                              if (!isMain && location.parentLocation != null) ...[
                                                const SizedBox(width: 8),
                                                Icon(Icons.arrow_forward, size: 12, color: Colors.grey[400]),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    location.parentLocation!,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                              if (isMain && hasSublocations) ...[
                                                const SizedBox(width: 8),
                                                Icon(Icons.subdirectory_arrow_right, size: 12, color: Colors.grey[400]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$sublocationCount sub${sublocationCount != 1 ? 's' : ''}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Action Buttons
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.blue[700]),
                                      onPressed: () => _editLocation(location),
                                      tooltip: 'Edit location',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class LocationItem {
  final String id;
  final String name;
  final String? type;
  final String? parentLocation;

  LocationItem({
    required this.id,
    required this.name,
    this.type,
    this.parentLocation,
  });
}
