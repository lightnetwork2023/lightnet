import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/ApiService.dart';
import '../controllers/location_controller.dart';
import '../widgets/modern_components.dart';

class LocationDataScreen extends StatefulWidget {
  const LocationDataScreen({Key? key}) : super(key: key);

  @override
  _LocationDataScreenState createState() => _LocationDataScreenState();
}

class _LocationDataScreenState extends State<LocationDataScreen> {
  List<dynamic> _locationData = [];
  String? _selectedLocation;
  bool _isLoadingData = false;
  String? _error;
  final LocationController locationController = Get.find();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadLocationData(String location) async {
    try {
      setState(() {
        _isLoadingData = true;
        _error = null;
      });

      final data = await ApiService.fetchLocationData(location);
      setState(() {
        _locationData = data;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load location data: $e';
        _isLoadingData = false;
      });
    }
  }

  void _onLocationSelected(String? location) {
    if (location != null && location != _selectedLocation) {
      setState(() {
        _selectedLocation = location;
        _locationData = [];
      });
      _loadLocationData(location);
    }
  }

  void _copyUsername(String username) {
    Clipboard.setData(ClipboardData(text: username));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Username "$username" copied to clipboard'),
        backgroundColor: const Color(0xFF48BB78),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text(
          'Location Data',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Selection Card
            ModernCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Location',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Obx(() => locationController.locations.isEmpty
                      ? const Text(
                          'No locations available',
                          style: TextStyle(color: Colors.grey),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D3748),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF4A5568)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedLocation,
                              hint: const Text(
                                'Choose a location',
                                style: TextStyle(color: Colors.grey),
                              ),
                              dropdownColor: const Color(0xFF2D3748),
                              style: const TextStyle(color: Colors.white),
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              items: locationController.locations.map<DropdownMenuItem<String>>((location) {
                                return DropdownMenuItem<String>(
                                  value: location,
                                  child: Text(location),
                                );
                              }).toList(),
                              onChanged: _onLocationSelected,
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Error Display
            if (_error != null)
              ModernCard(
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),

            // Location Data Header
            if (_selectedLocation != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Data for $_selectedLocation',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isLoadingData)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_locationData.length} users',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Location Data List
            Expanded(
              child: _selectedLocation == null
                  ? const Center(
                      child: Text(
                        'Select a location to view data',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : _isLoadingData
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
                          ),
                        )
                      : _locationData.isEmpty
                          ? const Center(
                              child: Text(
                                'No data found for this location',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _locationData.length,
                              itemBuilder: (context, index) {
                                final user = _locationData[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF1A1F3A),
                                        Color(0xFF2D3748),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF6C5CE7).withOpacity(0.3),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Username Header
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6C5CE7),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Username',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    user['username'] ?? 'N/A',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6C5CE7).withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                onPressed: () => _copyUsername(user['username'] ?? ''),
                                                icon: const Icon(
                                                  Icons.copy,
                                                  color: Color(0xFF6C5CE7),
                                                  size: 20,
                                                ),
                                                tooltip: 'Copy username',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        
                                        // Speed Limit and Session Timeout
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF48BB78).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: const Color(0xFF48BB78).withOpacity(0.3),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.speed,
                                                          color: const Color(0xFF48BB78),
                                                          size: 18,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        const Text(
                                                          'Speed Limit',
                                                          style: TextStyle(
                                                            color: Color(0xFF48BB78),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      user['speed_limit'] ?? 'N/A',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFED8936).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: const Color(0xFFED8936).withOpacity(0.3),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.timer,
                                                          color: const Color(0xFFED8936),
                                                          size: 18,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        const Text(
                                                          'Timeout',
                                                          style: TextStyle(
                                                            color: Color(0xFFED8936),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      _formatDuration(user['session_timeout']),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF6C5CE7), size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatDuration(dynamic seconds) {
    if (seconds == null) return 'N/A';
    
    try {
      final int totalSeconds = int.parse(seconds.toString());
      final int days = totalSeconds ~/ 86400;
      final int hours = (totalSeconds % 86400) ~/ 3600;
      final int minutes = (totalSeconds % 3600) ~/ 60;
      
      if (days > 0) {
        return '${days}d ${hours}h';
      } else if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else {
        return '${minutes}m';
      }
    } catch (e) {
      return seconds.toString();
    }
  }
}
