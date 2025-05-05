import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';
import 'package:intl/intl.dart';

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});

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
    });
  }

  DateTime? _parseDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) {
      debugPrint('Date string is null or empty');
      return null;
    }
    try {
      // Try HTTP date format (e.g., Sun, 04 May 2025 16:38:23 GMT)
      return _httpDateFormat.parse(dateTimeStr, true).toLocal(); // Parse as UTC, convert to local
    } catch (e) {
      debugPrint('Error parsing date "$dateTimeStr" with format E, dd MMM yyyy HH:mm:ss GMT: $e');
      try {
        // Fallback to MySQL format
        return _mysqlDateFormat.parse(dateTimeStr);
      } catch (e2) {
        debugPrint('Error parsing date "$dateTimeStr" with format yyyy-MM-dd HH:mm:ss: $e2');
        try {
          // Fallback to ISO format
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
      final vouchers = await ApiService.fetchVouchers();
      final now = DateTime.now();
      final last24Hours = now.subtract(const Duration(hours: 24));
      
      int recentCount = 0;
      for (var voucher in vouchers) {
        final loginTime = _parseDateTime(voucher['first_login_time']?.toString());
        if (loginTime != null && loginTime.isAfter(last24Hours)) {
          recentCount++;
        }
      }

      setState(() {
        _vouchers = vouchers;
        _filteredVouchers = List.from(vouchers); // Initialize filtered list
        _recentLoginCount = recentCount;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading vouchers: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _loadVouchers,
            ),
          ),
        );
      }
    }
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'N/A';
    final dateTime = _parseDateTime(dateTimeStr);
    if (dateTime == null) {
      debugPrint('Failed to format date: $dateTimeStr');
      return 'Invalid Date (Check Console)';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  bool _isRecentLogin(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return false;
    final loginTime = _parseDateTime(dateTimeStr);
    if (loginTime == null) return false;
    final last24Hours = DateTime.now().subtract(const Duration(hours: 24));
    return loginTime.isAfter(last24Hours);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🎫 Vouchers"),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Recent Logins: $_recentLoginCount",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ),
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
              decoration: InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterVouchers('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: _filterVouchers,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredVouchers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _searchController.text.isEmpty
                                  ? "No vouchers found"
                                  : "No vouchers match '${_searchController.text}'",
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 16),
                            if (_searchController.text.isEmpty)
                              ElevatedButton.icon(
                                onPressed: _loadVouchers,
                                icon: const Icon(Icons.refresh),
                                label: const Text("Retry"),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadVouchers,
                        child: ListView.builder(
                          itemCount: _filteredVouchers.length,
                          itemBuilder: (context, index) {
                            final voucher = _filteredVouchers[index];
                            final isRecent = _isRecentLogin(voucher['first_login_time']?.toString());

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 4.0,
                              ),
                              color: isRecent ? Colors.green.shade50 : null,
                              child: ListTile(
                                title: Text(
                                  voucher['username']?.toString() ?? 'N/A',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isRecent ? Colors.green : null,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("📍 Location: ${voucher['location']?.toString() ?? 'N/A'}"),
                                    Text("⚡ Speed Limit: ${voucher['speed_limit']?.toString() ?? 'No limit'}"),
                                    Text("⏱️ First Login: ${_formatDateTime(voucher['first_login_time']?.toString())}"),
                                    Text("⌛ Expires: ${_formatDateTime(voucher['expire_time']?.toString())}"),
                                    Text("📱 MAC: ${voucher['mac_address']?.toString() ?? 'Not registered'}"),
                                    Text("Status: ${voucher['used'] == 1 ? '🟢 Used' : '⚪ Unused'}"),
                                    Text("Created: ${_formatDateTime(voucher['created_at']?.toString())}"),
                                    Text("Updated: ${_formatDateTime(voucher['updated_at']?.toString())}"),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}