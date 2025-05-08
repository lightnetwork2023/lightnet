import 'dart:convert';
import 'package:http/http.dart' as http;

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
  static const String baseUrl = 'http://lightnet.lightnetwork.pro:5000';
  
  // Cache storage
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

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
}
