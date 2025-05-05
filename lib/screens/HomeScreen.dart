import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lightnetwork/screens/payments.dart';
import 'package:lightnetwork/screens/valid_users.dart';


import '../controllers/ApiService.dart';
import 'GenerateUserScreen.dart';
import 'VouchersScreen.dart';
import 'VouchersByLocationScreen.dart';
import 'active_sessions.dart';
import 'delete_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int activeSessionsCount = 0;
  int recentLoginsCount = 0;
  int recentPaymentsCount = 0;
  final DateFormat _mysqlDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final DateFormat _httpDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'");

  @override
  void initState() {
    super.initState();
    _loadActiveSessions();
    _loadRecentLogins();
    _loadRecentPayments();
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

  Future<void> _loadActiveSessions() async {
    final data = await ApiService.fetchActiveSessions();
    setState(() => activeSessionsCount = data.length);
  }

  Future<void> _loadRecentLogins() async {
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
      
      setState(() => recentLoginsCount = recentCount);
    } catch (e) {
      debugPrint('Error loading recent logins: $e');
    }
  }

  Future<void> _loadRecentPayments() async {
    try {
      final payments = await ApiService.fetchPayments();
      final now = DateTime.now();
      final last24Hours = now.subtract(const Duration(hours: 24));
      
      int recentCount = 0;
      for (var payment in payments) {
        final paymentTime = _parseDateTime(payment['timestamp']?.toString());
        if (paymentTime != null && paymentTime.isAfter(last24Hours)) {
          recentCount++;
        }
      }
      
      setState(() => recentPaymentsCount = recentCount);
    } catch (e) {
      debugPrint('Error loading recent payments: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadActiveSessions(),
      _loadRecentLogins(),
      _loadRecentPayments(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Text('lightNET', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Generate Users'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenerateUserScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('View Payments'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.computer),
              title: const Text('Active Sessions'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Valid Users'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ValidUsersScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.card_membership),
              title: const Text('Vouchers'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VouchersScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Vouchers by Location'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VouchersByLocationScreen())),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text("lightNET"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh all counters',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.computer, size: 40, color: Colors.green),
                title: const Text("Active Sessions"),
                subtitle: Text("$activeSessionsCount sessions running"),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionsScreen())),
              ),
            ),
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.login, size: 40, color: Colors.blue),
                title: const Text("Recent Logins"),
                subtitle: Text("$recentLoginsCount logins in last 24h"),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VouchersScreen())),
              ),
            ),
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.payment, size: 40, color: Colors.orange),
                title: const Text("Recent Payments"),
                subtitle: Text("$recentPaymentsCount payments in last 24h"),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen())),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text("Generate Users"),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenerateUserScreen())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}