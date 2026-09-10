import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lightnetwork/screens/payments.dart';
import 'package:lightnetwork/screens/PaymentAnalyticsPage.dart';
import 'package:get/get.dart';
import '../controllers/location_controller.dart';
import '../controllers/ApiService.dart';
import '../controllers/auth_controller.dart';
import 'UserManagementScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'NetworkDevicesScreen.dart';
import 'ActiveMacsScreen.dart';
import 'OfflineDevicesScreen.dart';
import 'VouchersScreen.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import '../widgets/modern_drawer.dart';
import 'HomeInternetCustomersScreen.dart';
import 'MikroTikMonitorScreen.dart';
import 'RecentTechActivitiesScreen.dart';
import 'ExpenseApprovalScreen.dart';
import 'SaWithdrawalRequestsScreen.dart';
import 'MyAccountScreen.dart';
import 'TransactionsScreen.dart';
import '../services/MikroTikMonitorService.dart';
import '../services/SiteService.dart';
import 'SiteOverviewScreen.dart';
import 'dart:async';
import 'dart:io';
import '../services/WifiBeaconScannerService.dart';
import 'NokiaBeaconSheetScreen.dart';
import 'InternetPaymentsScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthController _authController = Get.find<AuthController>();
  int activeSessionsCount = 0;
  int recentLoginsCount = 0;
  int todayLoginsCount = 0;
  int last24hLoginsCount = 0;
  int recentPaymentsCount = 0;
  int todayPaymentsCount = 0;
  int last24hPaymentsCount = 0;
  Map<String, int> paymentsByLocation = {};
  Map<String, int> recentPaymentsByLocation = {};
  Map<String, int> todayPaymentsByLocation = {};
  Map<String, int> yesterdayPaymentsByLocation = {};
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");
  List<dynamic> activeMacs = [];
  int offlineDevicesCount = 0;
  List<Map<String, dynamic>> allDevices = [];

  // MikroTik offline monitoring
  StreamSubscription<QuerySnapshot>? _mikrotikSub;
  final Map<String, String> _prevMikroTikStatuses = {};
  bool _mikrotikInitialized = false;
  Timer? _wifiScanTimer;
  int _internetPaymentsDueCount = 0;

  @override
  void initState() {
    super.initState();
    _loadActiveMacs();
    _loadOfflineDevices();
    _loadActiveSessions();
    _loadRecentLogins();
    _loadRecentPayments();
    // Cache users in background without blocking UI
    _cacheAllValidUsers().catchError((e) => debugPrint('Background caching error: $e'));
    _startMikroTikOfflineWatch();
    _triggerBeaconScan();
    _checkInternetPaymentsDue();
  }

  @override
  void dispose() {
    _mikrotikSub?.cancel();
    _wifiScanTimer?.cancel();
    super.dispose();
  }

  void _triggerBeaconScan() {
    // Auth may not be ready yet — wait up to 4 s in 500 ms steps, then proceed
    Future(() async {
      int waited = 0;
      while (!_authController.isDataLoaded && waited < 8) {
        await Future.delayed(const Duration(milliseconds: 500));
        waited++;
      }
      if (!mounted) return;

      final role = _authController.userRole.toLowerCase();
      final isAlwaysOn =
          role == 'technician' || role == 'agent' || role == 'dealer';

      if (isAlwaysOn) {
        // Immediate scan with permission request, then every 30 seconds
        WifiBeaconScannerService.scanAndReport(
            forceEnabled: true, askPermissions: true);
        _wifiScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted) WifiBeaconScannerService.scanAndReport(forceEnabled: true);
        });
      } else {
        // Others: 3-second delay then every 5 minutes
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        WifiBeaconScannerService.scanAndReport();
        _wifiScanTimer = Timer.periodic(const Duration(minutes: 5), (_) {
          if (mounted) WifiBeaconScannerService.scanAndReport();
        });
      }
    });
  }

  void _showTechCheckInSheet(BuildContext context) {
    String selectedType = '';
    final destCtrl = TextEditingController();
    final issueCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.directions_rounded,
                        color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Where Are You Going?',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                        Text('Log your current field activity',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Destination Type *',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final entry in [
                    ['agent', 'Agent', Icons.person_pin_circle_rounded],
                    ['home', 'Home', Icons.home_rounded],
                    ['site', 'Site', Icons.cell_tower_rounded],
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheet(() => selectedType = entry[0] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedType == entry[0]
                                ? AppTheme.primaryColor
                                : AppTheme.primaryColor.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedType == entry[0]
                                  ? AppTheme.primaryColor
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(entry[2] as IconData,
                                  size: 22,
                                  color: selectedType == entry[0]
                                      ? Colors.white
                                      : AppTheme.primaryColor),
                              const SizedBox(height: 4),
                              Text(
                                entry[1] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selectedType == entry[0]
                                      ? Colors.white
                                      : AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: destCtrl,
                decoration: InputDecoration(
                  labelText: selectedType == 'agent'
                      ? 'Agent Name / Location (optional)'
                      : selectedType == 'home'
                          ? 'Customer Name / Address (optional)'
                          : 'Site Name (optional)',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: issueCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Shida Nini?',
                  hintText: 'e.g. Hakuna Mtandao, Router Imefail, Nenda Kufanya Installation',
                  prefixIcon: const Icon(Icons.report_problem_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          if (selectedType.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please select a destination type')),
                            );
                            return;
                          }
                          setSheet(() => saving = true);
                          try {
                            await FirebaseFirestore.instance
                                .collection('tech_checkins')
                                .add({
                              'technician_id': _authController.user?.uid ?? '',
                              'technician_name': _authController.userName,
                              'destination_type': selectedType,
                              'destination_name': destCtrl.text.trim(),
                              'issue': issueCtrl.text.trim(),
                              'created_at': FieldValue.serverTimestamp(),
                            });
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Activity logged successfully!')),
                              );
                            }
                          } catch (e) {
                            setSheet(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to log: $e')),
                            );
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(saving ? 'Logging...' : 'Log Activity'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startMikroTikOfflineWatch() {
    final role = _authController.userRole;
    if (role != 'boss' && role != 'md' && role != 'technician') return;

    _mikrotikSub = FirebaseFirestore.instance
        .collection('mikrotik_devices')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final List<String> newlyOffline = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        final currentStatus = (data['status'] as String?) ?? 'unknown';
        final prev = _prevMikroTikStatuses[doc.id];
        // Detect transition to offline (skip on very first snapshot to avoid spam on login)
        if (_mikrotikInitialized && prev != 'offline' && currentStatus == 'offline') {
          final loc = (data['location'] ?? data['site'] ?? data['siteName'] ?? '')
              .toString()
              .trim();
          final model = (data['name'] ?? data['deviceName'] ?? '')
              .toString()
              .trim();
          String label;
          if (loc.isNotEmpty && model.isNotEmpty) {
            label = '$loc ($model)';
          } else if (loc.isNotEmpty) {
            label = loc;
          } else if (model.isNotEmpty) {
            label = model;
          } else {
            label = doc.id;
          }
          newlyOffline.add(label);
        }
        _prevMikroTikStatuses[doc.id] = currentStatus;
      }
      _mikrotikInitialized = true;
      // Show a dialog for each newly offline device
      for (final name in newlyOffline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showMikroTikOfflineDialog(name);
        });
      }
    });
  }

  void _showMikroTikOfflineDialog(String deviceName) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications_rounded,
                    color: Colors.green.shade700, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Notification',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'MikroTik $deviceName is OFFLINE',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('OK',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Internet payments due popup ────────────────────────────────────────

  Future<void> _checkInternetPaymentsDue() async {
    final role = _authController.userRole;
    if (role != 'boss' && role != 'md') return;
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('internet_payments')
          .get();
      final now = DateTime.now();
      final dueSubs = snap.docs.where((doc) {
        final data = doc.data();
        final dueDay = (data['due_day'] as num?)?.toInt() ?? 1;
        final raw = data['last_confirmed_date'];
        bool confirmedThisMonth = false;
        if (raw is Timestamp) {
          final dt = raw.toDate();
          confirmedThisMonth = dt.year == now.year && dt.month == now.month;
        }
        if (confirmedThisMonth) return false;
        final diff = dueDay - now.day;
        return diff <= 3; // due within 3 days or overdue
      }).map((doc) => {'_id': doc.id, ...doc.data()}).toList();

      if (mounted) {
        setState(() => _internetPaymentsDueCount = dueSubs.length);
      }
      if (dueSubs.isNotEmpty && mounted) {
        _showInternetPaymentsDueDialog(dueSubs);
      }
    } catch (e) {
      debugPrint('Internet payments check error: $e');
    }
  }

  void _showInternetPaymentsDueDialog(List<Map<String, dynamic>> dueSubs) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_rounded, color: Colors.orange.shade700, size: 36),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Internet Payment Due',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${dueSubs.length} subscription(s) need payment confirmation',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: dueSubs.length,
                    itemBuilder: (_, i) {
                      final sub = dueSubs[i];
                      final dueDay = (sub['due_day'] as num?)?.toInt() ?? 1;
                      final diff = dueDay - DateTime.now().day;
                      final isOverdue = diff < 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isOverdue ? Colors.red.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isOverdue ? Colors.red.shade200 : Colors.orange.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sub['location'] ?? '—',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '${sub['provider'] ?? '—'}  •  Day $dueDay  •  ${isOverdue ? 'OVERDUE' : '${diff}d left'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isOverdue ? Colors.red[700] : Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                try {
                                  final userName = _authController.userName;
                                  final now = DateTime.now();
                                  final monthYear = '${now.year}-${now.month.toString().padLeft(2,'0')}';
                                  await FirebaseFirestore.instance
                                      .collection('internet_payments')
                                      .doc(sub['_id'] as String)
                                      .update({
                                    'last_confirmed_date': FieldValue.serverTimestamp(),
                                    'confirmed_by': userName,
                                  });
                                  await FirebaseFirestore.instance
                                      .collection('internet_payment_history')
                                      .add({
                                    'payment_id': sub['_id'],
                                    'location': sub['location'] ?? '',
                                    'provider': sub['provider'] ?? '',
                                    'package_mbps': sub['package_mbps'] ?? 0,
                                    'due_day': sub['due_day'] ?? 1,
                                    'account_number': sub['account_number'] ?? '',
                                    'confirmed_at': FieldValue.serverTimestamp(),
                                    'confirmed_by': userName,
                                    'month_year': monthYear,
                                  });
                                  setD(() => dueSubs.removeAt(i));
                                  if (dueSubs.isEmpty && ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  debugPrint('Confirm error: $e');
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Confirm', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Dismiss'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InternetPaymentsScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('View All'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadActiveMacs() async {
    try {
      final data = await ApiService.fetchActiveMacs();
      setState(() => activeMacs = data);
    } catch (e) {
      setState(() => activeMacs = []);
    }
  }

  Future<void> _loadOfflineDevices() async {
    final snapshot = await FirebaseFirestore.instance.collection('devices').get();
    final all = snapshot.docs.map((doc) => {
      'id': doc.id,
      ...doc.data(),
    }).toList();
    final offline = all.where((d) => d['status'] == 'offline').toList();
    setState(() {
      offlineDevicesCount = offline.length;
      allDevices = all;
    });
  }

  Future<void> _loadActiveSessions() async {
    try {
      final data = await ApiService.fetchActiveSessions();
      setState(() => activeSessionsCount = data.length);
    } catch (e) {
      debugPrint('Error loading active sessions: $e');
      setState(() => activeSessionsCount = 0);
    }
  }

  Future<void> _loadRecentLogins() async {
    try {
      final recentVouchers = await ApiService.fetchRecentVouchers();
      final todayVouchers = await ApiService.fetchVouchersToday();

      setState(() {
        todayLoginsCount = todayVouchers.length;
        last24hLoginsCount = recentVouchers.length;
      });
    } catch (e) {
      debugPrint('Error loading logins: $e');
      setState(() {
        todayLoginsCount = 0;
        last24hLoginsCount = 0;
      });
    }
  }

  Future<void> _loadRecentPayments() async {
    try {
      final recentPayments = await ApiService.fetchRecentPayments();
      final todayPayments = await ApiService.fetchPaymentsToday();

      Map<String, int> tempTodayPaymentsByLocation = {};
      Map<String, int> tempLast24hPaymentsByLocation = {};

      // Process today's payments by location
      for (var payment in todayPayments) {
        final location = payment['location']?.toString() ?? 'Unknown';
        tempTodayPaymentsByLocation[location] = (tempTodayPaymentsByLocation[location] ?? 0) + 1;
      }

      // Process last 24h payments by location
      for (var payment in recentPayments) {
        final location = payment['location']?.toString() ?? 'Unknown';
        tempLast24hPaymentsByLocation[location] = (tempLast24hPaymentsByLocation[location] ?? 0) + 1;
      }

      setState(() {
        todayPaymentsCount = todayPayments.length;
        last24hPaymentsCount = recentPayments.length;
        todayPaymentsByLocation = tempTodayPaymentsByLocation;
        recentPaymentsByLocation = tempLast24hPaymentsByLocation;
      });
    } catch (e) {
      debugPrint('Error loading payments: $e');
      setState(() {
        todayPaymentsCount = 0;
        last24hPaymentsCount = 0;
        todayPaymentsByLocation = {};
        recentPaymentsByLocation = {};
      });
    }
  }

  Future<void> _cacheAllValidUsers() async {
    final locationController = Get.find<LocationController>();
    // Ensure locations are loaded
    if (locationController.locations.isEmpty) {
      await locationController.loadLocations();
    }
    await ApiService.fetchAllValidUsers(locationController.locations);
  }

  Future<void> _refreshData() async {
    ApiService.clearCache(); // Clear cache before refresh
    try {
      await Future.wait([
        _loadActiveMacs(),
        _loadOfflineDevices(),
        _loadActiveSessions(),
        _loadRecentLogins(),
        _loadRecentPayments(),
      ]);
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 0, // Default to Dashboard tab
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        drawer: const ModernDrawer(),
        appBar: AppBar(
          title: Text(
            'lightNET',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: AppGradients.primaryGradient,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _refreshData,
              tooltip: 'Refresh Data',
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              const Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
              Tab(
                icon: Icon(_authController.userRole == 'technician'
                    ? Icons.router_rounded
                    : Icons.location_city_rounded),
                text: _authController.userRole == 'technician' ? 'MikroTik' : 'Sites',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Dashboard Tab
            RefreshIndicator(
              onRefresh: _refreshData,
              color: AppTheme.primaryColor,
              child: CustomScrollView(
                slivers: [
            // Welcome Header
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.dashboard_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back!',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Obx(() => Text(
                                'Role: ${_authController.userRole.isEmpty ? "Loading..." : _authController.userRole.toUpperCase()}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Quick Stats Grid
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_authController.userRole != 'technician')
                          Expanded(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('mikrotik_devices')
                                  .snapshots(),
                              builder: (context, snap) {
                                int total = 0;
                                int routers = 0;
                                if (snap.hasData) {
                                  routers = snap.data!.docs.length;
                                  for (final d in snap.data!.docs) {
                                    final v = d.data()['clients_count'];
                                    if (v is num) total += v.toInt();
                                    else if (v is String) total += int.tryParse(v) ?? 0;
                                  }
                                }
                                return StatCard(
                                  title: 'Active Sessions',
                                  value: total.toString(),
                                  subtitle: 'Across $routers MikroTik${routers == 1 ? '' : 's'}',
                                  icon: Icons.wifi_rounded,
                                  iconColor: AppTheme.successColor,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MikroTikMonitorScreen(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        if (_authController.userRole != 'technician')
                          const SizedBox(width: 12),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('nokia_beacons')
                                .snapshots(),
                            builder: (context, nokiaSnap) {
                              int totalNokia = 0;
                              int alertCount = 0;
                              int freqCount = 0;

                              if (nokiaSnap.hasData) {
                                final docs = nokiaSnap.data!.docs;
                                totalNokia = docs.length;
                                final allData = docs.map((d) => d.data()).toList();

                                // Channel freq-conflict detection per location
                                final Map<String, Set<String>> locCh2 = {};
                                final Map<String, Set<String>> locCh5 = {};
                                for (final d in allData) {
                                  final loc = (d['location'] ?? '').toString().toLowerCase();
                                  final ch2 = (d['channel_2ghz'] ?? '').toString().trim();
                                  final ch5 = (d['channel_5ghz'] ?? '').toString().trim();
                                  if (loc.isEmpty) continue;
                                  locCh2.putIfAbsent(loc, () => {});
                                  locCh5.putIfAbsent(loc, () => {});
                                  if (ch2.isNotEmpty) locCh2[loc]!.add(ch2);
                                  if (ch5.isNotEmpty) locCh5[loc]!.add(ch5);
                                }
                                for (final d in allData) {
                                  // Stale / not seen > 6h
                                  final ts = d['last_seen'];
                                  if (ts is Timestamp) {
                                    final diff = DateTime.now().difference(ts.toDate()).inHours;
                                    if (diff >= 6 || (d['status'] ?? '') == 'offline') {
                                      alertCount++;
                                    }
                                  } else if ((d['status'] ?? '') == 'offline') {
                                    alertCount++;
                                  }

                                  // Freq conflicts
                                  final loc = (d['location'] ?? '').toString().toLowerCase();
                                  final ch2 = (d['channel_2ghz'] ?? '').toString().trim();
                                  final ch5 = (d['channel_5ghz'] ?? '').toString().trim();
                                  if (loc.isNotEmpty) {
                                    final ch2set = locCh2[loc] ?? {};
                                    final ch5set = locCh5[loc] ?? {};
                                    // conflict = same channel used by >1 beacon in same area
                                    if ((ch2.isNotEmpty && ch2set.length < allData.where((x) =>
                                        (x['location'] ?? '').toString().toLowerCase() == loc &&
                                        (x['channel_2ghz'] ?? '').toString().trim() == ch2).length
                                      ) || false) freqCount++;
                                  }
                                }
                                // Simpler freq conflict: count beacons sharing ch in same location
                                freqCount = 0;
                                for (final d in allData) {
                                  final loc = (d['location'] ?? '').toString().toLowerCase();
                                  final ch2 = (d['channel_2ghz'] ?? '').toString().trim();
                                  final ch5 = (d['channel_5ghz'] ?? '').toString().trim();
                                  if (loc.isEmpty) continue;
                                  if (ch2.isNotEmpty && allData.where((x) =>
                                      (x['location'] ?? '').toString().toLowerCase() == loc &&
                                      (x['channel_2ghz'] ?? '').toString().trim() == ch2).length > 1) {
                                    freqCount++;
                                    continue;
                                  }
                                  if (ch5.isNotEmpty && allData.where((x) =>
                                      (x['location'] ?? '').toString().toLowerCase() == loc &&
                                      (x['channel_5ghz'] ?? '').toString().trim() == ch5).length > 1) {
                                    freqCount++;
                                  }
                                }
                              }

                              final hasIssues = alertCount > 0 || freqCount > 0;
                              return StatCard(
                                title: 'Nokia Beacons',
                                value: totalNokia.toString(),
                                subtitle: alertCount > 0
                                    ? '$alertCount need check${freqCount > 0 ? " · $freqCount freq⚠" : ""}'
                                    : freqCount > 0
                                        ? '$freqCount freq conflict${freqCount > 1 ? "s" : ""}'
                                        : 'All beacons',
                                icon: Icons.cell_tower_rounded,
                                iconColor: hasIssues ? AppTheme.errorColor : AppTheme.successColor,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const NokiaBeaconSheetScreen(),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'Today Logins',
                            value: _authController.userRole == 'technician' ? '' : todayLoginsCount.toString(),
                            subtitle: _authController.userRole == 'technician' ? 'View login vouchers' : '$last24hLoginsCount in 24h',
                            icon: Icons.login_rounded,
                            iconColor: AppTheme.infoColor,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => VouchersScreen(userRole: _authController.userRole)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            title: 'Today Payments',
                            value: _authController.userRole == 'technician' ? '' : todayPaymentsCount.toString(),
                            subtitle: _authController.userRole == 'technician' ? 'View all payments' : '$last24hPaymentsCount in 24h',
                            icon: Icons.payment_rounded,
                            iconColor: AppTheme.warningColor,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => PaymentsScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Payments by Location Section
            if (_authController.userRole != 'technician' && recentPaymentsByLocation.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Payments by Location',
                  subtitle: 'Last 24 hours activity',
                ),
              ),
              SliverToBoxAdapter(
                child: ModernCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: recentPaymentsByLocation.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.warningColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: AppTheme.warningColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            ModernBadge(
                              text: '${entry.value}',
                              backgroundColor: AppTheme.warningColor,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            
            // Quick Actions Section
            const SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Quick Actions',
                subtitle: 'Frequently used features',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    if (_authController.isAdminLevel) ...[
                      // Internet Payments card
                      ModernCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const InternetPaymentsScreen()),
                        ),
                        margin: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.wifi_rounded, color: Colors.blue, size: 24),
                                ),
                                if (_internetPaymentsDueCount > 0)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$_internetPaymentsDueCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Internet Payments',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _internetPaymentsDueCount == 0
                                        ? 'Monthly ISP bill tracker'
                                        : '$_internetPaymentsDueCount payment${_internetPaymentsDueCount == 1 ? '' : 's'} due soon',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _internetPaymentsDueCount > 0 ? Colors.orange : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Pending Requests card with live count
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('expenses')
                            .where('status', isEqualTo: 'pending')
                            .snapshots(),
                        builder: (context, reqSnap) {
                          final count = reqSnap.data?.docs.length ?? 0;
                          return ModernCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ExpenseApprovalScreen()),
                            ),
                            margin: EdgeInsets.zero,
                            child: Row(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.assignment_rounded,
                                        color: Colors.purple,
                                        size: 24,
                                      ),
                                    ),
                                    if (count > 0)
                                      Positioned(
                                        top: -4,
                                        right: -4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '$count',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pending Requests',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        count == 0
                                            ? 'No pending requests'
                                            : '$count request${count == 1 ? '' : 's'} awaiting approval',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: count > 0 ? Colors.orange : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded,
                                    color: Colors.grey, size: 16),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ModernCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RecentTechActivitiesScreen()),
                        ),
                        margin: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.engineering_rounded,
                                color: Colors.orange,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Recent Tech Activities',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Vouchers & field actions by technicians',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _authController.userRole == 'technician'
                        ? ModernCard(
                            onTap: () => _showTechCheckInSheet(context),
                            margin: EdgeInsets.zero,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.directions_rounded,
                                      color: AppTheme.primaryColor, size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Where Are You Going?',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text('Log field activity & report issues',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded,
                                    color: Colors.grey, size: 16),
                              ],
                            ),
                          )
                        : _authController.isMD
                        ? StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(_authController.user?.uid)
                                .snapshots(),
                            builder: (context, snap) {
                              final data = snap.data?.data() as Map<String, dynamic>? ?? {};
                              final bal = (data['float_balance'] as num?)?.toDouble() ?? 0.0;
                              final isLow = bal < 50000;
                              final balStr = bal.toStringAsFixed(0).replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
                              return ModernCard(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                                margin: EdgeInsets.zero,
                                child: Row(
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: (isLow ? Colors.orange : Colors.teal).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(Icons.receipt_long_rounded,
                                              color: isLow ? Colors.orange : Colors.teal, size: 24),
                                        ),
                                        if (isLow)
                                          Positioned(
                                            top: -4, right: -4,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                              child: const Text('!', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Transactions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(
                                            isLow ? '⚠️ Low float – TZS $balStr' : 'Float: TZS $balStr',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: isLow ? Colors.orange : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                                  ],
                                ),
                              );
                            },
                          )
                        : ModernCard(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                            margin: EdgeInsets.zero,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.receipt_long_rounded, color: Colors.teal, size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Transactions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text('All float & approval transactions', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                              ],
                            ),
                          ),
                    if (_authController.isBoss) ...[
                      const SizedBox(height: 12),
                      // SA Withdraw card with live pending badge
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('sa_withdrawal_requests')
                            .where('status', isEqualTo: 'pending')
                            .snapshots(),
                        builder: (context, wSnap) {
                          final wCount = wSnap.data?.docs.length ?? 0;
                          return ModernCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const SaWithdrawalRequestsScreen()),
                            ),
                            margin: EdgeInsets.zero,
                            child: Row(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.arrow_circle_up_rounded,
                                        color: Colors.teal,
                                        size: 24,
                                      ),
                                    ),
                                    if (wCount > 0)
                                      Positioned(
                                        top: -4,
                                        right: -4,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '$wCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'SuperAgent Withdrawals',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        wCount == 0
                                            ? 'No pending withdrawal requests'
                                            : '$wCount withdrawal${wCount == 1 ? '' : 's'} awaiting approval',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: wCount > 0
                                                    ? Colors.red
                                                    : Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded,
                                    color: Colors.grey, size: 16),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ModernCard(
                        onTap: () => Get.to(() => const UserManagementScreen()),
                        gradient: AppGradients.primaryGradient,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.admin_panel_settings_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'User Management',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Manage user accounts and permissions',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white.withOpacity(0.8),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 32),
            ),
                ],
              ),
            ),
            
            // Sites / MikroTik Tab (role-based)
            _authController.userRole == 'technician'
                ? const MikroTikMonitorContent()
                : _buildSitesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSitesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SiteService.streamAll(),
      builder: (context, siteSnap) {
        if (siteSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = siteSnap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_city_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No sites yet', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refreshData,
          color: AppTheme.primaryColor,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final siteData = doc.data();
              final siteName = siteData['name'] as String? ?? 'Site';
              final siteLoc = siteData['main_location'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ModernCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SiteOverviewScreen(siteId: doc.id)),
                  ),
                  margin: EdgeInsets.zero,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.location_city_rounded, color: Colors.teal, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(siteName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              siteLoc.isNotEmpty ? '📍 $siteLoc' : 'Site Overview',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// MikroTik Monitor Content Widget (without AppBar)
class MikroTikMonitorContent extends StatefulWidget {
  const MikroTikMonitorContent({Key? key}) : super(key: key);

  @override
  State<MikroTikMonitorContent> createState() => _MikroTikMonitorContentState();
}

class _MikroTikMonitorContentState extends State<MikroTikMonitorContent> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterChips(),
        _buildSummaryCards(),
        Expanded(child: _buildDevicesList()),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 'all'),
            const SizedBox(width: 8),
            _buildFilterChip('Online', 'online'),
            const SizedBox(width: 8),
            _buildFilterChip('Offline', 'offline'),
            const SizedBox(width: 8),
            _buildFilterChip('Unknown', 'unknown'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => setState(() => _filterStatus = value),
      backgroundColor: Colors.grey[200],
      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot>(
      stream: MikroTikMonitorService.getMikroTikDevices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 80);
        }

        final devices = snapshot.data!.docs;
        final onlineCount = devices.where((d) => d['status'] == 'online').length;
        final offlineCount = devices.where((d) => d['status'] == 'offline').length;
        final unknownCount = devices.where((d) => d['status'] == 'unknown').length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Online',
                  onlineCount.toString(),
                  Colors.green,
                  Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Offline',
                  offlineCount.toString(),
                  Colors.red,
                  Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Unknown',
                  unknownCount.toString(),
                  Colors.orange,
                  Icons.help_outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _filterStatus == 'all'
          ? MikroTikMonitorService.getMikroTikDevices()
          : MikroTikMonitorService.getMikroTikDevicesByStatus(_filterStatus),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final devices = snapshot.data!.docs;

        if (devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.router_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No MikroTik devices found',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MikroTikMonitorScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Device'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: devices.length,
          itemBuilder: (context, index) => _buildDeviceCard(devices[index]),
        );
      },
    );
  }

  Widget _buildDeviceCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'unknown';
    final name = data['name'] ?? 'Unknown';
    final ipAddress = data['ipAddress'] ?? '';
    final location = data['location'] ?? '';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'online':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'offline':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MikroTikMonitorScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon, color: statusColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          location,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.router_outlined, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          ipAddress,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}