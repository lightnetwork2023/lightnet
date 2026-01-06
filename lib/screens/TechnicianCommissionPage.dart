import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/auth_controller.dart';
import '../controllers/TechnicianService.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'model/PaymentAnalytics.dart';

class TechnicianCommissionPage extends StatefulWidget {
  final String? location;
  final List<String>? locations;
  final String? technicianName; // optional: show name when boss views technician
  final String? technicianId; // optional: to fetch per-technician settings

  const TechnicianCommissionPage({
    super.key,
    this.location,
    this.locations,
    this.technicianName,
    this.technicianId,
  });

  @override
  State<TechnicianCommissionPage> createState() => _TechnicianCommissionPageState();
}

class _TechnicianCommissionPageState extends State<TechnicianCommissionPage> {
  late Future<PaymentAnalytics> _analyticsFuture;
  double _commissionDivisor = 30000.0; // Default divisor

  @override
  void initState() {
    super.initState();
    _loadCommissionDivisor();
    _analyticsFuture = _fetchAnalyticsData();
  }

  Future<void> _loadCommissionDivisor() async {
    try {
      String? targetUid = widget.technicianId;
      final auth = Get.isRegistered<AuthController>() ? Get.find<AuthController>() : null;
      if (targetUid == null && auth != null && auth.userRole == 'technician') {
        targetUid = auth.user?.uid;
      }
      if (targetUid == null || targetUid.isEmpty) return;

      final doc = await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final raw = data['commission_divisor'];
        double? parsed;
        if (raw is num) parsed = raw.toDouble();
        if (raw is String) parsed = double.tryParse(raw);
        if (parsed != null && parsed > 0) {
          if (mounted) setState(() => _commissionDivisor = parsed!);
        }
      }
    } catch (_) {
      // Ignore errors and keep default
    }
  }

  Future<PaymentAnalytics> _fetchAnalyticsData() async {
    try {
      final auth = Get.isRegistered<AuthController>() ? Get.find<AuthController>() : null;
      String? loc = widget.location;
      List<String>? locs = widget.locations;

      // Resolve default locations for technician self-view
      if ((loc == null || loc.isEmpty) && (locs == null || locs.isEmpty) && auth != null) {
        if (auth.userRole == 'technician') {
          final userLocs = auth.userLocations;
          if (userLocs.isNotEmpty) {
            locs = userLocs;
          } else if (auth.userLocation.isNotEmpty) {
            loc = auth.userLocation;
          }
        }
      }

      final resp = await TechnicianService.fetchTechnicianPaymentsSummary(
        location: loc,
        locations: locs,
      );
      final summary = resp['summary'] as Map<String, dynamic>;
      return PaymentAnalytics.fromSummary(summary);
    } catch (e) {
      rethrow;
    }
  }

  // Build a card that displays commission (total/30000) and shows payments total in subtitle
  Widget _commissionCard({required String title, required double total, required Color color, required IconData icon}) {
    final auth = Get.isRegistered<AuthController>() ? Get.find<AuthController>() : null;
    final isTechnician = auth?.userRole == 'technician';
    final commission = total / _commissionDivisor;
    final subtitle = isTechnician 
        ? 'Your commission' 
        : 'Payments total: ${total.toStringAsFixed(2)} TZS\nCommission = total / ${_commissionDivisor.toStringAsFixed(0)}';
    return StatCard(
      title: title,
      value: commission.toStringAsFixed(2),
      subtitle: subtitle,
      icon: icon,
      iconColor: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.isRegistered<AuthController>() ? Get.find<AuthController>() : null;
    List<String> displayLocations = [];
    if (widget.locations != null && widget.locations!.isNotEmpty) {
      displayLocations = widget.locations!;
    } else if (auth != null && auth.userRole == 'technician' && auth.userLocations.isNotEmpty) {
      displayLocations = auth.userLocations;
    } else if (widget.location != null && widget.location!.isNotEmpty) {
      displayLocations = [widget.location!];
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Technician Commission',
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
            onPressed: () async {
              await _loadCommissionDivisor();
              if (mounted) {
                setState(() {
                  _analyticsFuture = _fetchAnalyticsData();
                });
              }
            },
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<PaymentAnalytics>(
        future: _analyticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ModernLoading(message: 'Loading commission...');
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Error Loading Commission',
              subtitle: 'Failed to load data: ${snapshot.error}',
              action: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _analyticsFuture = _fetchAnalyticsData();
                  });
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const EmptyState(
              icon: Icons.analytics_outlined,
              title: 'No Data',
              subtitle: 'No commission data found',
            );
          }

          final data = snapshot.data!;
          return CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
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
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Technician Commission',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (widget.technicianName != null && widget.technicianName!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Technician: ${widget.technicianName}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.95),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (displayLocations.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          displayLocations.length > 1
                              ? 'Locations: ${displayLocations.join(', ')}'
                              : 'Location: ${displayLocations.first}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.95),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (auth?.userRole != 'technician') ...[
                        const SizedBox(height: 6),
                        Text(
                          'Formula: Commission = Payments total / ${_commissionDivisor.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.9),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Recent Performance',
                  subtitle: 'Today and last 24 hours',
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _commissionCard(
                          title: 'Today',
                          total: data.today,
                          color: AppTheme.successColor,
                          icon: Icons.today_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _commissionCard(
                          title: 'Last 24h',
                          total: data.last24Hours,
                          color: AppTheme.infoColor,
                          icon: Icons.access_time_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Monthly Overview',
                  subtitle: 'Current and previous month',
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _commissionCard(
                              title: 'This Month',
                              total: data.thisMonth,
                              color: AppTheme.primaryColor,
                              icon: Icons.calendar_month_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _commissionCard(
                              title: 'Daily Average',
                              total: data.dailyAverageThisMonth,
                              color: Colors.purple,
                              icon: Icons.show_chart_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _commissionCard(
                        title: 'Last Month',
                        total: data.lastMonth,
                        color: AppTheme.warningColor,
                        icon: Icons.calendar_today_rounded,
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Yearly Performance',
                  subtitle: 'Year to date',
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _commissionCard(
                    title: 'This Year',
                    total: data.thisYear,
                    color: Colors.indigo,
                    icon: Icons.calendar_view_month_rounded,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}
