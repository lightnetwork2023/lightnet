import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../services/FieldRegistrationService.dart';
import '../theme/app_theme.dart';
import '../controllers/ApiService.dart';

// ─── Equipment metadata ────────────────────────────────────────────────────

class EquipmentMeta {
  static const List<Map<String, dynamic>> types = [
    {'type': 'sim_card_router', 'label': 'SIM Card Router',      'icon': Icons.router},
    {'type': 'mikrotik',        'label': 'MikroTik',              'icon': Icons.dns},
    {'type': 'unifi_ap',        'label': 'UniFi Access Point',    'icon': Icons.wifi_tethering},
    {'type': 'nokia',           'label': 'Nokia',                 'icon': Icons.router},
    {'type': 'other_router',    'label': 'Other Router',          'icon': Icons.router},
    {'type': 'access_point',    'label': 'Access Point',          'icon': Icons.wifi},
    {'type': 'dish_receiver',           'label': 'Dish Receiver',              'icon': Icons.satellite_alt},
    {'type': 'link',                    'label': 'Link',                       'icon': Icons.cable},
    {'type': 'omnidirectional_antenna', 'label': 'Omnidirectional Antenna',    'icon': Icons.cell_tower},
    {'type': 'sector_antenna',          'label': 'Sector Antenna',             'icon': Icons.settings_input_antenna},
  ];

  static String labelFor(String type) =>
      (types.firstWhere((t) => t['type'] == type,
          orElse: () => {'label': type})['label'] as String?) ?? type;

  static IconData iconFor(String type) =>
      (types.firstWhere((t) => t['type'] == type,
          orElse: () => {'icon': Icons.device_unknown})['icon'] as IconData?) ??
      Icons.device_unknown;
}

// ─── List Screen ───────────────────────────────────────────────────────────

class FieldDetailsScreen extends StatelessWidget {
  final String ownerId;
  final String ownerName;
  final String ownerRole;
  final String ownerLocation;
  final bool canEdit;
  final bool canDelete;

  const FieldDetailsScreen({
    Key? key,
    required this.ownerId,
    required this.ownerName,
    required this.ownerRole,
    required this.ownerLocation,
    this.canEdit = true,
    this.canDelete = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$ownerName – Field Details'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FieldRegistrationFormScreen(
              ownerId: ownerId,
              ownerName: ownerName,
              ownerRole: ownerRole,
              ownerLocation: ownerLocation,
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Registration'),
        backgroundColor: AppTheme.primaryColor,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FieldRegistrationService.streamForOwner(ownerId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          docs.sort((a, b) {
            final aTs = a.data()['created_at'];
            final bTs = b.data()['created_at'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No registrations yet',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 8),
                  Text('Tap + to add one', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              return _RegistrationCard(
                docId: d.id,
                data: data,
                ownerId: ownerId,
                ownerName: ownerName,
                ownerRole: ownerRole,
                ownerLocation: ownerLocation,
                canEdit: canEdit,
                canDelete: canDelete,
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Registration Card ─────────────────────────────────────────────────────

class _RegistrationCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final String ownerId;
  final String ownerName;
  final String ownerRole;
  final String ownerLocation;
  final bool canEdit;
  final bool canDelete;

  const _RegistrationCard({
    required this.docId,
    required this.data,
    required this.ownerId,
    required this.ownerName,
    required this.ownerRole,
    required this.ownerLocation,
    this.canEdit = true,
    this.canDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    final equipment =
        (data['equipment'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final phones =
        (data['phone_numbers'] as List?)?.cast<String>() ?? [];
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canEdit
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FieldRegistrationFormScreen(
                      existingId: docId,
                      existingData: data,
                      ownerId: ownerId,
                      ownerName: ownerName,
                      ownerRole: ownerRole,
                      ownerLocation: ownerLocation,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data['client_name'] as String? ?? 'Unnamed Client',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (canDelete)
                    PopupMenuButton<String>(
                      onSelected: (val) async {
                        if (val == 'delete') {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete Registration'),
                              content: const Text('Are you sure?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await FieldRegistrationService.delete(docId);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
                ],
              ),
              if ((data['physical_location'] as String?)?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, size: 14,
                          color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(data['physical_location'] as String,
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              if (phones.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(phones.join(', '),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              if (lat != null && lng != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.gps_fixed, size: 14,
                          color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                            color: Colors.blue, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              if (equipment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _buildEquipmentChips(equipment),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEquipmentChips(List<Map<String, dynamic>> equipment) {
    final counts = <String, int>{};
    for (final e in equipment) {
      final t = e['type'] as String? ?? 'unknown';
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts.entries.map((entry) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(EquipmentMeta.iconFor(entry.key),
                size: 12, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(
              '${entry.value}× ${EquipmentMeta.labelFor(entry.key)}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.primaryColor),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ─── Registration Form Screen ──────────────────────────────────────────────

class FieldRegistrationFormScreen extends StatefulWidget {
  final String? existingId;
  final Map<String, dynamic>? existingData;
  final String ownerId;
  final String ownerName;
  final String ownerRole;
  final String ownerLocation;

  const FieldRegistrationFormScreen({
    Key? key,
    this.existingId,
    this.existingData,
    required this.ownerId,
    required this.ownerName,
    required this.ownerRole,
    required this.ownerLocation,
  }) : super(key: key);

  @override
  State<FieldRegistrationFormScreen> createState() =>
      _FieldRegistrationFormScreenState();
}

class _FieldRegistrationFormScreenState
    extends State<FieldRegistrationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _physicalLocationCtrl = TextEditingController();
  final _clientNameCtrl = TextEditingController();
  final _monthlyDeductionCtrl = TextEditingController();

  List<TextEditingController> _phoneCtrl = [TextEditingController()];
  double? _latitude;
  double? _longitude;
  bool _gettingGPS = false;
  bool _saving = false;

  List<Map<String, dynamic>> _equipment = [];
  List<Map<String, dynamic>> _mikrotikDevices = [];
  bool _mikrotikLoaded = false;
  List<dynamic> _unifiAPs = [];
  bool _unifiLoaded = false;
  bool _unifiLoading = false;
  List<Map<String, dynamic>> _simCards = [];
  bool _simCardsLoaded = false;
  bool _simCardsLoading = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existingData;
    if (d != null) {
      _physicalLocationCtrl.text = d['physical_location'] as String? ?? '';
      _clientNameCtrl.text = d['client_name'] as String? ?? '';
      _monthlyDeductionCtrl.text =
          d['monthly_deduction']?.toString() ?? '';
      _latitude = (d['latitude'] as num?)?.toDouble();
      _longitude = (d['longitude'] as num?)?.toDouble();
      final phones =
          (d['phone_numbers'] as List?)?.cast<String>() ?? [];
      if (phones.isNotEmpty) {
        _phoneCtrl =
            phones.map((p) => TextEditingController(text: p)).toList();
      }
      _equipment = List<Map<String, dynamic>>.from(
        (d['equipment'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)) ??
            [],
      );
    }
  }

  @override
  void dispose() {
    _physicalLocationCtrl.dispose();
    _clientNameCtrl.dispose();
    _monthlyDeductionCtrl.dispose();
    for (final c in _phoneCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmtBytes(int? bytes) {
    if (bytes == null || bytes == 0) return '0 B';
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  static String _fmtBps(num? bps) {
    if (bps == null || bps == 0) return '0 bps';
    if (bps < 1000) return '${bps.toStringAsFixed(0)} bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)} Kbps';
    return '${(bps / 1000000).toStringAsFixed(2)} Mbps';
  }

  Future<void> _loadMikrotikDevices(StateSetter setDlg) async {
    if (_mikrotikLoaded) return;
    setDlg(() {});
    try {
      final snap = await FirebaseFirestore.instance
          .collection('mikrotik_devices')
          .get();
      if (mounted) {
        setState(() {
          _mikrotikDevices =
              snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _mikrotikLoaded = true;
        });
        setDlg(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() => _mikrotikLoaded = true);
        setDlg(() {});
      }
    }
  }

  Future<void> _loadSimCards(StateSetter setDlg) async {
    if (_simCardsLoaded || _simCardsLoading) return;
    setState(() => _simCardsLoading = true);
    setDlg(() {});
    try {
      final snap = await FirebaseFirestore.instance
          .collection('simcards')
          .get();
      if (mounted) {
        setState(() {
          _simCards = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
          _simCardsLoaded = true;
          _simCardsLoading = false;
        });
        setDlg(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _simCardsLoaded = true;
          _simCardsLoading = false;
        });
        setDlg(() {});
      }
    }
  }

  Future<void> _loadUnifiAPs(StateSetter setDlg) async {
    if (_unifiLoaded || _unifiLoading) return;
    setState(() => _unifiLoading = true);
    setDlg(() {});
    try {
      final aps = await ApiService.getUnifiAPs();
      if (mounted) {
        setState(() {
          _unifiAPs = aps;
          _unifiLoaded = true;
          _unifiLoading = false;
        });
        setDlg(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unifiLoaded = true;
          _unifiLoading = false;
        });
        setDlg(() {});
      }
    }
  }

  Future<void> _captureGPS() async {
    setState(() => _gettingGPS = true);
    try {
      bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location services disabled. Please enable GPS.');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          _showSnack('Location permission denied.');
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        _showSnack(
            'Location permanently denied. Enable in device settings.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        _showSnack(
            'GPS captured: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}');
      }
    } catch (e) {
      _showSnack('Failed to get GPS: $e');
    } finally {
      if (mounted) setState(() => _gettingGPS = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _pickSimCard(
    BuildContext ctx,
    List<Map<String, dynamic>> simCards,
    String? current,
  ) async {
    if (simCards.isEmpty) {
      _showSnack('No SIM cards found. Add from Simcards management.');
      return null;
    }
    String query = '';
    return showModalBottomSheet<String>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bsCtx) => StatefulBuilder(
        builder: (bsCtx, setBs) {
          final filtered = query.isEmpty
              ? simCards
              : simCards.where((s) {
                  final msisdn =
                      (s['msisdn'] as String? ?? '').toLowerCase();
                  final name =
                      (s['customer_name'] as String? ?? '').toLowerCase();
                  final q = query.toLowerCase();
                  return msisdn.contains(q) || name.contains(q);
                }).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, sc) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.sim_card,
                        color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    const Text('Select SIM Card',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bsCtx)),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by number or name…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setBs(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No results',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            controller: sc,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final sim = filtered[i];
                              final msisdn =
                                  sim['msisdn'] as String? ?? '';
                              final custName =
                                  sim['customer_name'] as String? ?? '';
                              final loc =
                                  sim['location'] as String? ?? '';
                              final selected = current == msisdn;
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.sim_card,
                                    color: selected
                                        ? AppTheme.primaryColor
                                        : Colors.grey),
                                title: Text(msisdn,
                                    style: TextStyle(
                                        fontWeight: selected
                                            ? FontWeight.bold
                                            : FontWeight.normal)),
                                subtitle: Text([
                                  if (custName.isNotEmpty) custName,
                                  if (loc.isNotEmpty) loc,
                                ].join('  •  ')),
                                selected: selected,
                                selectedTileColor:
                                    AppTheme.primaryColor.withOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                onTap: () =>
                                    Navigator.pop(bsCtx, msisdn),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddEquipmentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Equipment Type',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            ...EquipmentMeta.types.map((t) => ListTile(
                  leading: Icon(t['icon'] as IconData,
                      color: AppTheme.primaryColor),
                  title: Text(t['label'] as String),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEquipmentFieldsDialog(
                        t['type'] as String, t['label'] as String);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showEquipmentFieldsDialog(
    String type,
    String label, [
    Map<String, dynamic>? existing,
    int? editIndex,
  ]) {
    final ctrls = <String, TextEditingController>{};
    String? mikrotikId = existing?['device_id'] as String?;
    String? mikrotikName = existing?['device_name'] as String?;
    String? mikrotikIp = existing?['ip_address'] as String?;
    String? unifiMac = existing?['ap_mac'] as String?;
    String? unifiName = existing?['ap_name'] as String?;
    String? unifiLocation = existing?['ap_location'] as String?;
    String? selectedSimMsisdn = existing?['sim_card_number'] as String?;

    if (type == 'sim_card_router') {
      ctrls['model'] =
          TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(
          text: existing?['serial_number'] as String? ?? '');
    } else if (type == 'link') {
      ctrls['model'] =
          TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(
          text: existing?['serial_number'] as String? ?? '');
      ctrls['ip'] = TextEditingController(
          text: existing?['ip_address'] as String? ?? '');
      ctrls['azimuth'] = TextEditingController(
          text: existing?['azimuth']?.toString() ?? '');
    } else if (type == 'dish_receiver') {
      ctrls['model'] =
          TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(
          text: existing?['serial_number'] as String? ?? '');
      ctrls['ip'] = TextEditingController(
          text: existing?['ip_address'] as String? ?? '');
      ctrls['azimuth'] = TextEditingController(
          text: existing?['azimuth']?.toString() ?? '');
    } else if (type == 'other_router') {
      ctrls['model'] =
          TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(
          text: existing?['serial_number'] as String? ?? '');
      ctrls['ip'] = TextEditingController(
          text: existing?['ip_address'] as String? ?? '');
    } else if (type == 'omnidirectional_antenna') {
      ctrls['model'] = TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(text: existing?['serial_number'] as String? ?? '');
      ctrls['height'] = TextEditingController(text: existing?['height']?.toString() ?? '');
      ctrls['frequency'] = TextEditingController(text: existing?['frequency']?.toString() ?? '');
    } else if (type == 'sector_antenna') {
      ctrls['model'] = TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(text: existing?['serial_number'] as String? ?? '');
      ctrls['height'] = TextEditingController(text: existing?['height']?.toString() ?? '');
      ctrls['frequency'] = TextEditingController(text: existing?['frequency']?.toString() ?? '');
      ctrls['azimuth'] = TextEditingController(text: existing?['azimuth']?.toString() ?? '');
      ctrls['beamwidth'] = TextEditingController(text: existing?['beamwidth']?.toString() ?? '');
    } else if (type != 'mikrotik') {
      ctrls['model'] =
          TextEditingController(text: existing?['model'] as String? ?? '');
      ctrls['serial'] = TextEditingController(
          text: existing?['serial_number'] as String? ?? '');
    }

    // ── Home client live lookup state ───────────────────────────────────────
    Map<String, dynamic>? homeClient;
    bool homeClientLoading = false;
    String lastSearchedIp = '';
    Timer? ipLookupTimer;

    void lookupByIp(String ip, StateSetter setDlg) {
      ipLookupTimer?.cancel();
      final trimmed = ip.trim();
      if (trimmed.length < 7) {
        setDlg(() { homeClient = null; homeClientLoading = false; lastSearchedIp = ''; });
        return;
      }
      setDlg(() => homeClientLoading = true);
      ipLookupTimer = Timer(const Duration(milliseconds: 800), () async {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('home_clients')
              .where('ip', isEqualTo: trimmed)
              .limit(1)
              .get();
          setDlg(() {
            homeClient = snap.docs.isNotEmpty ? snap.docs.first.data() : null;
            homeClientLoading = false;
            lastSearchedIp = trimmed;
          });
        } catch (_) {
          setDlg(() { homeClient = null; homeClientLoading = false; lastSearchedIp = trimmed; });
        }
      });
    }
    // ─────────────────────────────────────────────────────────────────────────

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          // Trigger lazy loading
          if (type == 'mikrotik' && !_mikrotikLoaded) {
            _loadMikrotikDevices(setDlg);
          } else if (type == 'unifi_ap' && !_unifiLoaded && !_unifiLoading) {
            _loadUnifiAPs(setDlg);
          } else if (type == 'sim_card_router' && !_simCardsLoaded && !_simCardsLoading) {
            _loadSimCards(setDlg);
          }
          return AlertDialog(
          title: Text(editIndex != null ? 'Edit $label' : 'Add $label'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (type == 'sim_card_router') ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Router Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _simCardsLoading
                        ? null
                        : () async {
                            final picked = await _pickSimCard(
                                context, _simCards, selectedSimMsisdn);
                            if (picked != null) {
                              setDlg(() => selectedSimMsisdn = picked);
                            }
                          },
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'SIM Card',
                        border: const OutlineInputBorder(),
                        suffixIcon: _simCardsLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ))
                            : const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        selectedSimMsisdn?.isNotEmpty == true
                            ? selectedSimMsisdn!
                            : 'Select SIM card…',
                        style: TextStyle(
                          color: selectedSimMsisdn?.isNotEmpty == true
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ] else if (type == 'unifi_ap') ...[
                  if (_unifiLoading)
                    const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ))
                  else if (_unifiAPs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                          'No UniFi APs found.\nAdd from UniFi AP Management.',
                          textAlign: TextAlign.center),
                    )
                  else
                    ..._unifiAPs.map((ap) {
                      final mac = ap['ap_mac'] as String? ?? '';
                      final name = ap['ap_name'] as String? ?? 'Unknown';
                      final loc = ap['location'] as String? ?? '';
                      final selected = unifiMac == mac;
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.wifi_tethering,
                            color: selected
                                ? AppTheme.primaryColor
                                : Colors.grey),
                        title: Text(name),
                        subtitle: Text('$mac  •  $loc'),
                        selected: selected,
                        selectedTileColor:
                            AppTheme.primaryColor.withOpacity(0.1),
                        onTap: () => setDlg(() {
                          unifiMac = mac;
                          unifiName = name;
                          unifiLocation = loc;
                        }),
                      );
                    }),
                ] else if (type == 'mikrotik') ...[
                  if (!_mikrotikLoaded)
                    const Center(child: CircularProgressIndicator())
                  else if (_mikrotikDevices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                          'No MikroTik devices found.\nAdd from MikroTik Monitoring.',
                          textAlign: TextAlign.center),
                    )
                  else
                    ..._mikrotikDevices.map((device) {
                      final selected = mikrotikId == device['id'];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.dns,
                            color: selected
                                ? AppTheme.primaryColor
                                : Colors.grey),
                        title: Text(
                            device['name'] as String? ?? 'Unknown'),
                        subtitle: Text(
                            device['ipAddress'] as String? ?? ''),
                        selected: selected,
                        selectedTileColor:
                            AppTheme.primaryColor.withOpacity(0.1),
                        onTap: () => setDlg(() {
                          mikrotikId = device['id'] as String;
                          mikrotikName =
                              device['name'] as String?;
                          mikrotikIp =
                              device['ipAddress'] as String?;
                        }),
                      );
                    }),
                ] else if (type == 'link') ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['ip'],
                      keyboardType: TextInputType.number,
                      onChanged: (v) => lookupByIp(v, setDlg),
                      decoration: const InputDecoration(
                          labelText: 'IP Address',
                          hintText: 'e.g. 192.168.1.10',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['azimuth'],
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Azimuth / Direction Angle (°)',
                          hintText: 'e.g. 270',
                          border: OutlineInputBorder())),
                ] else if (type == 'dish_receiver') ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['ip'],
                      keyboardType: TextInputType.number,
                      onChanged: (v) => lookupByIp(v, setDlg),
                      decoration: const InputDecoration(
                          labelText: 'IP Address',
                          hintText: 'e.g. 192.168.1.20',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['azimuth'],
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Azimuth / Direction Angle (°)',
                          hintText: 'e.g. 180',
                          border: OutlineInputBorder())),
                ] else if (type == 'other_router') ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['ip'],
                      keyboardType: TextInputType.number,
                      onChanged: (v) => lookupByIp(v, setDlg),
                      decoration: const InputDecoration(
                          labelText: 'IP Address',
                          hintText: 'e.g. 192.168.1.1',
                          border: OutlineInputBorder())),
                ] else if (type == 'omnidirectional_antenna') ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['height'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Height (m)',
                          hintText: 'e.g. 15',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['frequency'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Frequency (MHz)',
                          hintText: 'e.g. 2400',
                          border: OutlineInputBorder())),
                ] else if (type == 'sector_antenna') ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['height'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Height (m)',
                          hintText: 'e.g. 15',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['frequency'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Frequency (MHz)',
                          hintText: 'e.g. 5800',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['azimuth'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Azimuth (°)',
                          hintText: 'e.g. 90',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['beamwidth'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Beamwidth (°)',
                          hintText: 'e.g. 60',
                          border: OutlineInputBorder())),
                ] else ...[
                  TextField(
                      controller: ctrls['model'],
                      decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                      controller: ctrls['serial'],
                      decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          border: OutlineInputBorder())),
                ],
                // ── Home client lookup result ─────────────────────────────
                if (homeClientLoading && ctrls.containsKey('ip')) ...[
                  const SizedBox(height: 10),
                  const Row(children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Looking up home client…',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                ] else if (!homeClientLoading && homeClient != null) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (_) {
                    final name    = homeClient!['name'] as String? ?? '—';
                    final lastTs  = homeClient!['last_seen'] as Timestamp?;
                    final isOnline = lastTs != null &&
                        DateTime.now().difference(lastTs.toDate()).inMinutes < 6;
                    final dlBps   = homeClient!['download_bps_5min'] as num?;
                    final todayDl = homeClient!['today_download_bytes'] as int?;
                    final todayUl = homeClient!['today_upload_bytes'] as int?;
                    final monDl   = homeClient!['month_download_bytes'] as int?;
                    final monUl   = homeClient!['month_upload_bytes'] as int?;
                    final router  = homeClient!['router_name'] as String?;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isOnline ? Colors.green.shade200 : Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: isOnline ? Colors.green : Colors.grey,
                                shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                            const Spacer(),
                            Text(isOnline ? 'ONLINE' : 'OFFLINE',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isOnline ? Colors.green : Colors.grey)),
                          ]),
                          if (router != null) ...[
                            const SizedBox(height: 2),
                            Text('Router: $router',
                                style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                          if (dlBps != null && dlBps > 0) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.speed_rounded, size: 12, color: Colors.blue),
                              const SizedBox(width: 4),
                              Text('Current: ${_fmtBps(dlBps)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.blue)),
                            ]),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Today  ↓${_fmtBytes(todayDl)}  ↑${_fmtBytes(todayUl)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                          ),
                          Text(
                            'Month  ↓${_fmtBytes(monDl)}  ↑${_fmtBytes(monUl)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    );
                  }),
                ] else if (!homeClientLoading && lastSearchedIp.length >= 7
                    && homeClient == null && ctrls.containsKey('ip')) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline, size: 13, color: Colors.orange),
                      SizedBox(width: 6),
                      Text('No home client found for this IP',
                          style: TextStyle(fontSize: 11, color: Colors.orange)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ipLookupTimer?.cancel();
                for (final c in ctrls.values) c.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white),
              onPressed: () {
                ipLookupTimer?.cancel();
                if (type == 'mikrotik' && mikrotikId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Please select a MikroTik device.')));
                  return;
                }
                if (type == 'unifi_ap' && unifiMac == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Please select a UniFi AP.')));
                  return;
                }
                final item = <String, dynamic>{'type': type, 'label': label};
                if (type == 'sim_card_router') {
                  if (selectedSimMsisdn == null || selectedSimMsisdn!.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please select a SIM card.')));
                    return;
                  }
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                  item['sim_card_number'] = selectedSimMsisdn!;
                } else if (type == 'mikrotik') {
                  item['device_id'] = mikrotikId;
                  item['device_name'] = mikrotikName;
                  item['ip_address'] = mikrotikIp;
                } else if (type == 'unifi_ap') {
                  item['ap_mac'] = unifiMac;
                  item['ap_name'] = unifiName;
                  item['ap_location'] = unifiLocation;
                } else if (type == 'link') {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                  item['ip_address'] = ctrls['ip']!.text.trim();
                  item['azimuth'] =
                      double.tryParse(ctrls['azimuth']!.text.trim());
                } else if (type == 'dish_receiver') {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                  item['ip_address'] = ctrls['ip']!.text.trim();
                  item['azimuth'] =
                      double.tryParse(ctrls['azimuth']!.text.trim());
                } else if (type == 'other_router') {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                  item['ip_address'] = ctrls['ip']!.text.trim();
                } else if (type == 'omnidirectional_antenna') {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                  item['height'] = double.tryParse(ctrls['height']!.text.trim());
                  item['frequency'] = double.tryParse(ctrls['frequency']!.text.trim());
                } else if (type == 'sector_antenna') {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                  item['height'] = double.tryParse(ctrls['height']!.text.trim());
                  item['frequency'] = double.tryParse(ctrls['frequency']!.text.trim());
                  item['azimuth'] = double.tryParse(ctrls['azimuth']!.text.trim());
                  item['beamwidth'] = double.tryParse(ctrls['beamwidth']!.text.trim());
                } else {
                  item['model'] = ctrls['model']!.text.trim();
                  item['serial_number'] = ctrls['serial']!.text.trim();
                }
                setState(() {
                  if (editIndex != null) {
                    _equipment[editIndex] = item;
                  } else {
                    _equipment.add(item);
                  }
                });
                for (final c in ctrls.values) c.dispose();
                Navigator.pop(ctx);
              },
              child: Text(editIndex != null ? 'Update' : 'Add'),
            ),
          ],
          );
        },
      ),
    );
  }

  String _equipmentSubtitle(Map<String, dynamic> eq) {
    final type = eq['type'] as String? ?? '';
    if (type == 'sim_card_router') {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if ((eq['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${eq['serial_number']}',
        if ((eq['sim_card_number'] as String?)?.isNotEmpty == true)
          'SIM: ${eq['sim_card_number']}',
      ].join(' • ');
    } else if (type == 'mikrotik') {
      return '${eq['device_name'] ?? 'Unknown'} (${eq['ip_address'] ?? ''})';
    } else if (type == 'unifi_ap') {
      return '${eq['ap_name'] ?? 'Unknown'}  •  MAC: ${eq['ap_mac'] ?? ''}';
    } else if (type == 'link') {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if ((eq['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${eq['serial_number']}',
        if ((eq['ip_address'] as String?)?.isNotEmpty == true)
          'IP: ${eq['ip_address']}',
        if (eq['azimuth'] != null) 'Azimuth: ${eq['azimuth']}°',
      ].join(' • ');
    } else if (type == 'dish_receiver') {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if ((eq['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${eq['serial_number']}',
        if ((eq['ip_address'] as String?)?.isNotEmpty == true)
          'IP: ${eq['ip_address']}',
        if (eq['azimuth'] != null) 'Azimuth: ${eq['azimuth']}°',
      ].join(' • ');
    } else if (type == 'other_router') {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if ((eq['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${eq['serial_number']}',
        if ((eq['ip_address'] as String?)?.isNotEmpty == true)
          'IP: ${eq['ip_address']}',
      ].join(' • ');
    } else if (type == 'omnidirectional_antenna') {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if (eq['height'] != null) 'Height: ${eq['height']}m',
        if (eq['frequency'] != null) 'Freq: ${eq['frequency']}MHz',
      ].join(' • ');
    } else if (type == 'sector_antenna') {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if (eq['height'] != null) 'Height: ${eq['height']}m',
        if (eq['frequency'] != null) 'Freq: ${eq['frequency']}MHz',
        if (eq['azimuth'] != null) 'Azimuth: ${eq['azimuth']}°',
        if (eq['beamwidth'] != null) 'BW: ${eq['beamwidth']}°',
      ].join(' • ');
    } else {
      return [
        if ((eq['model'] as String?)?.isNotEmpty == true)
          'Model: ${eq['model']}',
        if ((eq['serial_number'] as String?)?.isNotEmpty == true)
          'S/N: ${eq['serial_number']}',
      ].join(' • ');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final phones = _phoneCtrl
          .map((c) => c.text.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final data = <String, dynamic>{
        'owner_id': widget.ownerId,
        'owner_name': widget.ownerName,
        'owner_role': widget.ownerRole,
        'location': widget.ownerLocation,
        'physical_location': _physicalLocationCtrl.text.trim(),
        'client_name': _clientNameCtrl.text.trim(),
        'phone_numbers': phones,
        'equipment': _equipment,
      };
      if (_latitude != null) data['latitude'] = _latitude;
      if (_longitude != null) data['longitude'] = _longitude;
      if (widget.ownerRole == 'superagent') {
        data['monthly_deduction'] =
            double.tryParse(_monthlyDeductionCtrl.text.trim()) ?? 0.0;
      }

      if (widget.existingId != null) {
        await FieldRegistrationService.update(widget.existingId!, data);
      } else {
        await FieldRegistrationService.add(data);
      }
      if (mounted) {
        _showSnack(widget.existingId != null
            ? 'Registration updated!'
            : 'Registration saved!');
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.textPrimary)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Container(height: 1, color: Colors.grey.shade300)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Registration' : 'New Registration'),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text('Save',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Client Info ───────────────────────────────────────────
            _sectionHeader(
                'Client Information', Icons.person_pin_circle_outlined),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clientNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Client Name *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _physicalLocationCtrl,
              decoration: const InputDecoration(
                labelText: 'Physical Location *  (e.g. Mbagala Zakiem)',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),

            // ── Phone Numbers ─────────────────────────────────────────
            _sectionHeader('Phone Numbers', Icons.phone_outlined),
            const SizedBox(height: 12),
            ..._phoneCtrl.asMap().entries.map((entry) {
              final idx = entry.key;
              final ctrl = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: ctrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone ${idx + 1}',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (idx > 0)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () {
                          ctrl.dispose();
                          setState(() => _phoneCtrl.removeAt(idx));
                        },
                      ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                    () => _phoneCtrl.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Add Phone'),
              ),
            ),
            const SizedBox(height: 20),

            // ── GPS Coordinates ───────────────────────────────────────
            _sectionHeader('GPS Coordinates', Icons.gps_fixed),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _latitude != null && _longitude != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Lat: ${_latitude!.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500)),
                              Text(
                                  'Lng: ${_longitude!.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500)),
                            ],
                          )
                        : const Text('No coordinates yet',
                            style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _gettingGPS ? null : _captureGPS,
                    icon: _gettingGPS
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    label: Text(
                        _gettingGPS ? 'Getting...' : 'Capture GPS'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Monthly Deduction (SuperAgent only) ───────────────────
            if (widget.ownerRole == 'superagent') ...[
              _sectionHeader(
                  'Monthly Deduction', Icons.remove_circle_outline),
              const SizedBox(height: 12),
              TextFormField(
                controller: _monthlyDeductionCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monthly Deduction (TZS)',
                  hintText: 'Amount deducted from commission for SIM line costs',
                  prefixIcon: Icon(Icons.money_off_outlined),
                  prefixText: 'TZS ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Equipment ─────────────────────────────────────────────
            _sectionHeader(
                'Equipment', Icons.devices_other_outlined),
            const SizedBox(height: 12),
            if (_equipment.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('No equipment added yet',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            ..._equipment.asMap().entries.map((entry) {
              final idx = entry.key;
              final eq = entry.value;
              final type = eq['type'] as String? ?? 'unknown';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: Icon(EquipmentMeta.iconFor(type),
                      color: AppTheme.primaryColor),
                  title: Text(EquipmentMeta.labelFor(type),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_equipmentSubtitle(eq)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: Colors.blue),
                        onPressed: () => _showEquipmentFieldsDialog(
                            type,
                            EquipmentMeta.labelFor(type),
                            eq,
                            idx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: () => setState(
                            () => _equipment.removeAt(idx)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _showAddEquipmentSheet,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add Equipment'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
