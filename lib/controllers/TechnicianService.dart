import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ApiService.dart';

class TechnicianService {
  // Reuse ApiService base URL
  static const String _baseUrl = ApiService.baseUrl;

  /// Fetch technician payments summary that INCLUDES test payments (phone '12345678').
  /// Accepts either a single location or a comma-separated list of locations.
  static Future<Map<String, dynamic>> fetchTechnicianPaymentsSummary({
    String? location,
    List<String>? locations,
  }) async {
    String url = '$_baseUrl/fetch_technician_payments_summary';

    if (locations != null && locations.isNotEmpty) {
      final locationsStr = locations.join(',');
      url += '?locations=${Uri.encodeComponent(locationsStr)}';
    } else if (location != null && location.isNotEmpty) {
      url += '?location=${Uri.encodeComponent(location)}';
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch technician payment summary: ${response.body}');
    }
    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception('Technician payment summary error: ${data['error'] ?? 'Unknown error'}');
    }
    // Return the whole payload to keep "summary" and meta fields
    return data as Map<String, dynamic>;
  }
}
