import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:lightnetwork/services/app_db.dart';

class MikroTikMonitorService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'mikrotik_devices';

  static Future<void> addMikroTikDevice({
    required String name,
    required String ipAddress,
    required String location,
    String? vpnInterface,
    String? description,
    String? username,
    String? password,
    String? wanInterface,
  }) async {
    await _firestore.collection(_collection).add({
      'name': name,
      'ipAddress': ipAddress,
      'location': location,
      'vpnInterface': vpnInterface ?? 'wireguard',
      'description': description ?? '',
      'username': username ?? 'admin',
      'password': password ?? '',
      'wanInterface': wanInterface ?? 'ether1',
      'status': 'unknown',
      'lastSeen': null,
      'lastChecked': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateMikroTikDevice({
    required String deviceId,
    String? name,
    String? ipAddress,
    String? location,
    String? vpnInterface,
    String? description,
    String? username,
    String? password,
    String? wanInterface,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) updates['name'] = name;
    if (ipAddress != null) updates['ipAddress'] = ipAddress;
    if (location != null) updates['location'] = location;
    if (vpnInterface != null) updates['vpnInterface'] = vpnInterface;
    if (description != null) updates['description'] = description;
    if (username != null) updates['username'] = username;
    if (password != null) updates['password'] = password;
    if (wanInterface != null) updates['wanInterface'] = wanInterface;

    await _firestore.collection(_collection).doc(deviceId).update(updates);
  }

  static Future<void> updateDeviceStatus({
    required String deviceId,
    required String status,
    DateTime? lastSeen,
  }) async {
    await _firestore.collection(_collection).doc(deviceId).update({
      'status': status,
      'lastSeen': lastSeen,
      'lastChecked': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteMikroTikDevice(String deviceId) async {
    await _firestore.collection(_collection).doc(deviceId).delete();
  }

  /// Read this router's Nokia beacon leases now, instead of waiting for the 5-minute check.
  static Future<Map<String, dynamic>> refreshAccessPoints(String deviceId) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final res = await http.post(
      Uri.parse('https://lightnet.lightnetwork.pro/api/mikrotik/refresh-access-points'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'deviceId': deviceId}),
    );
    final raw = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (res.statusCode >= 400) {
      throw Exception(map['error']?.toString() ?? 'Refresh failed');
    }
    return map;
  }

  /// Name is stored by MAC and is not touched by the DHCP refresh.
  static Future<void> setAccessPointName({
    required String deviceId,
    required String mac,
    required String name,
  }) async {
    final trimmed = name.trim();
    await _firestore.collection(_collection).doc(deviceId).update({
      'access_point_names': {
        mac: trimmed.isEmpty ? FieldValue.delete() : trimmed,
      },
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getMikroTikDevices() {
    return _firestore
        .collection(_collection)
        .orderBy('location')
        .orderBy('name')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getMikroTikDevicesByStatus(String status) {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: status)
        .orderBy('location')
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getMikroTikDevice(String deviceId) {
    return _firestore.collection(_collection).doc(deviceId).snapshots();
  }

  // Stream a specific set of devices by their Firestore document IDs
  static Stream<QuerySnapshot<Map<String, dynamic>>> getMikroTikDevicesByIds(List<String> ids) {
    if (ids.isEmpty) {
      return const Stream.empty();
    }
    return _firestore
        .collection(_collection)
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots();
  }

  static Future<int> getOfflineCount() async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'offline')
        .get();
    return snapshot.docs.length;
  }

  static Future<int> getOnlineCount() async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'online')
        .get();
    return snapshot.docs.length;
  }
}
