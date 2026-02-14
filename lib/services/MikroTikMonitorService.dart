import 'package:cloud_firestore/cloud_firestore.dart';

class MikroTikMonitorService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'mikrotik_devices';

  static Future<void> addMikroTikDevice({
    required String name,
    required String ipAddress,
    required String location,
    String? vpnInterface,
    String? description,
  }) async {
    await _firestore.collection(_collection).add({
      'name': name,
      'ipAddress': ipAddress,
      'location': location,
      'vpnInterface': vpnInterface ?? 'wireguard',
      'description': description ?? '',
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
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) updates['name'] = name;
    if (ipAddress != null) updates['ipAddress'] = ipAddress;
    if (location != null) updates['location'] = location;
    if (vpnInterface != null) updates['vpnInterface'] = vpnInterface;
    if (description != null) updates['description'] = description;

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

  static Stream<QuerySnapshot> getMikroTikDevices() {
    return _firestore
        .collection(_collection)
        .orderBy('location')
        .orderBy('name')
        .snapshots();
  }

  static Stream<QuerySnapshot> getMikroTikDevicesByStatus(String status) {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: status)
        .orderBy('location')
        .snapshots();
  }

  static Stream<DocumentSnapshot> getMikroTikDevice(String deviceId) {
    return _firestore.collection(_collection).doc(deviceId).snapshots();
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
