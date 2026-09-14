import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:lightnetwork/controllers/ApiService.dart';

class Timestamp implements Comparable<Timestamp> {
  final DateTime _date;
  Timestamp._(this._date);
  factory Timestamp.fromDate(DateTime date) => Timestamp._(date);
  factory Timestamp.now() => Timestamp._(DateTime.now());
  DateTime toDate() => _date;
  int get millisecondsSinceEpoch => _date.millisecondsSinceEpoch;
  int get seconds => _date.millisecondsSinceEpoch ~/ 1000;
  @override
  int compareTo(Timestamp other) => _date.compareTo(other._date);
  @override
  String toString() => _date.toIso8601String();
}

enum Source { cache, server, serverAndCache }

class GetOptions {
  final Source source;
  const GetOptions({this.source = Source.serverAndCache});
}

class SetOptions {
  final bool merge;
  const SetOptions({this.merge = false});
}

class Settings {
  final bool persistenceEnabled;
  final int cacheSizeBytes;
  const Settings({this.persistenceEnabled = true, this.cacheSizeBytes = 10485760});
}

class FieldPath {
  final String path;
  const FieldPath(this.path);
  static const FieldPath documentId = FieldPath('__name__');
  @override
  String toString() => path;
}

class FieldValue {
  final String op;
  final num n;
  final DateTime? date;
  const FieldValue._(this.op, {this.n = 0, this.date});
  static FieldValue serverTimestamp() => const FieldValue._('serverTimestamp');
  static FieldValue increment(num value) => FieldValue._('increment', n: value);
  static FieldValue delete() => const FieldValue._('delete');
  Map<String, dynamic> toJson() {
    if (op == 'increment') return {'__fv': 'increment', 'n': n};
    if (op == 'timestamp' && date != null) {
      return {'__fv': 'timestamp', 'iso': date!.toUtc().toIso8601String()};
    }
    return {'__fv': op};
  }
}

class FirebaseFirestore {
  FirebaseFirestore._();
  static final FirebaseFirestore instance = FirebaseFirestore._();
  Settings settings = const Settings();

  CollectionReference<Map<String, dynamic>> collection(String path) =>
      CollectionReference<Map<String, dynamic>>._(path);

  WriteBatch batch() => WriteBatch();
}

class WriteBatch {
  final List<Map<String, dynamic>> _ops = [];

  void set(DocumentReference ref, Map<String, dynamic> data, [SetOptions? options]) {
    _ops.add({
      'op': 'set',
      'collection': ref._collection,
      'id': ref.id,
      'data': _encode(data),
      'merge': options?.merge == true,
    });
  }

  void update(DocumentReference ref, Map<String, dynamic> data) {
    _ops.add({
      'op': 'update',
      'collection': ref._collection,
      'id': ref.id,
      'data': _encode(data),
      'merge': true,
    });
  }

  void delete(DocumentReference ref) {
    _ops.add({'op': 'delete', 'collection': ref._collection, 'id': ref.id});
  }

  Future<void> commit() async {
    if (_ops.isEmpty) return;
    await _AppHttp.batch(_ops);
  }
}

class CollectionReference<T extends Object?> extends Query<T> {
  CollectionReference._(String path) : super._(path, const [], null, null);

  DocumentReference<T> doc([String? id]) =>
      DocumentReference<T>._(path, id ?? _AppHttp.newId());

  Future<DocumentReference<T>> add(Map<String, dynamic> data) async {
    final id = await _AppHttp.create(path, _encode(data));
    return DocumentReference<T>._(path, id);
  }
}

class DocumentReference<T extends Object?> {
  final String _collection;
  final String id;
  DocumentReference._(this._collection, this.id);

  String get path => '$_collection/$id';

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      CollectionReference<Map<String, dynamic>>._('$_collection/$id/$name');

  Future<DocumentSnapshot<T>> get([GetOptions? options]) async {
    final raw = await _AppHttp.getDoc(_collection, id);
    return DocumentSnapshot<T>._(_collection, id, raw);
  }

  Stream<DocumentSnapshot<T>> snapshots({bool includeMetadataChanges = false}) async* {
    yield await get();
    yield* Stream.periodic(const Duration(seconds: 10)).asyncMap((_) => get());
  }

  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    await _AppHttp.set(_collection, id, _encode(data), merge: options?.merge == true);
  }

  Future<void> update(Map<String, dynamic> data) async {
    await _AppHttp.set(_collection, id, _encode(data), merge: true);
  }

  Future<void> delete() => _AppHttp.delete(_collection, id);
}

class Query<T extends Object?> {
  final String path;
  final List<Map<String, dynamic>> _filters;
  final Map<String, dynamic>? _orderBy;
  final int? _limit;
  Query._(this.path, this._filters, this._orderBy, this._limit);

  Query<T> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    List<Object?>? whereIn,
  }) {
    final fieldName = field is FieldPath ? field.path : field.toString();
    final next = List<Map<String, dynamic>>.from(_filters);
    void add(String op, Object? value) {
      if (value != null) next.add({'field': fieldName, 'op': op, 'value': _encode(value)});
    }
    add('==', isEqualTo);
    add('!=', isNotEqualTo);
    add('<', isLessThan);
    add('<=', isLessThanOrEqualTo);
    add('>', isGreaterThan);
    add('>=', isGreaterThanOrEqualTo);
    add('array-contains', arrayContains);
    if (whereIn != null) add('in', whereIn);
    return Query<T>._(path, next, _orderBy, _limit);
  }

  Query<T> orderBy(Object field, {bool descending = false}) {
    final fieldName = field is FieldPath ? field.path : field.toString();
    return Query<T>._(path, _filters, {'field': fieldName, 'descending': descending}, _limit);
  }

  Query<T> limit(int count) => Query<T>._(path, _filters, _orderBy, count);

  AggregateQuery count() => AggregateQuery._(this);

  Future<QuerySnapshot<T>> get([GetOptions? options]) async {
    final remoteFilters = _filters.where((f) => f['field'] != '__name__').toList();
    var docs = await _AppHttp.query(path, remoteFilters, _orderBy, _limit);
    for (final f in _filters) {
      if (f['field'] != '__name__') continue;
      if (f['op'] == 'in') {
        final ids = ((f['value'] as List?) ?? const []).map((e) => '$e').toSet();
        docs = docs.where((d) => ids.contains('${d['id']}')).toList();
      } else if (f['op'] == '==') {
        final id = '${f['value']}';
        docs = docs.where((d) => '${d['id']}' == id).toList();
      }
    }
    return QuerySnapshot<T>._(docs.map((d) => QueryDocumentSnapshot<T>._(d)).toList());
  }

  Stream<QuerySnapshot<T>> snapshots({bool includeMetadataChanges = false}) async* {
    yield await get();
    yield* Stream.periodic(const Duration(seconds: 10)).asyncMap((_) => get());
  }
}

class DocumentSnapshot<T extends Object?> {
  final String _collection;
  final String id;
  final Map<String, dynamic>? _raw;
  DocumentSnapshot._(this._collection, this.id, this._raw);

  bool get exists => _raw != null;
  String get path => '$_collection/$id';
  DocumentReference<T> get reference => DocumentReference<T>._(_collection, id);

  T? data() {
    if (_raw == null) return null;
    final inner = _raw!['data'];
    if (inner is Map) {
      return _hydrate(Map<String, dynamic>.from(inner)) as T;
    }
    return _hydrate(_raw!) as T;
  }

  dynamic operator [](Object field) {
    final value = data();
    if (value is Map) return value[field];
    return null;
  }

  dynamic get(Object field) => this[field];
}

class QueryDocumentSnapshot<T extends Object?> extends DocumentSnapshot<T> {
  QueryDocumentSnapshot._(Map<String, dynamic> raw)
      : super._(raw['collection']?.toString() ?? '', raw['id']?.toString() ?? '', raw);

  @override
  T data() {
    final value = super.data();
    if (value != null) return value;
    return <String, dynamic>{} as T;
  }
}

class AggregateQuery {
  final Query _query;
  AggregateQuery._(this._query);

  Future<AggregateQuerySnapshot> get() async {
    final snap = await _query.get();
    return AggregateQuerySnapshot._(snap.size);
  }
}

class AggregateQuerySnapshot {
  final int? count;
  AggregateQuerySnapshot._(this.count);
}

class QuerySnapshot<T extends Object?> {
  final List<QueryDocumentSnapshot<T>> docs;
  QuerySnapshot._(this.docs);
  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;
}

dynamic _encode(dynamic v) {
  if (v is FieldValue) return v.toJson();
  if (v is Timestamp) {
    return {'__fv': 'timestamp', 'iso': v.toDate().toUtc().toIso8601String()};
  }
  if (v is DateTime) {
    return {'__fv': 'timestamp', 'iso': v.toUtc().toIso8601String()};
  }
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _encode(val)));
  }
  if (v is List) return v.map(_encode).toList();
  return v;
}

dynamic _hydrate(dynamic v) {
  if (v is Map) {
    if (v['__fv'] == 'timestamp' && v['iso'] != null) {
      final dt = DateTime.tryParse(v['iso'].toString());
      if (dt != null) return Timestamp.fromDate(dt.toLocal());
    }
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      out[k.toString()] = _hydrate(val);
    });
    return out;
  }
  if (v is List) return v.map(_hydrate).toList();
  if (v is String) {
    final dt = DateTime.tryParse(v);
    if (dt != null && (v.contains('T') || v.contains('-') && v.contains(':'))) {
      return Timestamp.fromDate(dt.toLocal());
    }
  }
  return v;
}

class _AppHttp {
  static const _base = '${ApiService.baseUrl}/api/app';

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(16);

  static Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _decode(http.Response res) async {
    final raw = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (raw is! Map) throw Exception('Unexpected server response');
    final map = Map<String, dynamic>.from(raw);
    if (res.statusCode >= 400) {
      throw Exception(map['error']?.toString() ?? 'Request failed (${res.statusCode})');
    }
    return map;
  }

  static Future<List<Map<String, dynamic>>> query(
    String collection,
    List<Map<String, dynamic>> filters,
    Map<String, dynamic>? orderBy,
    int? limit,
  ) async {
    final res = await http.post(
      Uri.parse('$_base/query'),
      headers: await _headers(),
      body: jsonEncode({
        'collection': collection,
        'filters': filters,
        if (orderBy != null) 'orderBy': orderBy,
        if (limit != null) 'limit': limit,
      }),
    );
    final data = await _decode(res);
    return (data['docs'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>?> getDoc(String collection, String id) async {
    final res = await http.get(
      Uri.parse('$_base/doc').replace(queryParameters: {'c': collection, 'id': id}),
      headers: await _headers(),
    );
    final data = await _decode(res);
    if (data['exists'] != true) return null;
    final doc = data['doc'];
    if (doc is! Map) return null;
    return Map<String, dynamic>.from(doc);
  }

  static Future<String> create(String collection, Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$_base/doc'),
      headers: await _headers(),
      body: jsonEncode({'collection': collection, 'data': data}),
    );
    final out = await _decode(res);
    return '${out['id'] ?? newId()}';
  }

  static Future<void> set(String collection, String id, Map<String, dynamic> data, {required bool merge}) async {
    final res = await http.put(
      Uri.parse('$_base/doc'),
      headers: await _headers(),
      body: jsonEncode({'collection': collection, 'id': id, 'data': data, 'merge': merge}),
    );
    await _decode(res);
  }

  static Future<void> delete(String collection, String id) async {
    final res = await http.delete(
      Uri.parse('$_base/doc').replace(queryParameters: {'c': collection, 'id': id}),
      headers: await _headers(),
    );
    await _decode(res);
  }

  static Future<void> batch(List<Map<String, dynamic>> ops) async {
    final res = await http.post(
      Uri.parse('$_base/batch'),
      headers: await _headers(),
      body: jsonEncode({'ops': ops}),
    );
    await _decode(res);
  }
}

class AppAuthApi {
  static const _base = '${ApiService.baseUrl}/api/auth';

  static Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    final raw = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (res.statusCode >= 400) {
      throw map['error']?.toString() ?? 'Request failed (${res.statusCode})';
    }
    return map;
  }

  static Future<void> createUser(Map<String, dynamic> body) => _post('/create-user', body);
  static Future<void> deleteUser({String? uid, String? email}) =>
      _post('/delete-user', {if (uid != null) 'uid': uid, if (email != null) 'email': email});
  static Future<void> resetPassword({required String email, required String newPassword}) =>
      _post('/reset-password', {'email': email, 'newPassword': newPassword});
}
