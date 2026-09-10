import 'package:cloud_firestore/cloud_firestore.dart';

class SiteService {
  static final _db = FirebaseFirestore.instance;
  static const String col = 'sites';

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

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamAll() {
    return _db
        .collection(col)
        .orderBy('created_at', descending: false)
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamSite(String id) {
    return _db.collection(col).doc(id).snapshots();
  }
}
