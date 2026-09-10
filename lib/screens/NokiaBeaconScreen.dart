import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import '../services/NokiaBeaconService.dart';
import '../services/WifiBeaconScannerService.dart';

class NokiaBeaconScreen extends StatefulWidget {
  const NokiaBeaconScreen({super.key});

  @override
  State<NokiaBeaconScreen> createState() => _NokiaBeaconScreenState();
}

class _NokiaBeaconScreenState extends State<NokiaBeaconScreen> {
  String _filterStatus = 'all';
  String? _connectedBssid;
  bool _refreshing = false;
  Timer? _bssidTimer;

  @override
  void initState() {
    super.initState();
    _loadConnectedBssid();
    // Refresh every 10 s so the connected-beacon banner stays accurate
    _bssidTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadConnectedBssid());
  }

  @override
  void dispose() {
    _bssidTimer?.cancel();
    super.dispose();
  }

  /// Loads the connected AP BSSID using MethodChannel + NetworkInfo (no OUI filter).
  /// Sticky: only replaces the cached value when a real BSSID is returned;
  /// a temporary null (Android radio busy) does NOT clear a valid cached entry.
  Future<void> _loadConnectedBssid() async {
    final bssid = await WifiBeaconScannerService.getConnectedBssidRaw();
    if (!mounted) return;
    if (bssid != null) {
      // Got a real BSSID — update cache
      if (_connectedBssid != bssid) setState(() => _connectedBssid = bssid);
    }
    // If null: radio is temporarily busy or disconnected; keep the cached value
    // to avoid the banner flickering. The next successful poll will correct it.
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await WifiBeaconScannerService.scanAndReport(forceEnabled: true, askPermissions: true);
      await _loadConnectedBssid();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nokia Beacon Monitor',
            style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh & Scan',
              onPressed: _refresh,
            ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Setup Guide',
            onPressed: () => _showSetupGuide(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(context),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Beacon', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: NokiaBeaconService.streamAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final allDocs = snap.data?.docs ?? [];
          final online = allDocs.where((d) => d.data()['status'] == 'online').length;
          final offline = allDocs.where((d) => d.data()['status'] == 'offline').length;
          final stale = allDocs.where((d) => d.data()['status'] == 'stale').length;
          final unknown = allDocs.where((d) => d.data()['status'] == 'unknown').length;

          final filtered = _filterStatus == 'all'
              ? allDocs
              : allDocs.where((d) => d.data()['status'] == _filterStatus).toList();

          final sorted = [...filtered]..sort((a, b) {
              // Connected beacon always first
              final aConn = _connectedBssid != null &&
                  (a.data()['mac_address'] ?? '').toString().toUpperCase() == _connectedBssid;
              final bConn = _connectedBssid != null &&
                  (b.data()['mac_address'] ?? '').toString().toUpperCase() == _connectedBssid;
              if (aConn != bConn) return aConn ? -1 : 1;
              const order = {'offline': 0, 'stale': 1, 'unknown': 2, 'online': 3};
              final sa = order[a.data()['status'] ?? 'unknown'] ?? 1;
              final sb = order[b.data()['status'] ?? 'unknown'] ?? 1;
              if (sa != sb) return sa.compareTo(sb);
              return (a.data()['name'] as String? ?? '').compareTo(b.data()['name'] as String? ?? '');
            });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // ── Summary Row ────────────────────────────────────────────
              Row(
                children: [
                  _SummaryChip(
                    label: 'All',
                    count: allDocs.length,
                    color: AppTheme.primaryColor,
                    selected: _filterStatus == 'all',
                    onTap: () => setState(() => _filterStatus = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: 'Online',
                    count: online,
                    color: Colors.green,
                    selected: _filterStatus == 'online',
                    onTap: () => setState(() => _filterStatus = 'online'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: 'Offline',
                    count: offline,
                    color: Colors.red,
                    selected: _filterStatus == 'offline',
                    onTap: () => setState(() => _filterStatus = 'offline'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: 'Stale',
                    count: stale,
                    color: Colors.orange,
                    selected: _filterStatus == 'stale',
                    onTap: () => setState(() => _filterStatus = 'stale'),
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: 'Unknown',
                    count: unknown,
                    color: Colors.grey,
                    selected: _filterStatus == 'unknown',
                    onTap: () => setState(() => _filterStatus = 'unknown'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DiscoveredBeaconsSection(
                currentUid: Get.find<AuthController>().user?.uid ?? 'anon',
                onRegister: (bssid) => _showAddEditDialog(context, null, null, bssid),
              ),
              const SizedBox(height: 6),

              if (allDocs.isEmpty)
                _buildEmptyState(context)
              else if (sorted.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      'No $_filterStatus beacons',
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ),
                )
              else
                ...sorted.map((doc) => _BeaconCard(
                      docId: doc.id,
                      data: doc.data(),
                      isConnected: _connectedBssid != null &&
                          (doc.data()['mac_address'] ?? '').toString().toUpperCase() == _connectedBssid,
                      onEdit: () => _showAddEditDialog(context, doc.id, doc.data()),
                      onDelete: () => _confirmDelete(context, doc.id, doc.data()['name'] ?? ''),
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cell_tower_rounded,
                size: 56, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 20),
          const Text('No Nokia Beacons Registered',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Register your Nokia Beacon 1.1 MAC addresses\nto monitor online/offline status.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showSetupGuide(context),
            icon: const Icon(Icons.info_outline_rounded),
            label: const Text('How does detection work?'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddEditDialog(
    BuildContext context, [
    String? docId,
    Map<String, dynamic>? existing,
    String? prefillMac,
  ]) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final macCtrl = TextEditingController(text: existing?['mac_address'] ?? prefillMac ?? '');
    final locCtrl = TextEditingController(text: existing?['location'] ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');
    final ssidCtrl = TextEditingController(text: existing?['ssid'] ?? '');
    final ch2Ctrl = TextEditingController(text: existing?['channel_2ghz'] ?? '');
    final ch5Ctrl = TextEditingController(text: existing?['channel_5ghz'] ?? '');
    final speedCtrl = TextEditingController(text: existing?['connection_speed'] ?? '');
    final connectedToCtrl = TextEditingController(text: existing?['connected_to'] ?? '');
    final mikrotikInterfaceCtrl = TextEditingController(text: existing?['mikrotik_interface'] ?? '');
    String? selectedMikrotikId = existing?['mikrotik_id'] as String?;
    String selectedMikrotikName = '';
    bool saving = false;

    final mikrotikSnap = await FirebaseFirestore.instance
        .collection('mikrotik_devices')
        .get();
    final mikrotikDocs = mikrotikSnap.docs;
    if (selectedMikrotikId != null) {
      final found = mikrotikDocs.where((d) => d.id == selectedMikrotikId);
      if (found.isNotEmpty) {
        selectedMikrotikName = found.first.data()['name'] as String? ?? '';
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.cell_tower_rounded, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              Text(docId != null ? 'Edit Beacon' : 'Add Nokia Beacon'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Beacon Name *',
                    hintText: 'e.g. Beacon-Mbagala-01',
                    prefixIcon: const Icon(Icons.label_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: macCtrl,
                  inputFormatters: [
                    TextInputFormatter.withFunction((old, newVal) {
                      final raw = newVal.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
                      final formatted = StringBuffer();
                      for (int i = 0; i < raw.length && i < 12; i++) {
                        if (i > 0 && i % 2 == 0) formatted.write(':');
                        formatted.write(raw[i]);
                      }
                      final str = formatted.toString();
                      return TextEditingValue(
                        text: str,
                        selection: TextSelection.collapsed(offset: str.length),
                      );
                    }),
                  ],
                  decoration: InputDecoration(
                    labelText: 'MAC Address *',
                    hintText: 'B4:63:6F:96:E0:9E',
                    prefixIcon: const Icon(Icons.memory_outlined),
                    helperText: 'Nokia OUI starts with B4:63:6F',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locCtrl,
                  decoration: InputDecoration(
                    labelText: 'Location *',
                    hintText: 'e.g. Mbagala',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                // MikroTik picker
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final picked = await showDialog<Map<String, String>>(
                      context: ctx,
                      builder: (_) => _MikrotikPickerDialog(docs: mikrotikDocs),
                    );
                    if (picked != null) {
                      setDlg(() {
                        selectedMikrotikId = picked['id'];
                        selectedMikrotikName = picked['name'] ?? '';
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Assigned MikroTik *',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      selectedMikrotikName.isNotEmpty
                          ? selectedMikrotikName
                          : 'Select MikroTik…',
                      style: TextStyle(
                        color: selectedMikrotikName.isNotEmpty
                            ? Colors.black87
                            : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ssidCtrl,
                  decoration: InputDecoration(
                    labelText: 'SSID (WiFi name)',
                    hintText: 'e.g. chalinze',
                    prefixIcon: const Icon(Icons.wifi_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: ch2Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '2.4GHz Channel',
                        hintText: '1, 6 or 11',
                        prefixIcon: const Icon(Icons.settings_input_antenna),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: ch5Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '5GHz Channel',
                        hintText: '36, 40…',
                        prefixIcon: const Icon(Icons.settings_input_antenna),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: speedCtrl,
                  decoration: InputDecoration(
                    labelText: 'Connection Speed',
                    hintText: 'TX: 300 / RX: 150 Mbps',
                    prefixIcon: const Icon(Icons.speed_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: connectedToCtrl,
                  decoration: InputDecoration(
                    labelText: 'Connected To (beacon)',
                    hintText: 'Which Nokia the dealer connects to',
                    prefixIcon: const Icon(Icons.link_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mikrotikInterfaceCtrl,
                  decoration: InputDecoration(
                    labelText: 'MikroTik Interface (optional)',
                    hintText: 'e.g. ether3, bridge1, vlan10',
                    prefixIcon: const Icon(Icons.cable_outlined),
                    helperText: 'Port this Nokia is plugged into on MikroTik',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: const Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final mac = macCtrl.text.trim();
                      final loc = locCtrl.text.trim();
                      if (name.isEmpty || mac.isEmpty || loc.isEmpty || selectedMikrotikId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill all required fields')),
                        );
                        return;
                      }
                      if (mac.length != 17) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid MAC address format')),
                        );
                        return;
                      }
                      setDlg(() => saving = true);
                      try {
                        if (docId != null) {
                          await NokiaBeaconService.update(docId,
                              name: name,
                              macAddress: mac,
                              location: loc,
                              mikrotikId: selectedMikrotikId,
                              notes: notesCtrl.text.trim(),
                              ssid: ssidCtrl.text.trim(),
                              channel2ghz: ch2Ctrl.text.trim(),
                              channel5ghz: ch5Ctrl.text.trim(),
                              connectionSpeed: speedCtrl.text.trim(),
                              connectedTo: connectedToCtrl.text.trim(),
                              mikrotikInterface: mikrotikInterfaceCtrl.text.trim());
                        } else {
                          await NokiaBeaconService.add(
                            name: name,
                            macAddress: mac,
                            location: loc,
                            mikrotikId: selectedMikrotikId!,
                            notes: notesCtrl.text.trim(),
                            ssid: ssidCtrl.text.trim(),
                            channel2ghz: ch2Ctrl.text.trim(),
                            channel5ghz: ch5Ctrl.text.trim(),
                            connectionSpeed: speedCtrl.text.trim(),
                            connectedTo: connectedToCtrl.text.trim(),
                            mikrotikInterface: mikrotikInterfaceCtrl.text.trim(),
                          );
                        }
                        if (context.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDlg(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    },
              child: Text(docId != null ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Beacon?'),
        content: Text('Remove "$name" from monitoring?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await NokiaBeaconService.delete(docId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beacon removed')),
        );
      }
    }
  }

  void _showSetupGuide(BuildContext context) {
    const diagCmd =
        '/ip arp print\n/ip dhcp-server lease print\n/interface bridge host print';

    const script = r'''# ── Nokia Beacon Detector (Enhanced) ───────────
# Add to /system scheduler  |  Name: nokia-beacon-check
# Interval: 00:02:00        |  Policy: read,write,test,sniff

:local cfUrl "https://us-central1-lightnet-d2de9.cloudfunctions.net/reportNokiaBeaconStatus"
:local mikrotikId "YOUR_MIKROTIK_FIRESTORE_DOC_ID"
:local macs ""
:local count 0

# ── Layer 1: ARP table (Nokia Beacon gets management IP via DHCP)
:foreach a in [/ip arp find] do={
  :local mac [/ip arp get $a mac-address]
  :if (([:pick $mac 0 8]="B4:63:6F") || ([:pick $mac 0 8]="B6:63:6F")) do={
    :if ($count > 0) do={ :set macs ($macs . ",") }
    :set macs ($macs . "\"" . $mac . "\"")
    :set count ($count + 1)
  }
}

# ── Layer 2: DHCP lease table (persistent even between scans)
:foreach l in [/ip dhcp-server lease find] do={
  :local mac [/ip dhcp-server lease get $l mac-address]
  :if (([:pick $mac 0 8]="B4:63:6F") || ([:pick $mac 0 8]="B6:63:6F")) do={
    :if ($count > 0) do={ :set macs ($macs . ",") }
    :set macs ($macs . "\"" . $mac . "\"")
    :set count ($count + 1)
  }
}

# ── Layer 3: Bridge host table (L2 forwarding cache)
:foreach h in [/interface bridge host find] do={
  :local mac [/interface bridge host get $h mac-address]
  :if (([:pick $mac 0 8]="B4:63:6F") || ([:pick $mac 0 8]="B6:63:6F")) do={
    :if ($count > 0) do={ :set macs ($macs . ",") }
    :set macs ($macs . "\"" . $mac . "\"")
    :set count ($count + 1)
  }
}

:local payload ("{\"mikrotik_id\":\"" . $mikrotikId . "\",\"visible_macs\":[" . $macs . "]}")
/tool fetch url=$cfUrl mode=https http-method=post \
  http-header-field="Content-Type:application/json" \
  http-data=$payload output=none''';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.integration_instructions_outlined,
              color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          const Text('MikroTik Setup Guide'),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Why it was failing ──────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Why MikroTik "can\'t see" it:\n'
                          'Nokia Beacon 1.1 in bridge mode has no static IP. '
                          'MikroTik\'s bridge host table is passive and entries expire. '
                          'BUT — the beacon still requests a management IP via DHCP, '
                          'which appears in the ARP table. The updated script checks '
                          'ARP + DHCP leases + bridge host for maximum reliability.',
                          style: TextStyle(fontSize: 11.5, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Step 0: Diagnose first ──────────────────────
                _guideStep('→', 'Diagnose first (MikroTik Terminal)',
                    'Run these 3 commands in MikroTik terminal. Look for a MAC starting with B4:63:6F — that is your Nokia Beacon\'s management MAC.'),
                _codeBlock(
                  context,
                  label: 'Diagnostic Commands',
                  code: diagCmd,
                  copyText: diagCmd,
                ),
                const SizedBox(height: 14),

                _guideStep('1', 'Give the beacon a static DHCP lease (recommended)',
                    'In MikroTik: IP → DHCP Server → Leases → Add. Set the Nokia Beacon\'s wired MAC (found above) with a fixed IP like 192.168.x.250. This makes it permanently visible in the ARP table.'),
                _guideStep('2', 'Get your MikroTik Firestore ID',
                    'Open MikroTik Monitoring screen → tap the device → the Firestore document ID is shown. Replace YOUR_MIKROTIK_FIRESTORE_DOC_ID in the script.'),
                _guideStep('3', 'Add the RouterOS scheduler script',
                    'MikroTik: System → Scheduler → Add. Name: nokia-beacon-check, Interval: 00:02:00, Policy: check read,write,test,sniff. Paste the script below.'),
                const SizedBox(height: 8),
                _codeBlock(context,
                    label: 'RouterOS Scheduler Script',
                    code: script,
                    copyText: script),
                const SizedBox(height: 14),
                _guideStep('4', 'Register beacons in the app',
                    'Use "+ Add Beacon". The MAC to register is the WiFi BSSID seen on your phone (B4:63:6F:xx:xx:xx). The beacon\'s wired MAC may differ by 1-2 digits — register both if unsure.'),
                _guideStep('5', 'Status updates automatically',
                    'Every 2 minutes MikroTik checks ARP + DHCP + bridge and reports. Status updates within 2 minutes of the beacon going online or offline.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(
    BuildContext context, {
    required String label,
    required String code,
    required String copyText,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.green, fontSize: 11)),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: copyText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
                child: const Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('Copy',
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(code,
              style: const TextStyle(
                  color: Color(0xFFCDD6F4),
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  height: 1.5)),
        ],
      ),
    );
  }

  Widget _guideStep(String num, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
            child: Text(num,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Beacon Card ────────────────────────────────────────────────────────────────

class _BeaconCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isConnected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BeaconCard({
    required this.docId,
    required this.data,
    required this.isConnected,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'unknown';
    final name = data['name'] as String? ?? 'Unknown';
    final mac = data['mac_address'] as String? ?? '';
    final location = data['location'] as String? ?? '';
    final notes = data['notes'] as String? ?? '';
    final lastSeen = data['last_seen'] as Timestamp?;
    final lastChecked = data['last_checked'] as Timestamp?;

    final statusColor = status == 'online'
        ? Colors.green
        : status == 'offline'
            ? Colors.red
            : status == 'stale'
                ? Colors.orange
                : Colors.grey;
    final statusIcon = status == 'online'
        ? Icons.wifi_rounded
        : status == 'offline'
            ? Icons.wifi_off_rounded
            : Icons.wifi_find_rounded;
    final signalPercent = data['last_signal_percent'] as int?;
    final signalDbm = data['last_signal_dbm'] as int?;
    final scannedBy = data['last_scanned_by'] as String?;

    final lastSeenStr = lastSeen != null
        ? _formatTime(lastSeen.toDate())
        : 'Never';
    final lastCheckedStr = lastChecked != null
        ? _formatTime(lastChecked.toDate())
        : '—';

    return Card(
      elevation: isConnected ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isConnected ? Colors.blue.shade400 : statusColor.withOpacity(0.3),
          width: isConnected ? 2 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isConnected)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_android_rounded, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text('YOUR PHONE IS CONNECTED TO THIS BEACON',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                  ],
                ),
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.blue.withOpacity(0.1) : statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, color: isConnected ? Colors.blue : statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(location,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                    if (v == 'copy') {
                      Clipboard.setData(ClipboardData(text: mac));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('MAC copied to clipboard')),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy_rounded, size: 18), SizedBox(width: 8), Text('Copy MAC')])),
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.memory_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 6),
                  SelectableText(
                    mac,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _infoChip(Icons.visibility_rounded, 'Last seen: $lastSeenStr'),
                const SizedBox(width: 8),
                _infoChip(Icons.sync_rounded, 'Checked: $lastCheckedStr'),
              ],
            ),
            if (signalPercent != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    signalPercent >= 70
                        ? Icons.signal_wifi_4_bar_rounded
                        : signalPercent >= 40
                            ? Icons.network_wifi_2_bar_rounded
                            : Icons.signal_wifi_0_bar_rounded,
                    size: 13,
                    color: signalPercent >= 70
                        ? Colors.green
                        : signalPercent >= 40
                            ? Colors.orange
                            : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "$signalPercent%  (${signalDbm ?? '?'} dBm)${scannedBy != null ? '  •  by $scannedBy' : ''}",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            // ── RF Details row ────────────────────────────────────
            () {
              final phy   = data['phy_mode'] as String?;
              final width = data['channel_width_mhz'] as int?;
              final snr   = data['est_snr_db'] as int?;
              final snrLbl= data['snr_label'] as String?;
              final dfs   = data['is_dfs'] as bool? ?? false;
              final seenCount = data['seen_count'] as int?;
              final confidence = WifiBeaconScannerService.confidenceScore(
                  data['last_seen'] as Timestamp?);
              if (phy == null && width == null && snr == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (phy != null && phy != 'Unknown')
                        _rfBadge(Icons.wifi_tethering_rounded, phy, Colors.indigo),
                      if (width != null && width > 0)
                        _rfBadge(Icons.settings_ethernet_rounded, '${width}MHz', Colors.teal),
                      if (snr != null && snr > 0)
                        _rfBadge(Icons.graphic_eq_rounded,
                            '~${snr}dB ${snrLbl ?? ""}',
                            snr >= 25 ? Colors.green : snr >= 15 ? Colors.orange : Colors.red),
                      if (dfs)
                        _rfBadge(Icons.radar_rounded, 'DFS', Colors.purple),
                      if (seenCount != null)
                        _rfBadge(Icons.track_changes_rounded, 'Seen $seenCount×', Colors.blueGrey),
                      _rfBadge(Icons.verified_rounded, '$confidence%',
                          confidence >= 80 ? Colors.green : confidence >= 50 ? Colors.orange : Colors.red),
                    ],
                  ),
                ],
              );
            }(),
            // ── Link Speed (connected AP only) ────────────────────
            if (isConnected) () {
              final link = data['last_link_speed_mbps'] as int?;
              final tx   = data['last_tx_speed_mbps'] as int?;
              final rx   = data['last_rx_speed_mbps'] as int?;
              if (link == null || link == 0) return const SizedBox.shrink();
              return Column(children: [
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.speed_rounded, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Link: $link Mbps'
                      '${(tx != null && tx > 0 && tx != link) ? '  ↑$tx' : ''}'
                      '${(rx != null && rx > 0 && rx != link) ? '  ↓$rx' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ]);
            }(),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.notes_rounded, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(notes,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rfBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM HH:mm').format(dt);
  }
}

// ── Summary Chip ───────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(selected ? 0 : 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withOpacity(0.3) : color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MikroTik Picker Dialog ─────────────────────────────────────────────────────

class _MikrotikPickerDialog extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _MikrotikPickerDialog({required this.docs});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select MikroTik'),
      content: SizedBox(
        width: double.maxFinite,
        child: docs.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No MikroTik devices found.\nAdd from MikroTik Monitoring.',
                    textAlign: TextAlign.center),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final name = d['name'] as String? ?? 'Unknown';
                  final ip = d['ipAddress'] as String? ?? '';
                  final loc = d['location'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.dns_outlined,
                        color: AppTheme.primaryColor),
                    title: Text(name),
                    subtitle: Text('$loc  •  $ip'),
                    onTap: () => Navigator.pop(
                        context, {'id': docs[i].id, 'name': name}),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}

// ── Discovered Beacons Section ─────────────────────────────────────────────────

class _DiscoveredBeaconsSection extends StatelessWidget {
  final String currentUid;
  final void Function(String bssid) onRegister;

  const _DiscoveredBeaconsSection({
    required this.currentUid,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('nokia_beacons_discovered')
          .where('scanned_by_uid', isEqualTo: currentUid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
        final docs = [...snap.data!.docs]
            .where((d) {
              final ts = d.data()['last_seen'] as Timestamp?;
              if (ts == null) return false;
              return ts.toDate().isAfter(cutoff);
            })
            .toList()
          ..sort((a, b) {
              final aT = (a.data()['last_seen'] as Timestamp?)?.seconds ?? 0;
              final bT = (b.data()['last_seen'] as Timestamp?)?.seconds ?? 0;
              return bT.compareTo(aT);
            });
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.shade200),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.cell_tower_rounded,
                  color: Colors.purple, size: 22),
              title: Text(
                '${docs.length} Unregistered Beacon${docs.length > 1 ? 's' : ''} Discovered',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.purple,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'Tap to view & register',
                style: TextStyle(fontSize: 11, color: Colors.purple),
              ),
              children: docs
                  .map((doc) => _DiscoveredBeaconTile(
                        data: doc.data(),
                        onRegister: () => onRegister(
                            doc.data()['bssid'] as String? ?? doc.id),
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _DiscoveredBeaconTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onRegister;

  const _DiscoveredBeaconTile({
    required this.data,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    final bssid = data['bssid'] as String? ?? '';
    final signalPercent = data['last_signal_percent'] as int?;
    final signalDbm = data['last_signal_dbm'] as int?;
    final scannedBy = data['last_scanned_by'] as String? ?? '';
    final lastSeen = data['last_seen'] as Timestamp?;
    final lastSeenStr = lastSeen != null
        ? DateFormat('dd MMM HH:mm').format(lastSeen.toDate())
        : '—';
    final band = data['last_frequency_band'] as String? ?? '';
    final freqMhz = data['last_frequency_mhz'];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bssid,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                if (band.isNotEmpty)
                  Text('$band${freqMhz != null ? '  ($freqMhz MHz)' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (signalPercent != null)
                      Text(
                        "$signalPercent% (${signalDbm ?? '?'} dBm)",
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    if (signalPercent != null && scannedBy.isNotEmpty)
                      const Text('  •  ',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    if (scannedBy.isNotEmpty)
                      Flexible(
                        child: Text(
                          'by $scannedBy',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                Text(
                  'Last seen: $lastSeenStr',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Register', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
