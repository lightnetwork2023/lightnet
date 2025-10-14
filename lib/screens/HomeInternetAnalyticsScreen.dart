import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class HomeInternetAnalyticsScreen extends StatefulWidget {
  const HomeInternetAnalyticsScreen({super.key});

  @override
  State<HomeInternetAnalyticsScreen> createState() => _HomeInternetAnalyticsScreenState();
}

class _HomeInternetAnalyticsScreenState extends State<HomeInternetAnalyticsScreen> {
  final _auth = Get.find<AuthController>();

  final _fmt = NumberFormat('#,##0');

  List<String> _zones = [];
  String? _zone;
  List<String> _customerTypes = [];
  String? _customerType;

  bool _loading = true;
  Map<String, dynamic>? _thisMonth;
  Map<String, dynamic>? _lastMonth;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final zones = await HomeInternetService.fetchZones();
      final types = await HomeInternetService.fetchCustomerTypes();
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _customerTypes = types;
        _zone = zones.isNotEmpty ? null : null; // no preselect
        _customerType = null;
      });
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1, 1);

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final thisStart = _monthStart(now);
      final thisEnd = _nextMonthStart(now);
      final lastStart = _monthStart(DateTime(now.year, now.month - 1, 1));
      final lastEnd = thisStart;

      final results = await Future.wait([
        HomeInternetService.fetchPaymentsTotal(start: thisStart, end: thisEnd, zone: _zone, customerType: _customerType),
        HomeInternetService.fetchPaymentsTotal(start: lastStart, end: lastEnd, zone: _zone, customerType: _customerType),
      ]);
      if (!mounted) return;
      setState(() {
        _thisMonth = results[0];
        _lastMonth = results[1];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isBoss) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Payments Analytics'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
          ),
        ),
        body: const Center(child: Text('Boss role required to view analytics.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments Analytics'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _filters(),
                  const SizedBox(height: 16),
                  _totalsRow(),
                ],
              ),
            ),
    );
  }

  Widget _filters() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Zone',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _zone,
                        hint: const Text('All Zones'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Zones')),
                          ..._zones.map((z) => DropdownMenuItem<String?>(value: z, child: Text(z))),
                        ],
                        onChanged: (v) => setState(() => _zone = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Customer Type',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _customerType,
                        hint: const Text('All Customer Types'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Customer Types')),
                          ..._customerTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                        ],
                        onChanged: (v) => setState(() => _customerType = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.filter_alt_rounded),
                  label: const Text('Apply'),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow() {
    final tmTotal = (_thisMonth?['total_amount'] ?? 0.0) as double;
    final tmCount = (_thisMonth?['count'] ?? 0) as int;
    final lmTotal = (_lastMonth?['total_amount'] ?? 0.0) as double;
    final lmCount = (_lastMonth?['count'] ?? 0) as int;

    return Column(
      children: [
        _totalCard(
          title: 'This Month',
          amountText: 'TZS ${_fmt.format(tmTotal)}',
          subtitle: '$tmCount payments',
          color: AppTheme.primaryColor,
          icon: Icons.calendar_month_rounded,
        ),
        const SizedBox(height: 12),
        _totalCard(
          title: 'Last Month',
          amountText: 'TZS ${_fmt.format(lmTotal)}',
          subtitle: '$lmCount payments',
          color: AppTheme.textSecondary,
          icon: Icons.history_rounded,
        ),
      ],
    );
  }

  Widget _totalCard({
    required String title,
    required String amountText,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(amountText, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
