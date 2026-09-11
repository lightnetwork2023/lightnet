import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/ApiService.dart';
import '../controllers/location_controller.dart';
import '../controllers/auth_controller.dart';
import 'package:intl/intl.dart';

class VouchersByLocationScreen extends StatefulWidget {
  const VouchersByLocationScreen({super.key});

  @override
  State<VouchersByLocationScreen> createState() => _VouchersByLocationScreenState();
}

class _VouchersByLocationScreenState extends State<VouchersByLocationScreen> {
  final LocationController locationController = Get.find();
  final AuthController authController = Get.find<AuthController>();
  final Map<String, List<dynamic>> vouchersByLocation = {};
  final Map<String, int> voucherCounts = {};
  final Map<String, int> recentLoginCounts = {};
  final Map<String, DateTime?> latestCreationTimes = {};
  bool _loading = true;
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() => _loading = true);
    if (locationController.locations.isEmpty) {
      await locationController.loadLocations();
    }
    if (!mounted) return;
    await _loadVouchers();
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

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'N/A';
    final dateTime = _parseDateTime(dateTimeStr);
    if (dateTime == null) {
      debugPrint('Failed to format date: $dateTimeStr');
      return 'Invalid Date';
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

  String _getTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown';
    
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _loadLocationVouchers(String location) async {
    final vouchers = await ApiService.fetchVouchers(location: location, limit: 200);
    if (!mounted) return;
    setState(() {
      vouchersByLocation[location] = vouchers;
    });
  }

  Future<void> _loadVouchers() async {
    try {
      final rows = await ApiService.fetchVoucherLocationCounts();
      final tempVouchersByLocation = <String, List<dynamic>>{};
      final tempRecentLoginCounts = <String, int>{};
      final tempLatestCreationTimes = <String, DateTime?>{};

      for (final row in rows) {
        final location = row['location']?.toString() ?? 'Unknown';
        final matchedLocation = locationController.locations.firstWhere(
          (loc) => _normalizeLocationName(loc) == _normalizeLocationName(location),
          orElse: () => location,
        );
        tempVouchersByLocation.putIfAbsent(matchedLocation, () => []);
        tempRecentLoginCounts[matchedLocation] =
            int.tryParse(row['recent_logins']?.toString() ?? '') ??
                (row['recent_logins'] as num?)?.toInt() ??
                0;
        tempLatestCreationTimes[matchedLocation] =
            _parseDateTime(row['latest_created']?.toString());
        voucherCounts[matchedLocation] =
            int.tryParse(row['voucher_count']?.toString() ?? '') ??
                (row['voucher_count'] as num?)?.toInt() ??
                0;
      }

      setState(() {
        vouchersByLocation.clear();
        vouchersByLocation.addAll(tempVouchersByLocation);
        recentLoginCounts.clear();
        recentLoginCounts.addAll(tempRecentLoginCounts);
        latestCreationTimes.clear();
        latestCreationTimes.addAll(tempLatestCreationTimes);
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

  String _normalizeLocationName(String location) {
    return location.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🎫 Vouchers by Location")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : vouchersByLocation.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "No vouchers found",
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
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
                    itemCount: locationController.locations.length,
                    itemBuilder: (context, index) {
                      final location = locationController.locations[index];
                      final vouchers = vouchersByLocation[location] ?? [];
                      final voucherCount = voucherCounts[location] ?? vouchers.length;
                      final recentCount = recentLoginCounts[location] ?? 0;
                      final latestCreationTime = latestCreationTimes[location];

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      location,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      _getTimeAgo(latestCreationTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "Recent: $recentCount",
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text("$voucherCount vouchers"),
                          trailing: authController.isBoss ? IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () async {
                              if ((vouchersByLocation[location] ?? []).isEmpty) {
                                await _loadLocationVouchers(location);
                              }
                              if (!mounted) return;
                              final loaded = vouchersByLocation[location] ?? [];
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (context) => DraggableScrollableSheet(
                                  initialChildSize: 0.9,
                                  minChildSize: 0.5,
                                  maxChildSize: 0.95,
                                  expand: false,
                                  builder: (context, scrollController) => Container(
                                    color: Colors.white,
                                    child: Column(
                                      children: [
                                        AppBar(
                                          title: Text("Vouchers in $location"),
                                        ),
                                        Expanded(
                                          child: ListView.builder(
                                            controller: scrollController,
                                            itemCount: loaded.length,
                                            itemBuilder: (context, index) {
                                              final voucher = loaded[index];
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
                                                      Text("⚡ Speed Limit: ${voucher['speed_limit']?.toString() ?? 'No limit'}"),
                                                      Text("⏱️ First Login: ${_formatDateTime(voucher['first_login_time']?.toString())}"),
                                                      Text("⌛ Expires: ${_formatDateTime(voucher['expire_time']?.toString())}"),
                                                      Text("📱 MAC: ${voucher['mac_address']?.toString() ?? 'Not registered'}"),
                                                      Text("Status: ${voucher['used'] == 1 ? '🟢 Used' : '⚪ Unused'}"),
                                                    ],
                                                  ),
                                                  isThreeLine: true,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ) : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
} 