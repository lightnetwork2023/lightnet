import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

// Cache entry class to store data with timestamp
class _CacheEntry {
  final dynamic data;
  final DateTime timestamp;

  _CacheEntry(this.data, this.timestamp);

  bool isValid(Duration cacheDuration) {
    return DateTime.now().difference(timestamp) < cacheDuration;
  }
}

class ApiService {
  static const String baseUrl = 'http://167.179.100.104:5000';
  
  // Cache storage
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 2);

  // Helper method to get cached data
  static T? _getCachedData<T>(String key) {
    final entry = _cache[key];
    if (entry != null && entry.isValid(_cacheDuration)) {
      return entry.data as T;
    }
    return null;
  }

  // Helper method to cache data
  static void _cacheData(String key, dynamic data) {
    _cache[key] = _CacheEntry(data, DateTime.now());
  }

  // Clear all cache
  static void clearCache() {
    _cache.clear();
  }

  static Future<Map<String, dynamic>> generateUsers({
    required int numUsers,
    required double numDays,
    required String location,
    String? speedLimit,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate_users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'num_users': numUsers,
        'num_days': numDays,
        'location': location,
        'speed_limit': speedLimit,
      }),
    );
    final result = jsonDecode(response.body);
    // Clear cache after generating new users
    clearCache();
    return result;
  }

  static Future<List<dynamic>> fetchPayments() async {
    const cacheKey = 'payments';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    final response = await http.get(Uri.parse('$baseUrl/payments'));
    final payments = jsonDecode(response.body)['payments'];
    _cacheData(cacheKey, payments);
    return payments;
  }

  static Future<Map<String, dynamic>> deleteUser(String username) async {
    final response = await http.post(
      Uri.parse('$baseUrl/delete_user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username}),
    );
    final result = jsonDecode(response.body);
    // Clear cache after deleting a user
    clearCache();
    return result;
  }

  static Future<Map<String, dynamic>> getUserInfo(String username) async {
    final cacheKey = 'user_info_$username';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    final response = await http.get(Uri.parse('$baseUrl/get_user_info?username=$username'));
    final result = jsonDecode(response.body);
    _cacheData(cacheKey, result);
    return result;
  }

  static Future<List<dynamic>> fetchActiveSessions() async {
    const cacheKey = 'active_sessions';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    final response = await http.get(Uri.parse('$baseUrl/active_sessions'));
    final sessions = jsonDecode(response.body)['active_sessions'];
    _cacheData(cacheKey, sessions);
    return sessions;
  }

  static Future<List<dynamic>> fetchValidUsers(String location) async {
    final cacheKey = 'valid_users_$location';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    final response = await http.get(Uri.parse('$baseUrl/valid_users?location=$location'));
    final users = jsonDecode(response.body)['users'];
    _cacheData(cacheKey, users);
    return users;
  }

  static Future<List<dynamic>> fetchVouchers() async {
    const cacheKey = 'vouchers';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/vouchers'));
      if (response.statusCode == 404) {
        return [];
      }
      final vouchers = jsonDecode(response.body)['vouchers'];
      _cacheData(cacheKey, vouchers);
      return vouchers;
    } catch (e) {
      throw Exception('Failed to fetch vouchers: $e');
    }
  }

  // Fetch and cache all valid users for all locations
  static Future<void> fetchAllValidUsers(List<String> locations) async {
    for (final location in locations) {
      try {
        await fetchValidUsers(location); // This will cache the result
      } catch (e) {
        // Optionally log or handle error per location
      }
    }
  }

  static Future<List<dynamic>> fetchRecentVouchers() async {
    const cacheKey = 'recent_vouchers';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_recent_vouchers'));
      if (response.statusCode == 404) {
        return [];
      }
      final data = jsonDecode(response.body);
      final vouchers = data['vouchers'];
      _cacheData(cacheKey, vouchers);
      return vouchers;
    } catch (e) {
      throw Exception('Failed to fetch recent vouchers: $e');
    }
  }

  static Future<List<dynamic>> fetchRecentPayments() async {
    const cacheKey = 'recent_payments';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_recent_payments'));
      if (response.statusCode == 404) {
        return [];
      }
      final data = jsonDecode(response.body);
      final payments = data['payments'];
      _cacheData(cacheKey, payments);
      return payments;
    } catch (e) {
      throw Exception('Failed to fetch recent payments: $e');
    }
  }

  static Future<List<dynamic>> fetchVouchersToday() async {
    const cacheKey = 'vouchers_today';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_vouchers_today'));
      if (response.statusCode == 404) {
        return [];
      }
      final data = jsonDecode(response.body);
      final vouchers = data['vouchers'];
      _cacheData(cacheKey, vouchers);
      return vouchers;
    } catch (e) {
      throw Exception('Failed to fetch today\'s vouchers: $e');
    }
  }

  static Future<List<dynamic>> fetchPaymentsToday() async {
    const cacheKey = 'payments_today';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_payments_today'));
      if (response.statusCode == 404) {
        return [];
      }
      final data = jsonDecode(response.body);
      final payments = data['payments'];
      _cacheData(cacheKey, payments);
      return payments;
    } catch (e) {
      throw Exception('Failed to fetch today\'s payments: $e');
    }
  }

  static Future<List<dynamic>> fetchNetworkDevices() async {
    const cacheKey = 'network_devices';
    try {
      // Check cache first
      final cachedData = _getCachedData<List<dynamic>>(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }

      final devicesSnapshot = await FirebaseFirestore.instance
          .collection('networks')
          .get();

      if (devicesSnapshot.docs.isEmpty) {
        return [];
      }

      final devices = devicesSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Include document ID in the data
        return data;
      }).toList();

      _cacheData(cacheKey, devices);
      return devices;
    } catch (e) {
      throw Exception('Error fetching network devices: $e');
    }
  }

  static Future<Map<String, dynamic>> addNetworkDevice({
    required String name,
    required String location,
    required String macId,
  }) async {
    try {
      // Check if device with same MAC ID already exists
      final existingDevice = await FirebaseFirestore.instance
          .collection('networks')
          .where('mac_id', isEqualTo: macId)
          .get();

      if (existingDevice.docs.isNotEmpty) {
        throw Exception('Device with MAC ID $macId already exists');
      }

      // Create new device document
      final docRef = await FirebaseFirestore.instance
          .collection('networks')
          .add({
        'name': name,
        'location': location,
        'mac_id': macId,
        'created_at': FieldValue.serverTimestamp(),
        'status': 'active'
      });

      return {
        'success': true,
        'device_id': docRef.id,
        'message': 'Device added successfully'
      };
    } catch (e) {
      throw Exception('Error adding network device: $e');
    }
  }

  static Future<Map<String, dynamic>> deleteNetworkDevice(String macId) async {
    try {
      // Find the device document with the given MAC ID
      final deviceQuery = await FirebaseFirestore.instance
          .collection('networks')
          .where('mac_id', isEqualTo: macId)
          .get();

      if (deviceQuery.docs.isEmpty) {
        throw Exception('Device with MAC ID $macId not found');
      }

      // Delete the device document
      await FirebaseFirestore.instance
          .collection('networks')
          .doc(deviceQuery.docs.first.id)
          .delete();

      // Clear the devices cache to force a refresh
      clearCache();

      return {
        'success': true,
        'message': 'Device deleted successfully'
      };
    } catch (e) {
      throw Exception('Error deleting network device: $e');
    }
  }
}
