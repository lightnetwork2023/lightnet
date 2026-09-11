import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
// New Data Model for Payment Analytics

class ApiService {
  static const String baseUrl = 'https://lightnet.lightnetwork.pro';

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

  // Clear a specific cache key
  static void clearCacheKey(String key) {
    _cache.remove(key);
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
    return fetchActiveMacs();
  }

  static Future<Map<String, dynamic>> fetchDashboardStats() async {
    const cacheKey = 'dashboard_stats';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    final response = await http.get(Uri.parse('$baseUrl/dashboard_stats'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'dashboard_stats failed');
    }
    _cacheData(cacheKey, data);
    return data;
  }

  static Future<List<dynamic>> fetchVoucherLocationCounts() async {
    const cacheKey = 'vouchers_by_location';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    final response = await http.get(Uri.parse('$baseUrl/vouchers_by_location'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'vouchers_by_location failed');
    }
    final rows = (data['locations'] as List?) ?? [];
    _cacheData(cacheKey, rows);
    return rows;
  }

  static Future<List<dynamic>> fetchValidUsers(String location) async {
    final cacheKey = 'valid_users_$location';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    final response = await http.get(Uri.parse('$baseUrl/valid_users?location=$location'));
    final users = (jsonDecode(response.body)['users'] as List?) ?? [];
    _cacheData(cacheKey, users);
    return users;
  }

  static Future<List<dynamic>> fetchVouchers({String? location, int limit = 200}) async {
    final cacheKey = 'vouchers_${location ?? 'all'}_$limit';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final uri = Uri.parse('$baseUrl/vouchers').replace(queryParameters: {
        'limit': '$limit',
        if (location != null && location.isNotEmpty) 'location': location,
      });
      final response = await http.get(uri);
      if (response.statusCode == 404) {
        return [];
      }
      final vouchers = jsonDecode(response.body)['vouchers'] ?? [];
      _cacheData(cacheKey, vouchers);
      return vouchers;
    } catch (e) {
      throw Exception('Failed to fetch vouchers: $e');
    }
  }
  /// Fetches combined payment analytics summary from backend (for boss - all locations)
  static Future<Map<String, dynamic>> fetchPaymentsSummary() async {
    const cacheKey = 'payments_summary';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    
    final response = await http.get(Uri.parse('$baseUrl/fetch_payments_summary'));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch payment summary: ${response.body}');
    }
    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception('Payment summary error: ${data['error'] ?? 'Unknown error'}');
    }
    final summary = data['summary'] as Map<String, dynamic>;
    _cacheData(cacheKey, summary);
    return summary;
  }

  /// Fetches location-based payment analytics summary for agents/superagents
  static Future<Map<String, dynamic>> fetchAgentPaymentsSummary({String? location, List<String>? locations}) async {
    String cacheKey;
    String url = '$baseUrl/fetch_agent_payments_summary';
    
    if (locations != null && locations.isNotEmpty) {
      // For superagents with multiple locations
      final locationsStr = locations.join(',');
      cacheKey = 'agent_payments_summary_multi_${locationsStr.hashCode}';
      url += '?locations=${Uri.encodeComponent(locationsStr)}';
    } else if (location != null && location.isNotEmpty) {
      // For agents with single location
      cacheKey = 'agent_payments_summary_$location';
      url += '?location=${Uri.encodeComponent(location)}';
    } else {
      // Fallback to global summary
      cacheKey = 'agent_payments_summary';
    }
    
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch agent payment summary: ${response.body}');
    }
    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception('Agent payment summary error: ${data['error'] ?? 'Unknown error'}');
    }
    final summary = data['summary'] as Map<String, dynamic>;
    _cacheData(cacheKey, summary);
    return summary;
  }

  static Future<List<dynamic>> fetchVouchersByName() async {
    const cacheKey = 'vouchers_by_name';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    final response = await http.get(Uri.parse('$baseUrl/get_vouchers_by_name'));
    if (response.statusCode == 404) {
      return [];
    }
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic> && data.containsKey('vouchers')) {
      final vouchers = data['vouchers'] as List;
      _cacheData(cacheKey, vouchers);
      return vouchers;
    }
    throw Exception('Unexpected response from server');
  }

  // Fetch and cache all valid users for all locations
  static Future<void> fetchAllValidUsers(List<String> locations) async {
    // Make all requests in parallel instead of sequential
    final futures = locations.map((location) async {
      try {
        await fetchValidUsers(location); // This will cache the result
      } catch (e) {
        debugPrint('Error fetching users for $location: $e');
      }
    });
    
    // Wait for all requests to complete
    await Future.wait(futures);
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

  static Future<List<dynamic>> searchPayments(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) {
      return [];
    }
    try {
      final response = await http.get(Uri.parse('$baseUrl/search_payments?phone=${Uri.encodeComponent(phone)}'));
      if (response.statusCode == 404 || response.statusCode == 400) {
        return [];
      }
      final data = jsonDecode(response.body);
      return (data['payments'] as List?) ?? [];
    } catch (e) {
      throw Exception('Failed to search payments: $e');
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

  /// Fetches the total payment amount for today.
  static Future<double> fetchTotalPaymentsToday() async {
    const cacheKey = 'total_payments_today';
    final cachedData = _getCachedData<double>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_payments_today'));
      if (response.statusCode != 200) {
        throw Exception('Failed to load today\'s total payments: ${response.body}');
      }
      final data = json.decode(response.body);
      final totalAmount = (data['total_amount'] as num).toDouble();
      _cacheData(cacheKey, totalAmount);
      return totalAmount;
    } catch (e) {
      print('Error fetching total payments today: $e');
      rethrow;
    }
  }

  /// Fetches the total payment amount for the current month.
  static Future<double> fetchTotalPaymentsThisMonth() async {
    const cacheKey = 'total_payments_this_month';
    final cachedData = _getCachedData<double>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_payments_this_month'));
      if (response.statusCode != 200) {
        throw Exception('Failed to load this month\'s total payments: ${response.body}');
      }
      final data = json.decode(response.body);
      final totalAmount = (data['total_amount'] as num).toDouble();
      _cacheData(cacheKey, totalAmount);
      return totalAmount;
    } catch (e) {
      print('Error fetching total payments this month: $e');
      rethrow;
    }
  }

  /// Fetches the total payment amount for the last month.
  static Future<double> fetchTotalPaymentsLastMonth() async {
    const cacheKey = 'total_payments_last_month';
    final cachedData = _getCachedData<double>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/fetch_payments_last_month'));
      if (response.statusCode != 200) {
        throw Exception('Failed to load last month\'s total payments: ${response.body}');
      }
      final data = json.decode(response.body);
      final totalAmount = (data['total_amount'] as num).toDouble();
      _cacheData(cacheKey, totalAmount);
      return totalAmount;
    } catch (e) {
      print('Error fetching total payments last month: $e');
      rethrow;
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

  /// Fetches all unique locations from the location table
  static Future<List<dynamic>> fetchAllLocations() async {
    const cacheKey = 'all_locations';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/locations'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final locations = data['locations'] as List<dynamic>;
        _cacheData(cacheKey, locations);
        return locations;
      } else {
        throw Exception('Failed to fetch locations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching locations: $e');
    }
  }

  /// Fetches location-specific data from the location table
  static Future<List<dynamic>> fetchLocationData(String location) async {
    final cacheKey = 'location_data_$location';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/location_data?location=${Uri.encodeComponent(location)}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final locationData = data['data'] as List<dynamic>;
        _cacheData(cacheKey, locationData);
        return locationData;
      } else {
        throw Exception('Failed to fetch location data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching location data: $e');
    }
  }

  static Future<List<dynamic>> fetchOnlineMacs() async {
    const cacheKey = 'online_macs';
    try {
      // Check cache first
      final cachedData = _getCachedData<List<dynamic>>(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }

      final response = await http.get(Uri.parse('$baseUrl/get-all-macs'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _cacheData(cacheKey, data);
        return data;
      } else {
        throw Exception('Failed to fetch online MACs: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching online MACs: $e');
    }
  }

  static Future<List<dynamic>> fetchActiveMacs() async {
    const cacheKey = 'active_macs';
    final cachedData = _getCachedData<List<dynamic>>(cacheKey);
    if (cachedData != null) return cachedData;

    final response = await http.get(Uri.parse('$baseUrl/get-all-macs-active'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      _cacheData(cacheKey, data);
      return data;
    } else {
      throw Exception('Failed to fetch active MACs: \\${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> makePayment({
    required String provider,
    required String phone,
    required int amount,
    required int quantity,
    required double durationSeconds,
    required String location,
    int? days,
  }) async {
    try {
      print('🔄 Starting payment request...');
      print('📍 URL: https://processpayment-3vxbatgzgq-uc.a.run.app');
      print('📱 Provider: $provider, Phone: $phone, Amount: $amount');
      print('📍 Location: $location, Quantity: $quantity, Duration: $durationSeconds');
      
      final requestBody = {
        'provider': provider,
        'phone': phone,
        'amount': amount,
        'quantity': quantity,
        'durationSeconds': durationSeconds,
        'location': location,
        if (days != null) 'days': days,
      };
      
      print('📤 Request body: ${jsonEncode(requestBody)}');
      
      // Preflight: DNS check for visibility
      try {
        final lookup = await InternetAddress.lookup('processpayment-3vxbatgzgq-uc.a.run.app', type: InternetAddressType.any);
        print('🔎 DNS lookup results: ${lookup.map((a) => '${a.address}/${a.type}').join(', ')}');
      } catch (e) {
        print('⚠️ DNS lookup failed but proceeding to request: $e');
      }

      // Single robust attempt with extended timeout
      final uri = Uri.parse('https://processpayment-3vxbatgzgq-uc.a.run.app');
      http.Response response;
      try {
        response = await http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'LightNet-Flutter/1.0',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 45));
      } on TimeoutException {
        // Retry once immediately on timeout (cold start / transient)
        print('⏳ First attempt timed out, retrying once...');
        response = await http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'LightNet-Flutter/1.0',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 45));
      }
      
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response headers: ${response.headers}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('✅ Payment request successful: $result');
        return result;
      } else {
        print('❌ Payment request failed with status: ${response.statusCode}');
        print('❌ Error response: ${response.body}');
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
          'status_code': response.statusCode,
        };
      }
    } on SocketException catch (e) {
      print('🌐 Network/Socket error during payment: $e');
      print('🌐 Error type: ${e.runtimeType}');
      print('🌐 OS Error: ${e.osError}');
      return {
        'success': false,
        'error': 'Network connection failed: ${e.message}',
        'error_type': 'SocketException',
        'details': e.toString(),
      };
    } on HttpException catch (e) {
      print('🌐 HTTP error during payment: $e');
      return {
        'success': false,
        'error': 'HTTP error: ${e.message}',
        'error_type': 'HttpException',
        'details': e.toString(),
      };
    } on FormatException catch (e) {
      print('📝 JSON parsing error during payment: $e');
      return {
        'success': false,
        'error': 'Invalid response format: ${e.message}',
        'error_type': 'FormatException',
        'details': e.toString(),
      };
    } on TimeoutException catch (e) {
      print('⏰ Timeout error during payment: $e');
      return {
        'success': false,
        'error': 'Request timed out: ${e.message}',
        'error_type': 'TimeoutException',
        'details': e.toString(),
      };
    } catch (e) {
      print('❌ Unexpected error during payment: $e');
      print('❌ Error type: ${e.runtimeType}');
      return {
        'success': false,
        'error': 'Unexpected error: $e',
        'error_type': e.runtimeType.toString(),
        'details': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> insertVoucher({
    required String macAddress,
    String? name,
    DateTime? expireTime,
  }) async {
    final Map<String, dynamic> body = {
      'mac_address': macAddress,
      if (name != null) 'name': name,
      if (expireTime != null) 'expire_time': expireTime.toIso8601String(),
    };
  
    final response = await http.post(
      Uri.parse('$baseUrl/insert_voucher'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteVoucherByMac(String macAddress) async {
    final response = await http.post(
      Uri.parse('$baseUrl/delete_voucher_by_mac'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mac_address': macAddress}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteVoucherByUsername(String username) async {
    final response = await http.post(
      Uri.parse('$baseUrl/delete_voucher_by_username'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateVoucher({
    required String username,
    String? newMacAddress,
    String? name,
    DateTime? expireTime,
  }) async {
    final Map<String, dynamic> body = {
      'username': username,
      if (newMacAddress != null) 'new_mac_address': newMacAddress,
      if (name != null) 'name': name,
      if (expireTime != null) 'expire_time': expireTime.toIso8601String(),
    };
    final response = await http.post(
      Uri.parse('$baseUrl/update_voucher'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateVoucherByMac({
    required String macAddress,
    String? name,
    DateTime? expireTime,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/update_voucher_by_mac'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mac_address': macAddress,
        'name': name ?? 'DefaultName',
        if (expireTime != null) 'expire_time': expireTime.toIso8601String(),
      }),
    );
    return jsonDecode(response.body);
  }

  /// Update voucher settings (speed_limit and/or expire_time)
  /// Can identify by username or mac_address
  static Future<Map<String, dynamic>> updateVoucherSettings({
    String? username,
    String? macAddress,
    String? speedLimit,
    DateTime? expireTime,
  }) async {
    if (username == null && macAddress == null) {
      throw ArgumentError('Either username or macAddress must be provided');
    }
    if (speedLimit == null && expireTime == null) {
      throw ArgumentError('At least one of speedLimit or expireTime must be provided');
    }

    final Map<String, dynamic> body = {
      if (username != null) 'username': username,
      if (macAddress != null) 'mac_address': macAddress,
      if (speedLimit != null) 'speed_limit': speedLimit,
      if (expireTime != null) 'expire_time': expireTime.toIso8601String(),
    };

    final response = await http.post(
      Uri.parse('$baseUrl/update_voucher_settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      clearCache(); // Clear cache after update
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update voucher settings: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> fetchSuperAgentPayments(List<String> locations) async {
    final cacheKey = 'sa_payments_${locations.join(',').hashCode}';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    final locationsParam = locations.map((loc) => 'locations=${Uri.encodeComponent(loc)}').join('&');
    final response = await http.get(
      Uri.parse('$baseUrl/fetch_superagent_payments?$locationsParam'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      _cacheData(cacheKey, data);
      return data;
    } else {
      throw Exception('Failed to fetch superagent payments: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> fetchSuperAgentRecentVouchers({
    required String locations,
    String? searchTerm,
  }) async {
    final cacheKey = 'sa_vouchers_${locations.hashCode}_${searchTerm ?? ''}';
    if (searchTerm == null || searchTerm.isEmpty) {
      final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
      if (cachedData != null) {
        return cachedData;
      }
    }
    final uri = Uri.parse('$baseUrl/fetch_superagent_recent_vouchers').replace(
      queryParameters: {
        'locations': locations,
        if (searchTerm != null && searchTerm.isNotEmpty) 'search': searchTerm,
      },
    );

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (searchTerm == null || searchTerm.isEmpty) {
        _cacheData(cacheKey, data);
      }
      return data;
    } else {
      throw Exception('Failed to fetch superagent recent vouchers: ${response.statusCode}');
    }
  }

  // Fetch counts of payments grouped by location for a given period (today or last24h)
  static Future<Map<String, dynamic>> fetchPaymentsByLocation({
    List<String>? locations,
    String period = 'last24h',
  }) async {
    final locStr = (locations != null && locations.isNotEmpty) ? locations.join(',') : '';
    final cacheKey = 'payments_by_location_${period}_${locStr.hashCode}';
    final cachedData = _getCachedData<Map<String, dynamic>>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }

    final uri = Uri.parse('$baseUrl/fetch_payments_by_location').replace(
      queryParameters: {
        'period': period,
        if (locStr.isNotEmpty) 'locations': locStr,
      },
    );

    final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch payments by location: ${response.body}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception('Payments by location error: ${data['error'] ?? 'Unknown error'}');
    }
    _cacheData(cacheKey, data);
    return data;
  }

  // Get all UniFi Access Points
  static Future<List<dynamic>> getUnifiAPs({String? location}) async {
    final uri = location != null && location.isNotEmpty
        ? Uri.parse('$baseUrl/get_unifi_aps?location=$location')
        : Uri.parse('$baseUrl/get_unifi_aps');

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    final result = jsonDecode(response.body);
    
    if (response.statusCode == 200 && result['success'] == true) {
      return result['access_points'] ?? [];
    } else {
      throw Exception(result['error'] ?? 'Failed to fetch UniFi APs');
    }
  }

  // Register or update UniFi Access Point
  static Future<Map<String, dynamic>> registerUnifiAP({
    required String macAddress,
    required String location,
    String? deviceName,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register_unifi_ap'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mac_address': macAddress,
        'location': location,
        'device_name': deviceName ?? '',
        'notes': notes ?? '',
      }),
    );

    final result = jsonDecode(response.body);
    
    if (response.statusCode == 200 && result['success'] == true) {
      return result;
    } else {
      throw Exception(result['error'] ?? 'Failed to register UniFi AP');
    }
  }

}
