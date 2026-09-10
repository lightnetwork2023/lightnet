import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_cost_guards.dart';

class _CachedRadacct {
  _CachedRadacct(this.data, this.at);
  final Map<String, dynamic>? data;
  final DateTime at;
}

class MikroTikMonitorService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'mikrotik_devices';
  static final Map<String, _CachedRadacct> _radacctCache = {};

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

  // Stream a specific set of devices by their Firestore document IDs
  static Stream<QuerySnapshot> getMikroTikDevicesByIds(List<String> ids) {
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

  /// Aggregates RX/TX bytes + active sessions for a MikroTik from
  /// the existing `radacct_history` Firestore collection.
  ///
  /// Tries multiple match fields because field naming may differ:
  ///   1. NAS_IP_Address == nasIp (most common)
  ///   2. Mikrotik_Host_IP == nasIp (fallback)
  ///
  /// Returns a map: { rx_bytes, tx_bytes, sessions, source } or null if no match.
  static Future<Map<String, dynamic>?> fetchRadacctStats(String nasIp) async {
    if (nasIp.isEmpty) return null;
    final cached = _radacctCache[nasIp];
    if (cached != null &&
        DateTime.now().difference(cached.at) < FirestoreCostGuards.radacctCacheTtl) {
      return cached.data;
    }
    try {
      // Try the primary field first.
      QuerySnapshot snap = await _firestore
          .collection('radacct_history')
          .where('NAS_IP_Address', isEqualTo: nasIp)
          .limit(FirestoreCostGuards.maxRadacctDocs)
          .get();

      String source = 'NAS_IP_Address';

      // Fallback: try Mikrotik_Host_IP if no match.
      if (snap.docs.isEmpty) {
        snap = await _firestore
            .collection('radacct_history')
            .where('Mikrotik_Host_IP', isEqualTo: nasIp)
            .limit(FirestoreCostGuards.maxRadacctDocs)
            .get();
        source = 'Mikrotik_Host_IP';
      }

      if (snap.docs.isEmpty) {
        _radacctCache[nasIp] = _CachedRadacct(null, DateTime.now());
        return null;
      }

      // Only account for records in the last 24 hours (in-memory filter).
      final cutoff24h = DateTime.now().subtract(const Duration(hours: 24));

      // Daytime window: 06:00 – 22:00 local time (16 h = 57,600 s)
      final now = DateTime.now();
      final todayDawn     = DateTime(now.year, now.month, now.day, 6, 0, 0);
      final todayDusk     = DateTime(now.year, now.month, now.day, 22, 0, 0);
      final cutoff15min   = now.subtract(const Duration(minutes: 15));

      // Per-session aggregation: take MAX values per Acct_Session_Id so we
      // don't double-count Start + Interim + Stop records.
      //
      // RFC 2866 semantics (NAS perspective):
      //   Acct_Input_Octets  = bytes received BY NAS from client  = UPLOAD   (WAN TX)
      //   Acct_Output_Octets = bytes sent FROM NAS to client      = DOWNLOAD (WAN RX)
      final Map<String, _SessionAgg> bySession = {};
      int activeSessions = 0;
      DateTime? newest;
      int skipped24h = 0;

      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;

        // ── 24-hour filter ──────────────────────────────────────────────
        final ts = d['Event_Timestamp'];
        DateTime? eventDt;
        if (ts is Timestamp) eventDt = ts.toDate();
        if (eventDt != null && eventDt.isBefore(cutoff24h)) {
          skipped24h++;
          continue;
        }

        final sid = (d['Acct_Session_Id'] ?? doc.id).toString();
        final inputO = _toInt(d['Acct_Input_Octets']);
        final outputO = _toInt(d['Acct_Output_Octets']);
        final inGw = _toInt(d['Acct_Input_Gigawords']);
        final outGw = _toInt(d['Acct_Output_Gigawords']);
        final sessTime = _toInt(d['Acct_Session_Time']);
        final type = (d['Acct_Status_Type'] ?? '').toString();

        // Combine Gigawords (each = 4 GiB) with octets for full count
        final upload   = (inGw  * (1 << 32)) + inputO;   // client→NAS = WAN TX
        final download = (outGw * (1 << 32)) + outputO;  // NAS→client = WAN RX

        final agg = bySession.putIfAbsent(sid, () => _SessionAgg());
        if (download > agg.downloadBytes) agg.downloadBytes = download;
        if (upload   > agg.uploadBytes)   agg.uploadBytes   = upload;
        if (sessTime > agg.sessionSec)    agg.sessionSec    = sessTime;
        if (type == 'Stop') agg.stopped = true;

        // Track daytime events for daytime-average estimate
        if (eventDt != null &&
            eventDt.isAfter(todayDawn) &&
            eventDt.isBefore(todayDusk)) {
          agg.daytime = true;
        }

        // Track recent 15-min events for near-real-time estimate
        if (eventDt != null && eventDt.isAfter(cutoff15min)) {
          if (download > agg.recent15Download) agg.recent15Download = download;
          if (upload   > agg.recent15Upload)   agg.recent15Upload   = upload;
        }

        if (eventDt != null && (newest == null || eventDt.isAfter(newest))) {
          newest = eventDt;
        }
      }

      int totalDownload   = 0;
      int totalUpload     = 0;
      int totalSessSec    = 0;
      int daytimeDownload = 0;
      int daytimeUpload   = 0;
      int recent15Download = 0;
      int recent15Upload   = 0;

      for (final a in bySession.values) {
        totalDownload += a.downloadBytes;
        totalUpload   += a.uploadBytes;
        totalSessSec  += a.sessionSec;
        if (!a.stopped) activeSessions++;
        if (a.daytime) {
          daytimeDownload += a.downloadBytes;
          daytimeUpload   += a.uploadBytes;
        }
        recent15Download += a.recent15Download;
        recent15Upload   += a.recent15Upload;
      }

      // ── Throughput averages ─────────────────────────────────────────
      // Divide total bytes by wall-clock seconds (24 h = 86 400 s), NOT by
      // the sum of session durations.  This gives the true average router
      // throughput over the day, which aligns with what network managers see.
      const int wallClockSec24h = 86400;
      const int daytimeSec      = 57600; // 16 h × 3600
      const int recentSec       = 900;   // 15 min

      final double avgBps      = ((totalDownload + totalUpload) * 8) / wallClockSec24h;
      final double daytimeAvgBps = daytimeDownload + daytimeUpload > 0
          ? ((daytimeDownload + daytimeUpload) * 8) / daytimeSec.toDouble()
          : avgBps * 2.0; // rough daytime estimate: 2× overall avg
      // Near-real-time estimate: bytes with Event_Timestamp in last 15 min ÷ 900 s
      final double recentAvgBps = recent15Download + recent15Upload > 0
          ? ((recent15Download + recent15Upload) * 8) / recentSec.toDouble()
          : 0;

      final result = {
        'rx_bytes': totalDownload,              // 24h download (NAS→client)
        'tx_bytes': totalUpload,                // 24h upload   (client→NAS)
        'avg_bps': avgBps.round(),              // 24h wall-clock average throughput
        'daytime_avg_bps': daytimeAvgBps.round(), // 06:00–22:00 estimate
        'recent_avg_bps': recentAvgBps.round(), // last-15-min near-realtime estimate
        'total_session_sec': totalSessSec,
        'sessions': bySession.length,
        'active_sessions': activeSessions,
        'source': source,
        'last_event': newest,
      };
      _radacctCache[nasIp] = _CachedRadacct(result, DateTime.now());
      return result;
    } catch (e) {
      // Likely a missing composite index — return null silently
      return null;
    }
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

class _SessionAgg {
  int downloadBytes = 0;    // NAS→client
  int uploadBytes = 0;      // client→NAS
  int sessionSec = 0;
  bool stopped = false;
  bool daytime = false;     // event occurred in 06:00–22:00 window
  int recent15Download = 0; // bytes in last 15-min window
  int recent15Upload   = 0;
}
