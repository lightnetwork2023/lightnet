import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class WifiBeaconScannerService {
  static const String _prefKey = 'wifi_beacon_scanning_enabled';
  static const List<String> _nokiaOuis = ['B4:63:6F', 'B6:63:6F', 'E0:1F:2B'];
  static const Set<String> _alwaysOnRoles = {'technician', 'agent', 'dealer'};

  /// Returns the raw BSSID of the connected AP (no OUI filter).
  /// Uses MethodChannel first (reliable on Android 10+), falls back to NetworkInfo.
  static Future<String?> getConnectedBssidRaw() async {
    // Try MethodChannel first
    try {
      final ext = await getConnectedWifiExtendedInfo();
      final raw = ext?['bssid'] as String?;
      if (raw != null && raw.length > 10 && raw != '02:00:00:00:00:00') {
        return raw.toUpperCase().trim();
      }
    } catch (_) {}
    // Fallback to NetworkInfo
    try {
      final info = NetworkInfo();
      final bssid = await info.getWifiBSSID();
      if (bssid != null && bssid.length > 10 && bssid != '02:00:00:00:00:00') {
        return bssid.toUpperCase().trim();
      }
    } catch (_) {}
    return null;
  }

  /// Returns the Nokia BSSID the phone is currently connected to, or null.
  static Future<String?> getConnectedNokiaBssid() async {
    final bssid = await getConnectedBssidRaw();
    if (bssid == null) return null;
    if (_nokiaOuis.any((oui) => bssid.startsWith(oui))) return bssid;
    return null;
  }

  /// Native MethodChannel: get link speed, Tx/Rx speed for connected AP.
  static const _wifiChannel = MethodChannel('com.tz.lightnet/wifi_info');
  static Future<Map<String, dynamic>?> getConnectedWifiExtendedInfo() async {
    try {
      final raw = await _wifiChannel
          .invokeMapMethod<String, dynamic>('getConnectedWifiInfo');
      return raw;
    } catch (_) {
      return null;
    }
  }

  // ── RF helper methods ─────────────────────────────────────────────────────

  static String _phyMode(WiFiStandards s) {
    switch (s) {
      case WiFiStandards.ax:     return '802.11ax';
      case WiFiStandards.ac:     return '802.11ac';
      case WiFiStandards.n:      return '802.11n';
      case WiFiStandards.legacy: return '802.11a/g';
      default:                   return 'Unknown';
    }
  }

  static int _chWidthMhz(WiFiChannelWidth? w) {
    switch (w) {
      case WiFiChannelWidth.mhz160:
      case WiFiChannelWidth.mhz80Plus80: return 160;
      case WiFiChannelWidth.mhz80:       return 80;
      case WiFiChannelWidth.mhz40:       return 40;
      case WiFiChannelWidth.mhz20:       return 20;
      default:                           return 0;
    }
  }

  static bool _isDfs(int channel, bool is5) {
    if (!is5) return false;
    return (channel >= 52 && channel <= 64) || (channel >= 100 && channel <= 144);
  }

  /// Estimated SNR using typical noise floors (2.4G≈-95, 5G≈-98).
  /// Returns 0 if RSSI is 0 / unavailable.
  static int _estimatedSnr(int rssi, bool is24) {
    if (rssi == 0) return 0;
    final noiseFloor = is24 ? -95 : -98;
    return (rssi - noiseFloor).clamp(0, 60);
  }

  static String _snrLabel(int snr) {
    if (snr >= 25) return 'Excellent';
    if (snr >= 15) return 'Usable';
    if (snr > 0)   return 'Poor';
    return '—';
  }

  static int confidenceScore(Timestamp? lastSeen) {
    if (lastSeen == null) return 0;
    final minutes = DateTime.now().difference(lastSeen.toDate()).inMinutes;
    if (minutes <  5)   return 100;
    if (minutes < 30)   return 80;
    if (minutes < 60)   return 60;
    if (minutes < 360)  return 30;
    return 0;
  }

  /// Derive frequency band from center frequency in MHz.
  static String _bandFromFreq(int freqMhz) {
    if (freqMhz >= 2400 && freqMhz <= 2500) return '2.4 GHz';
    if (freqMhz >= 4900 && freqMhz <= 6000) return '5 GHz';
    if (freqMhz >= 6000) return '6 GHz';
    return '?';
  }

  /// Derive channel number from frequency in MHz.
  static int _channelFromFreq(int freqMhz) {
    if (freqMhz == 2484) return 14;
    if (freqMhz >= 2412 && freqMhz < 2484) return (freqMhz - 2412) ~/ 5 + 1;
    if (freqMhz >= 5160 && freqMhz <= 5885) return (freqMhz - 5000) ~/ 5;
    if (freqMhz >= 4915 && freqMhz < 5160) return (freqMhz - 4000) ~/ 5;
    return 0;
  }

  static Future<bool> isScanningEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? true;
  }

  static Future<void> setScanningEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  static Future<void> scanAndReport({bool forceEnabled = false, bool askPermissions = false}) async {
    try {
      String userRole = 'user';
      String userName = 'Unknown';
      String uid = 'anon';
      try {
        final auth = Get.find<AuthController>();
        userRole = auth.userRole.toLowerCase();
        uid = auth.user?.uid ?? 'anon';
        // Best available display name fallback
        if (auth.userName.isNotEmpty) {
          userName = auth.userName;
        } else if (auth.user?.displayName?.isNotEmpty == true) {
          userName = auth.user!.displayName!;
        } else if (auth.user?.email?.isNotEmpty == true) {
          userName = auth.user!.email!.split('@').first;
        } else if (uid != 'anon') {
          userName = uid.substring(0, uid.length.clamp(0, 8));
        }
      } catch (_) {}

      final roleForced = _alwaysOnRoles.contains(userRole);
      final effectiveForce = forceEnabled || roleForced;
      if (effectiveForce) {
        await setScanningEnabled(true);
      }

      if (!effectiveForce && !await isScanningEnabled()) {
        debugPrint('WifiBeaconScanner: skipped (disabled in preferences)');
        return;
      }

      final shouldAsk = askPermissions || roleForced;

      // Explicitly request location permission — required for WiFi scanning
      // on all Android versions (wifi_scan's internal ask is not reliable)
      if (shouldAsk) {
        try {
          LocationPermission perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.deniedForever) {
            debugPrint('WifiBeaconScanner: location permission permanently denied');
            return;
          }
        } catch (_) {}
      }

      final canGet = await WiFiScan.instance
          .canGetScannedResults(askPermissions: shouldAsk);
      if (canGet != CanGetScannedResults.yes) {
        debugPrint('WifiBeaconScanner: canGetScannedResults=$canGet');
        return;
      }

      final canStart =
          await WiFiScan.instance.canStartScan(askPermissions: shouldAsk);
      if (canStart == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 3));
      } else {
        debugPrint('WifiBeaconScanner: canStartScan=$canStart (using cached results)');
      }

      final results = await WiFiScan.instance.getScannedResults();

      final nokiaAps = results.where((ap) {
        final mac = ap.bssid.toUpperCase();
        final ssid = ap.ssid.toUpperCase();
        final isNokia = _nokiaOuis.any((oui) => mac.startsWith(oui));
        final isLightnet = ssid.contains('LIGHTNET');
        return isNokia || isLightnet;
      }).toList();

      if (nokiaAps.isEmpty) return;

      final db = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();

      // Clean up this user's stale discovered entries (older than 10 minutes)
      try {
        final tenMinAgo = Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 10)));
        final stale = await db
            .collection('nokia_beacons_discovered')
            .where('scanned_by_uid', isEqualTo: uid)
            .where('last_seen', isLessThan: tenMinAgo)
            .get();
        for (final d in stale.docs) {
          d.reference.delete(); // fire-and-forget
        }
      } catch (_) {}

      for (final ap in nokiaAps) {
        final bssid = ap.bssid.toUpperCase().trim();
        if (bssid.isEmpty || bssid == '00:00:00:00:00:00') continue;

        final signalPercent = _dbmToPercent(ap.level);
        final freqMhz = ap.frequency;
        final band = _bandFromFreq(freqMhz);
        final channel = _channelFromFreq(freqMhz);
        final is24 = band == '2.4 GHz';
        final is5  = band == '5 GHz';

        // ── New RF fields from WiFiAccessPoint ──
        final phyMode = _phyMode(ap.standard);
        final chWidthMhz = _chWidthMhz(ap.channelWidth);
        final isDfs = _isDfs(channel, is5);
        final estSnr = _estimatedSnr(ap.level, is24);

        final snap = await db
            .collection('nokia_beacons')
            .where('mac_address', isEqualTo: bssid)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          final Map<String, dynamic> update = {
            'status': 'online',
            'last_seen': now,
            'last_checked': now,
            'last_signal_dbm': ap.level,
            'last_signal_percent': signalPercent,
            'last_scanned_by': userName,
            'last_scanned_role': userRole,
            'last_frequency_mhz': freqMhz,
            'last_frequency_band': band,
            'phy_mode': phyMode,
            'est_snr_db': estSnr,
            'snr_label': _snrLabel(estSnr),
            'seen_count': FieldValue.increment(1),
            if (chWidthMhz > 0) 'channel_width_mhz': chWidthMhz,
            'is_dfs': isDfs,
          };
          if (channel > 0) {
            if (is24) update['channel_2ghz'] = channel.toString();
            if (is5)  update['channel_5ghz'] = channel.toString();
          }
          // For connected AP: get link speed from native
          if (bssid == (await getConnectedNokiaBssid())) {
            final ext = await getConnectedWifiExtendedInfo();
            if (ext != null) {
              update['last_link_speed_mbps'] = ext['linkSpeedMbps'] ?? 0;
              update['last_tx_speed_mbps']   = ext['txSpeedMbps'] ?? 0;
              update['last_rx_speed_mbps']   = ext['rxSpeedMbps'] ?? 0;
            }
          }
          await snap.docs.first.reference.update(update);
        } else {
          // Unregistered — store under a per-user key so each user sees only their own
          final docKey = '${uid}_$bssid';
          final discData = <String, dynamic>{
            'bssid': bssid,
            'scanned_by_uid': uid,
            'last_signal_dbm': ap.level,
            'last_signal_percent': signalPercent,
            'last_scanned_by': userName,
            'last_scanned_role': userRole,
            'last_seen': now,
            'last_frequency_mhz': freqMhz,
            'last_frequency_band': band,
            'phy_mode': phyMode,
            'est_snr_db': estSnr,
            'snr_label': _snrLabel(estSnr),
            if (chWidthMhz > 0) 'channel_width_mhz': chWidthMhz,
            'is_dfs': isDfs,
          };
          if (channel > 0 && is24) discData['channel_2ghz'] = channel.toString();
          if (channel > 0 && is5)  discData['channel_5ghz'] = channel.toString();
          discData['first_seen'] = FieldValue.serverTimestamp();
          await db
              .collection('nokia_beacons_discovered')
              .doc(docKey)
              .set(discData, SetOptions(merge: true));
        }
      }

      debugPrint(
          'WifiBeaconScanner: reported ${nokiaAps.length} Nokia/LIGHTNET AP(s)');
    } catch (e) {
      debugPrint('WifiBeaconScannerService error: $e');
    }
  }

  static int _dbmToPercent(int dbm) {
    if (dbm >= -50) return 100;
    if (dbm <= -100) return 0;
    return (2 * (dbm + 100)).clamp(0, 100);
  }
}
