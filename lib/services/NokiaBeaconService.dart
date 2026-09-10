import 'package:cloud_firestore/cloud_firestore.dart';

class NokiaBeaconService {
  static final _db = FirebaseFirestore.instance;
  static const String col = 'nokia_beacons';

  static Future<String> add({
    required String name,
    required String macAddress,
    required String location,
    required String mikrotikId,
    String notes = '',
    String ssid = '',
    String channel2ghz = '',
    String channel5ghz = '',
    String connectionSpeed = '',
    String connectedTo = '',
    String mikrotikInterface = '',
  }) async {
    final doc = await _db.collection(col).add({
      'name': name,
      'mac_address': macAddress.toUpperCase().trim(),
      'location': location,
      'mikrotik_id': mikrotikId,
      'notes': notes,
      'ssid': ssid,
      'channel_2ghz': channel2ghz,
      'channel_5ghz': channel5ghz,
      'connection_speed': connectionSpeed,
      'connected_to': connectedTo,
      'mikrotik_interface': mikrotikInterface,
      'status': 'unknown',
      'last_seen': null,
      'last_checked': null,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> update(String id, {
    String? name,
    String? macAddress,
    String? location,
    String? mikrotikId,
    String? notes,
    String? ssid,
    String? channel2ghz,
    String? channel5ghz,
    String? connectionSpeed,
    String? connectedTo,
    String? mikrotikInterface,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (macAddress != null) data['mac_address'] = macAddress.toUpperCase().trim();
    if (location != null) data['location'] = location;
    if (mikrotikId != null) data['mikrotik_id'] = mikrotikId;
    if (notes != null) data['notes'] = notes;
    if (ssid != null) data['ssid'] = ssid;
    if (channel2ghz != null) data['channel_2ghz'] = channel2ghz;
    if (channel5ghz != null) data['channel_5ghz'] = channel5ghz;
    if (connectionSpeed != null) data['connection_speed'] = connectionSpeed;
    if (connectedTo != null) data['connected_to'] = connectedTo;
    if (mikrotikInterface != null) data['mikrotik_interface'] = mikrotikInterface;
    await _db.collection(col).doc(id).update(data);
  }

  static Future<void> delete(String id) async {
    await _db.collection(col).doc(id).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamAll() {
    return _db.collection(col).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamByMikrotik(String mikrotikId) {
    return _db.collection(col).where('mikrotik_id', isEqualTo: mikrotikId).snapshots();
  }
}
