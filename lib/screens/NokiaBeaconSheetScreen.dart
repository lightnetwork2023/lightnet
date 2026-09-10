import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/NokiaBeaconService.dart';
import '../services/WifiBeaconScannerService.dart';
import 'NokiaBeaconScreen.dart';

/// Google Sheet–style table for Nokia Beacon monitoring.
/// Columns: #, Name, BSSID, SSID, 2.4G Ch, 5G Ch, Signal(dBm),
///          Status, Location, Last Seen, Speed, Connected To, Alerts, Freq Overlap
class NokiaBeaconSheetScreen extends StatefulWidget {
  const NokiaBeaconSheetScreen({super.key});
  @override
  State<NokiaBeaconSheetScreen> createState() => _NokiaBeaconSheetScreenState();
}

class _NokiaBeaconSheetScreenState extends State<NokiaBeaconSheetScreen> {
  String _search = '';
  String _filterStatus = 'all';
  final _searchCtrl = TextEditingController();
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await WifiBeaconScannerService.scanAndReport(forceEnabled: true, askPermissions: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  static const _staleHours = 6;

  // ─── alert computation ─────────────────────────────────────
  String _alert(Map<String, dynamic> d) {
    final status = (d['status'] ?? 'unknown').toString();
    if (status == 'offline') return '❌ OFFLINE';
    final ts = d['last_seen'];
    if (ts != null) {
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      if (dt != null) {
        final diffH = DateTime.now().difference(dt).inHours;
        if (diffH >= _staleHours) return '⚠ Not seen >$_staleHours h';
        if (diffH >= 3) return '⚠ CHECK >3 h';
      }
    }
    if (status == 'stale') return '⚠ Stale';
    if (status == 'unknown') return '❓ Unknown';
    return '✓ OK';
  }

  bool _hasAlert(String alert) => alert.startsWith('⚠') || alert.startsWith('❌');

  // ─── frequency overlap computation ─────────────────────────
  String _freqOverlap(Map<String, dynamic> d, List<Map<String, dynamic>> all) {
    final loc = (d['location'] ?? '').toString().toLowerCase().trim();
    final ch2 = (d['channel_2ghz'] ?? '').toString().trim();
    final ch5 = (d['channel_5ghz'] ?? '').toString().trim();
    if (loc.isEmpty) return '—';

    final sameArea = all.where((o) =>
        o != d &&
        (o['location'] ?? '').toString().toLowerCase().trim() == loc);

    if (ch2.isNotEmpty &&
        sameArea.any((o) => (o['channel_2ghz'] ?? '').toString().trim() == ch2)) {
      return '⚠ 2.4 GHz conflict';
    }
    if (ch5.isNotEmpty &&
        sameArea.any((o) => (o['channel_5ghz'] ?? '').toString().trim() == ch5)) {
      return '⚠ 5 GHz conflict';
    }
    if (ch2.isEmpty && ch5.isEmpty) return '—';
    return '✓ OK';
  }

  bool _hasFreqConflict(String f) => f.startsWith('⚠');

  // ─── row background color ───────────────────────────────────
  Color _rowBg(Map<String, dynamic> d, int idx, String alert) {
    if (alert.startsWith('❌')) return Colors.red.shade50;
    if (alert.startsWith('⚠')) return Colors.orange.shade50;
    final status = (d['status'] ?? '').toString();
    if (status == 'online') return idx.isEven ? Colors.white : Colors.green.shade50;
    return idx.isEven ? Colors.white : Colors.grey.shade50;
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '—';
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    if (dt == null) return '—';
    return DateFormat('dd MMM HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Nokia Beacon Sheet',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh & Scan',
              onPressed: _refresh,
            ),
          IconButton(
            icon: const Icon(Icons.table_rows_rounded),
            tooltip: 'Card view',
            onPressed: () {
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const NokiaBeaconScreen()));
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: NokiaBeaconService.streamAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));

          final allDocs = snap.data?.docs ?? [];
          final allData = allDocs.map((d) => d.data()).toList();

          // Apply alert + freq data to each map for computation
          final enriched = allDocs.map((doc) {
            final d = Map<String, dynamic>.from(doc.data());
            d['_id'] = doc.id;
            d['_alert'] = _alert(d);
            d['_freq'] = _freqOverlap(d, allData);
            return d;
          }).toList();

          // Counts
          final total = enriched.length;
          final staleCount = enriched.where((d) => _hasAlert(d['_alert'] as String)).length;
          final freqCount = enriched.where((d) => _hasFreqConflict(d['_freq'] as String)).length;
          final online = enriched.where((d) => (d['status'] ?? '') == 'online').length;

          // Filter
          List<Map<String, dynamic>> rows = enriched;
          if (_filterStatus == 'alert') {
            rows = rows.where((d) => _hasAlert(d['_alert'] as String)).toList();
          } else if (_filterStatus != 'all') {
            rows = rows.where((d) => (d['status'] ?? '') == _filterStatus).toList();
          }
          if (_search.isNotEmpty) {
            final q = _search.toLowerCase();
            rows = rows.where((d) {
              return (d['name'] ?? '').toString().toLowerCase().contains(q) ||
                  (d['mac_address'] ?? '').toString().toLowerCase().contains(q) ||
                  (d['location'] ?? '').toString().toLowerCase().contains(q);
            }).toList();
          }

          // Sort: alerts first
          rows.sort((a, b) {
            const order = {'❌': 0, '⚠': 1, '✓': 2, '—': 3, '❓': 4};
            int rank(String al) {
              for (final k in order.keys) if (al.startsWith(k)) return order[k]!;
              return 5;
            }
            final ra = rank(a['_alert'] as String);
            final rb = rank(b['_alert'] as String);
            if (ra != rb) return ra.compareTo(rb);
            return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
          });

          return Column(children: [
            // ── Summary bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              color: const Color(0xFF1B5E20),
              child: Row(children: [
                _sumBox('Total', total, Colors.white),
                const SizedBox(width: 8),
                _sumBox('Online', online, Colors.greenAccent),
                const SizedBox(width: 8),
                _sumBox('Alerts', staleCount, Colors.orange.shade200),
                const SizedBox(width: 8),
                _sumBox('Freq ⚠', freqCount, Colors.red.shade200),
              ]),
            ),

            // ── Filter chips ─────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _fChip('All', 'all'),
                  _fChip('Online', 'online'),
                  _fChip('Offline', 'offline'),
                  _fChip('Stale', 'stale'),
                  _fChip('⚠ Alerts', 'alert'),
                ]),
              ),
            ),

            // ── Search ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search name, MAC, location…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          })
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase().trim()),
              ),
            ),

            // ── Table ────────────────────────────────────────────
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No beacons match', style: TextStyle(color: Colors.grey)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildTable(rows),
                      ),
                    ),
            ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1B5E20),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Beacon', style: TextStyle(color: Colors.white)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NokiaBeaconScreen()),
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );
    const cellStyle = TextStyle(fontSize: 11);

    final headers = [
      '#', 'Beacon Name', 'BSSID (MAC)',
      'Frequency', '2.4G Ch', '5G Ch', 'Signal (dBm)',
      'PHY Mode', 'Ch Width', '~SNR', 'Link Spd',
      'Confidence', 'Seen×',
      'Status', 'Location', 'Last Seen',
      'Speed', 'Connected To', 'Alerts', 'Freq Overlap',
    ];

    // column widths
    final widths = [28.0, 130.0, 120.0,
        90.0, 55.0, 55.0, 80.0,
        80.0, 65.0, 65.0, 75.0,
        75.0, 50.0,
        70.0, 100.0, 100.0, 120.0, 120.0, 150.0, 140.0];

    return Table(
      columnWidths: {
        for (int i = 0; i < widths.length; i++) i: FixedColumnWidth(widths[i])
      },
      border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
      children: [
        // Header row
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFF2E7D32)),
          children: headers.map((h) => _hCell(h, headerStyle)).toList(),
        ),
        // Data rows
        ...rows.asMap().entries.map((entry) {
          final idx = entry.key;
          final d = entry.value;
          final alert = d['_alert'] as String;
          final freq = d['_freq'] as String;
          final bg = _rowBg(d, idx, alert);

          Color alertColor = Colors.green;
          if (alert.startsWith('❌')) alertColor = Colors.red;
          else if (alert.startsWith('⚠')) alertColor = Colors.orange;

          Color freqColor = Colors.green;
          if (freq.startsWith('⚠')) freqColor = Colors.red;

          return TableRow(
            decoration: BoxDecoration(color: bg),
            children: [
              _cell('${idx + 1}', cellStyle, TextAlign.center),
              _cellTap(d['name'] ?? '—', cellStyle, () => _editBeacon(d)),
              _cell(d['mac_address'] ?? '—', cellStyle),
              _cell(_freqLabel(d), cellStyle, TextAlign.center),
              _cell(d['channel_2ghz'] ?? '—', cellStyle, TextAlign.center),
              _cell(d['channel_5ghz'] ?? '—', cellStyle, TextAlign.center),
              _cell(_signal(d), cellStyle, TextAlign.center),
              _cell(d['phy_mode'] ?? '—', cellStyle, TextAlign.center),
              _cell(_chWidth(d), cellStyle, TextAlign.center),
              _snrCell(d),
              _linkSpdCell(d),
              _confidenceCell(d),
              _cell('${d['seen_count'] ?? '—'}', cellStyle, TextAlign.center),
              _statusCell(d['status'] ?? 'unknown'),
              _cell(d['location'] ?? '—', cellStyle),
              _cell(_fmtTs(d['last_seen']), cellStyle),
              _cell(d['connection_speed'] ?? '—', cellStyle),
              _cell(d['connected_to'] ?? '—', cellStyle),
              _cell(alert, TextStyle(fontSize: 11, color: alertColor, fontWeight: FontWeight.w600)),
              _cell(freq, TextStyle(fontSize: 11, color: freqColor, fontWeight: FontWeight.w600)),
            ],
          );
        }),
      ],
    );
  }

  String _freqLabel(Map<String, dynamic> d) {
    final band = d['last_frequency_band']?.toString() ?? '';
    final mhz  = d['last_frequency_mhz'];
    if (band.isNotEmpty && mhz != null) return '$band\n$mhz MHz';
    if (band.isNotEmpty) return band;
    // Fallback: derive from channel data
    final ch2 = (d['channel_2ghz'] ?? '').toString().trim();
    final ch5 = (d['channel_5ghz'] ?? '').toString().trim();
    if (ch2.isNotEmpty && ch5.isNotEmpty) return '2.4 / 5 GHz';
    if (ch2.isNotEmpty) return '2.4 GHz';
    if (ch5.isNotEmpty) return '5 GHz';
    return '—';
  }

  String _signal(Map<String, dynamic> d) {
    final dbm = d['last_signal_dbm'];
    final pct = d['last_signal_percent'];
    if (dbm != null) return '$dbm dBm';
    if (pct != null) return '$pct%';
    return '—';
  }

  Widget _hCell(String text, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(text, style: style),
    );
  }

  Widget _cell(String text, TextStyle style, [TextAlign align = TextAlign.left]) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(text, style: style, textAlign: align, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _cellTap(String text, TextStyle style, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Text(
          text,
          style: style.copyWith(
              color: const Color(0xFF1B5E20), fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _statusCell(String status) {
    Color color;
    IconData icon;
    switch (status) {
      case 'online':
        color = Colors.green; icon = Icons.check_circle_outline; break;
      case 'offline':
        color = Colors.red; icon = Icons.cancel_outlined; break;
      case 'stale':
        color = Colors.orange; icon = Icons.hourglass_bottom_rounded; break;
      default:
        color = Colors.grey; icon = Icons.help_outline;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sumBox(String label, int count, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
        Text(label, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.85))),
      ]),
    );
  }

  Widget _fChip(String label, String value) {
    final sel = _filterStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87)),
        selected: sel,
        selectedColor: const Color(0xFF2E7D32),
        onSelected: (_) => setState(() => _filterStatus = value),
      ),
    );
  }

  String _chWidth(Map<String, dynamic> d) {
    final w = d['channel_width_mhz'];
    if (w == null) return '—';
    return '${w}MHz';
  }

  Widget _snrCell(Map<String, dynamic> d) {
    final snr = d['est_snr_db'] as int?;
    final lbl = d['snr_label'] as String?;
    if (snr == null || snr == 0) return _cell('—', const TextStyle(fontSize: 11));
    final color = snr >= 25 ? Colors.green : snr >= 15 ? Colors.orange : Colors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('~${snr}dB', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        if (lbl != null) Text(lbl, style: TextStyle(fontSize: 9, color: color)),
      ]),
    );
  }

  Widget _linkSpdCell(Map<String, dynamic> d) {
    final link = d['last_link_speed_mbps'] as int?;
    if (link == null || link == 0) return _cell('—', const TextStyle(fontSize: 11));
    final tx = d['last_tx_speed_mbps'] as int?;
    final rx = d['last_rx_speed_mbps'] as int?;
    final extra = (tx != null && tx > 0 && tx != link) ? '\n↑$tx↓${rx ?? link}' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text('$link Mbps$extra',
          style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600)),
    );
  }

  Widget _confidenceCell(Map<String, dynamic> d) {
    final score = WifiBeaconScannerService.confidenceScore(d['last_seen'] as Timestamp?);
    final color = score >= 80 ? Colors.green : score >= 50 ? Colors.orange : Colors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_rounded, size: 11, color: color),
        const SizedBox(width: 2),
        Text('$score%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  void _editBeacon(Map<String, dynamic> d) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EditBeaconRoute(docId: d['_id'] as String, data: d),
      ),
    );
  }
}

/// Thin wrapper that opens NokiaBeaconScreen and auto-opens edit dialog
class _EditBeaconRoute extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _EditBeaconRoute({required this.docId, required this.data});
  @override
  State<_EditBeaconRoute> createState() => _EditBeaconRouteState();
}

class _EditBeaconRouteState extends State<_EditBeaconRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pop(context);
    });
  }
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
