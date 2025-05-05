import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://lightnet.lightnetwork.pro:5000';

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
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> fetchPayments() async {
    final response = await http.get(Uri.parse('$baseUrl/payments'));
    return jsonDecode(response.body)['payments'];
  }

  static Future<Map<String, dynamic>> deleteUser(String username) async {
    final response = await http.post(
      Uri.parse('$baseUrl/delete_user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getUserInfo(String username) async {
    final response = await http.get(Uri.parse('$baseUrl/get_user_info?username=$username'));
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> fetchActiveSessions() async {
    final response = await http.get(Uri.parse('$baseUrl/active_sessions'));
    return jsonDecode(response.body)['active_sessions'];
  }

  static Future<List<dynamic>> fetchValidUsers(String location) async {
    final response = await http.get(Uri.parse('$baseUrl/valid_users?location=$location'));
    return jsonDecode(response.body)['users'];
  }

  static Future<List<dynamic>> fetchVouchers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/vouchers'));
      if (response.statusCode == 404) {
        return [];
      }
      return jsonDecode(response.body)['vouchers'];
    } catch (e) {
      throw Exception('Failed to fetch vouchers: $e');
    }
  }
}
