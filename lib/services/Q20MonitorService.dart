import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class Q20MonitorService {
  static const String baseUrl = 'https://lightnet.lightnetwork.pro';

  static Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      if (jsonBody) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _decode(http.Response response) async {
    final raw = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (response.statusCode >= 400) {
      throw Exception(map['error']?.toString() ?? 'Request failed (${response.statusCode})');
    }
    return map;
  }

  static Future<Map<String, dynamic>> listRouters() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/app/q20'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> getRouter(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/app/q20/$id'),
      headers: await _headers(),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> renameRouter(int id, String name) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/app/q20/$id'),
      headers: await _headers(jsonBody: true),
      body: jsonEncode({'name': name}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> sendCommand(int id, String type) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/app/q20/$id/command'),
      headers: await _headers(jsonBody: true),
      body: jsonEncode({'type': type}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> meshAction({
    required int id,
    required String action,
    required String mac,
    String? name,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/app/q20/$id/mesh'),
      headers: await _headers(jsonBody: true),
      body: jsonEncode({
        'action': action,
        'mac': mac,
        if (name != null) 'name': name,
      }),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> login(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/app/q20/$id/login'),
      headers: await _headers(),
    );
    return _decode(response);
  }
}
