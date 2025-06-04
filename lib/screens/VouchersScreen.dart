import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';
import 'package:intl/intl.dart';

class VouchersScreen extends StatefulWidget {
  final bool showOnlyUsed;
  const VouchersScreen({super.key, this.showOnlyUsed = false});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  List<dynamic> _vouchers = [];
  List<dynamic> _filteredVouchers = [];
  bool _loading = true;
  int _recentLoginCount = 0;
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterVouchers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredVouchers = List.from(_vouchers);
      } else {
        _filteredVouchers = _vouchers.where((voucher) {
          final username = voucher['username']?.toString().toLowerCase() ?? '';
          return username.contains(query.toLowerCase());
        }).toList();
      }
      // Always sort filtered vouchers by newest first
      _filteredVouchers.sort((a, b) {
        final aTime = _parseDateTime(a['first_login_time']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = _parseDateTime(b['first_login_time']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    });
  }

  DateTime? _parseDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) {
      debugPrint('Date string is null or empty');
      return null;
    }
    try {
      return _httpDateFormat.parse(dateTimeStr, true);
    } catch (e) {
      debugPrint('Error parsing date "$dateTimeStr" with format E, dd MMM yyyy HH:mm:ss GMT: $e');
      try {
        return _mysqlDateFormat.parse(dateTimeStr);
      } catch (e2) {
        debugPrint('Error parsing date "$dateTimeStr" with format yyyy-MM-dd HH:mm:ss: $e2');
        try {
          return DateTime.parse(dateTimeStr);
        } catch (e3) {
          debugPrint('Error parsing date "$dateTimeStr" with ISO format: $e3');
          return null;
        }
      }
    }
  }

  Future<void> _loadVouchers() async {
    setState(() => _loading = true);
    try {
      final vouchers = await ApiService.fetchRecentVouchers();
      // Sort by first_login_time descending (newest first)
      vouchers.sort((a, b) {
        final aTime = _parseDateTime(a['first_login_time']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = _parseDateTime(b['first_login_time']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      setState(() {
        _vouchers = vouchers;
        // Filter vouchers if showOnlyUsed is true
        _filteredVouchers = widget.showOnlyUsed 
            ? vouchers.where((voucher) => voucher['used'] == 1).toList()
            : List.from(vouchers);
        _recentLoginCount = vouchers.length; // All vouchers are from last 24h
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading vouchers: $e');
      setState(() {
        _loading = false;
        _vouchers = [];
        _filteredVouchers = [];
        _recentLoginCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🔄 Recent Vouchers (24h)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVouchers,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by username',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterVouchers,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredVouchers.isEmpty
                    ? const Center(child: Text("No recent vouchers found."))
                    : ListView.builder(
                        itemCount: _filteredVouchers.length,
                        itemBuilder: (context, index) {
                          final voucher = _filteredVouchers[index];
                          final loginTime = _parseDateTime(voucher['first_login_time']?.toString());
                          final expireTime = _parseDateTime(voucher['expire_time']?.toString());
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.person, color: Colors.blue),
                              title: Text(voucher['username'] ?? 'Unknown'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Location: ${voucher['location'] ?? 'N/A'}"),
                                  Text("Speed Limit: ${voucher['speed_limit'] ?? 'N/A'}"),
                                  Text("Session Timeout: ${voucher['session_timeout'] ?? 'N/A'}"),
                                  if (loginTime != null)
                                    Text("First Login: ${loginTime.toString().split('.')[0]}"),
                                  if (expireTime != null)
                                    Text("Expires: ${expireTime.toString().split('.')[0]}"),
                                ],
                              ),
                              trailing: Icon(
                                voucher['used'] == 1 ? Icons.check_circle : Icons.pending,
                                color: voucher['used'] == 1 ? Colors.green : Colors.orange,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}