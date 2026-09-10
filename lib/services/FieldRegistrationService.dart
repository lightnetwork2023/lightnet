import 'package:cloud_firestore/cloud_firestore.dart';

class FieldRegistrationService {
  static final _db = FirebaseFirestore.instance;
  static const String col = 'field_registrations';

  static Future<String> add(Map<String, dynamic> data) async {
    final doc = await _db.collection(col).add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> update(String id, Map<String, dynamic> data) async {
    await _db.collection(col).doc(id).update({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> delete(String id) async {
    await _db.collection(col).doc(id).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamForOwner(String ownerId) {
    return _db
        .collection(col)
        .where('owner_id', isEqualTo: ownerId)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamAll() {
    return _db
        .collection(col)
        .snapshots();
  }

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final snap = await _db.collection(col).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }
}
