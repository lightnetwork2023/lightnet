import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/ApiService.dart';
import '../controllers/location_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class UniFiAPManagementScreen extends StatefulWidget {
  const UniFiAPManagementScreen({Key? key}) : super(key: key);

  @override
  State<UniFiAPManagementScreen> createState() => _UniFiAPManagementScreenState();
}

class _UniFiAPManagementScreenState extends State<UniFiAPManagementScreen> {
  final LocationController _locationController = Get.find<LocationController>();
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _accessPoints = [];
  List<dynamic> _filteredAccessPoints = [];
  bool _isLoading = true;
  String? _filterLocation;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (_locationController.locations.isEmpty) {
      _locationController.loadLocations();
    }
    _loadAccessPoints();
  }

  Future<void> _loadAccessPoints() async {
    setState(() => _isLoading = true);
    try {
      final aps = await ApiService.getUnifiAPs(location: _filterLocation);
      setState(() {
        _accessPoints = aps;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Error loading APs: ${e.toString()}');
    }
  }

  void _applyFilters() {
    _filteredAccessPoints = _accessPoints.where((ap) {
      final matchesSearch = _searchQuery.isEmpty ||
          (ap['ap_name']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (ap['ap_mac']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      return matchesSearch;
    }).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _onLocationFilterChanged(String? location) {
    setState(() {
      _filterLocation = location;
    });
    _loadAccessPoints();
  }

  void _clearFilters() {
    setState(() {
      _filterLocation = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadAccessPoints();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddEditDialog({Map<String, dynamic>? ap}) {
    final isEdit = ap != null;
    final formKey = GlobalKey<FormState>();
    final macController = TextEditingController(text: ap?['ap_mac'] ?? '');
    final nameController = TextEditingController(text: ap?['ap_name'] ?? '');
    final notesController = TextEditingController(text: ap?['notes'] ?? '');
    String selectedLocation = ap?['location'] ?? '';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit : Icons.add_circle_outline,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 12),
              Text(isEdit ? 'Edit Access Point' : 'Add Access Point'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: macController,
                      decoration: const InputDecoration(
                        labelText: 'MAC Address *',
                        hintText: 'AA:BB:CC:DD:EE:FF',
                        prefixIcon: Icon(Icons.fingerprint),
                      ),
                      enabled: !isEdit,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f:.\-]')),
                        LengthLimitingTextInputFormatter(17),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'MAC address is required';
                        }
                        final cleaned = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
                        if (cleaned.length != 12) {
                          return 'Invalid MAC address format';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Obx(() {
                      final locations = _locationController.locations;
                      return DropdownButtonFormField<String>(
                        value: selectedLocation.isEmpty ? null : selectedLocation,
                        decoration: const InputDecoration(
                          labelText: 'Location *',
                          prefixIcon: Icon(Icons.location_on),
                        ),
                        items: locations.map((location) {
                          return DropdownMenuItem<String>(
                            value: location,
                            child: Text(location),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedLocation = value ?? '';
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a location';
                          }
                          return null;
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Device Name',
                        hintText: 'e.g., Office AP 1',
                        prefixIcon: Icon(Icons.devices),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        prefixIcon: Icon(Icons.note_alt_outlined),
                      ),
                      maxLines: 3,
                      maxLength: 255,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      setDialogState(() => isSubmitting = true);

                      try {
                        final normalizedMac = _normalizeMacAddress(macController.text.trim());
                        final result = await ApiService.registerUnifiAP(
                          macAddress: normalizedMac,
                          location: selectedLocation,
                          deviceName: nameController.text.trim(),
                          notes: notesController.text.trim(),
                        );

                        if (result['success'] == true) {
                          if (mounted) {
                            Navigator.pop(context);
                            final action = result['action'] ?? 'saved';
                            _showSuccessSnackbar('UniFi AP $action successfully');
                            _loadAccessPoints();
                          }
                        } else {
                          _showErrorSnackbar(result['error'] ?? 'Failed to save AP');
                        }
                      } catch (e) {
                        _showErrorSnackbar('Error: ${e.toString()}');
                      } finally {
                        if (mounted) {
                          setDialogState(() => isSubmitting = false);
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeMacAddress(String mac) {
    final cleaned = mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (cleaned.length != 12) return mac;
    
    final parts = <String>[];
    for (int i = 0; i < cleaned.length; i += 2) {
      parts.add(cleaned.substring(i, i + 2));
    }
    return parts.join(':');
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String? _validateMacAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'MAC address is required';
    }
    
    final cleaned = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (cleaned.length != 12) {
      return 'Invalid MAC address format';
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryColor, AppTheme.primaryVariant],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add AP'),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UniFi Access Points',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
Text(
                  _isLoading
                      ? 'Loading...'
                      : '${_filteredAccessPoints.length}/${_accessPoints.length} device${_accessPoints.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadAccessPoints,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildFilterSection(),
        Expanded(
          child: _buildAPList(),
        ),
      ],
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or MAC...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Obx(() {
                  final locations = _locationController.locations;
                  return DropdownButtonFormField<String?>(
                    value: _filterLocation,
                    decoration: InputDecoration(
                      labelText: 'Filter by Location',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Locations'),
                      ),
                      ...locations.map((location) {
                        return DropdownMenuItem<String?>(
                          value: location,
                          child: Text(location),
                        );
                      }),
                    ],
                    onChanged: _onLocationFilterChanged,
                  );
                }),
              ),
              if (_filterLocation != null || _searchQuery.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear filters',
                  onPressed: _clearFilters,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.errorColor.withOpacity(0.1),
                    foregroundColor: AppTheme.errorColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAPList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_accessPoints.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.router_outlined,
              size: 80,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Access Points',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add your first AP',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredAccessPoints.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No matching results',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAccessPoints,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredAccessPoints.length,
        itemBuilder: (context, index) {
          final ap = _filteredAccessPoints[index];
          return _buildAPCard(ap);
        },
      ),
    );
  }

  Widget _buildAPCard(Map<String, dynamic> ap) {
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.router,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ap['ap_name']?.toString().isEmpty == true
                          ? 'Unnamed AP'
                          : ap['ap_name'] ?? 'Unnamed AP',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.fingerprint,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ap['ap_mac'] ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
                onPressed: () => _showAddEditDialog(ap: ap),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 16,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                ap['location'] ?? 'No location',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (ap['notes'] != null && ap['notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.note_outlined,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ap['notes'] ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (ap['updated_at'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.update,
                  size: 14,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Updated: ${ap['updated_at']}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
