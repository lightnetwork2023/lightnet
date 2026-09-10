import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../controllers/ApiService.dart';
import '../controllers/location_controller.dart';
import '../utils/voucher_pdf_grid.dart';
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
  final Map<String, Map<String, dynamic>> _soldVouchers = {};
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
        _soldVouchers.clear();
      });
      _loadLocationData(location);
      _loadSoldVouchers(location);
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

  Future<void> _shareLocationPdf() async {
    if (_selectedLocation == null || _locationData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }
    try {
      final bytes = await VoucherPdfGrid.build(
        _locationData,
        location: _selectedLocation!,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/vouchers-${_selectedLocation!.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Vouchers for ${_selectedLocation!}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export PDF: $e')),
        );
      }
    }
  }

  Future<void> _loadSoldVouchers(String location) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sold_vouchers')
          .where('location', isEqualTo: location)
          .get();
      if (mounted) {
        setState(() {
          _soldVouchers.clear();
          for (final doc in snap.docs) {
            _soldVouchers[doc.id] = doc.data();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleSold(String username) async {
    final ref = FirebaseFirestore.instance.collection('sold_vouchers').doc(username);
    if (_soldVouchers.containsKey(username)) {
      await ref.delete();
      if (mounted) setState(() => _soldVouchers.remove(username));
    } else {
      final data = {
        'username': username,
        'location': _selectedLocation ?? '',
        'sold_at': FieldValue.serverTimestamp(),
      };
      await ref.set(data);
      if (mounted) setState(() => _soldVouchers[username] = data);
    }
  }

  void _showQrCode(String username) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('WiFi Voucher QR', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: QrImageView(data: username, version: QrVersions.auto, size: 180),
            ),
            const SizedBox(height: 14),
            Text(username,
                style: const TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 4),
            const Text('Customer scans or types this code',
                style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF6C5CE7))),
          ),
        ],
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
        actions: [
          if (_selectedLocation != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
              tooltip: 'Export PDF',
              onPressed: _isLoadingData || _locationData.isEmpty ? null : _shareLocationPdf,
            ),
          const SizedBox(width: 8),
        ],
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
                                final username = (user['username'] ?? '') as String;
                                final isSold = _soldVouchers.containsKey(username);
                                return GestureDetector(
                                  onLongPress: () => _toggleSold(username),
                                  child: Stack(
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 16),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: isSold
                                                ? [const Color(0xFF2D1800), const Color(0xFF3D2800)]
                                                : [const Color(0xFF1A1F3A), const Color(0xFF2D3748)],
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSold
                                                ? Colors.orange.withOpacity(0.6)
                                                : const Color(0xFF6C5CE7).withOpacity(0.3),
                                            width: isSold ? 1.5 : 1,
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
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(
                                                      color: isSold
                                                          ? Colors.orange.withOpacity(0.2)
                                                          : const Color(0xFF6C5CE7),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Icon(
                                                      isSold ? Icons.sell_rounded : Icons.person,
                                                      color: isSold ? Colors.orange : Colors.white,
                                                      size: 20,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text('Username',
                                                            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
                                                        const SizedBox(height: 4),
                                                        Text(username,
                                                            style: TextStyle(
                                                              color: isSold ? Colors.orange.shade300 : Colors.white,
                                                              fontSize: 18,
                                                              fontWeight: FontWeight.w700,
                                                            )),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    margin: const EdgeInsets.only(right: 8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.teal.withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: IconButton(
                                                      onPressed: () => _showQrCode(username),
                                                      icon: const Icon(Icons.qr_code_rounded, color: Colors.teal, size: 20),
                                                      tooltip: 'Show QR Code',
                                                    ),
                                                  ),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF6C5CE7).withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: IconButton(
                                                      onPressed: () => _copyUsername(username),
                                                      icon: const Icon(Icons.copy, color: Color(0xFF6C5CE7), size: 20),
                                                      tooltip: 'Copy username',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 20),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      padding: const EdgeInsets.all(16),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF48BB78).withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: const Color(0xFF48BB78).withOpacity(0.3)),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(children: [
                                                            const Icon(Icons.speed, color: Color(0xFF48BB78), size: 18),
                                                            const SizedBox(width: 8),
                                                            const Text('Speed Limit', style: TextStyle(color: Color(0xFF48BB78), fontSize: 12, fontWeight: FontWeight.w600)),
                                                          ]),
                                                          const SizedBox(height: 8),
                                                          Text(user['speed_limit'] ?? 'N/A',
                                                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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
                                                        border: Border.all(color: const Color(0xFFED8936).withOpacity(0.3)),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(children: [
                                                            const Icon(Icons.timer, color: Color(0xFFED8936), size: 18),
                                                            const SizedBox(width: 8),
                                                            const Text('Timeout', style: TextStyle(color: Color(0xFFED8936), fontSize: 12, fontWeight: FontWeight.w600)),
                                                          ]),
                                                          const SizedBox(height: 8),
                                                          Text(_formatDuration(user['session_timeout']),
                                                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (isSold) ...[  
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                                                  ),
                                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                                    Icon(Icons.sell_rounded, color: Colors.orange, size: 14),
                                                    SizedBox(width: 6),
                                                    Text('SOLD — Long press to unmark',
                                                        style: TextStyle(color: Colors.orange, fontSize: 11)),
                                                  ]),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isSold)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                            decoration: const BoxDecoration(
                                              color: Colors.orange,
                                              borderRadius: BorderRadius.only(
                                                topRight: Radius.circular(16),
                                                bottomLeft: Radius.circular(14),
                                              ),
                                            ),
                                            child: const Text('SOLD',
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
                                          ),
                                        ),
                                    ],
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
