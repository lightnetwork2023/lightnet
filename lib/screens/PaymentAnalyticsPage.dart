import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';
import 'model/PaymentAnalytics.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class PaymentAnalyticsPage extends StatefulWidget {
  final String? location;
  final List<String>? locations;
  final String? userRole;
  const PaymentAnalyticsPage({super.key, this.location, this.locations, this.userRole});

  @override
  State<PaymentAnalyticsPage> createState() => _PaymentAnalyticsPageState();
}

class _PaymentAnalyticsPageState extends State<PaymentAnalyticsPage> {
  late Future<PaymentAnalytics> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _fetchAnalyticsData();
  }

  // Fetch all analytics data from summary endpoint
  Future<PaymentAnalytics> _fetchAnalyticsData() async {
    try {
      final summary = widget.userRole == 'boss' 
        ? await ApiService.fetchPaymentsSummary()
        : await ApiService.fetchAgentPaymentsSummary(
            location: widget.location,
            locations: widget.locations,
          );
      return PaymentAnalytics.fromSummary(summary);
    } catch (e) {
      rethrow;
    }
  }

  // Helper widget to display a single analytics card
  Widget _buildAnalyticsCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
    String? subtitle,
  }) {
    return StatCard(
      title: title,
      value: '${amount.toStringAsFixed(2)} TZS',
      subtitle: subtitle,
      icon: icon,
      iconColor: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Payment Analytics',
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
            onPressed: () {
              ApiService.clearCache();
              setState(() {
                _analyticsFuture = _fetchAnalyticsData();
              });
            },
            tooltip: 'Refresh Data',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ApiService.clearCache();
          setState(() {
            _analyticsFuture = _fetchAnalyticsData();
          });
        },
        color: AppTheme.primaryColor,
        child: FutureBuilder<PaymentAnalytics>(
          future: _analyticsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ModernLoading(
                message: 'Loading payment analytics...',
              );
            } else if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Error Loading Analytics',
                subtitle: 'Failed to load payment data: ${snapshot.error}',
                action: ElevatedButton.icon(
                  onPressed: () {
                    ApiService.clearCache();
                    setState(() {
                      _analyticsFuture = _fetchAnalyticsData();
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              );
            } else if (snapshot.hasData) {
              final analytics = snapshot.data!;
              return CustomScrollView(
                slivers: [
                  // Header Section
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
                            child: const Icon(
                              Icons.analytics_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Payment Analytics',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Financial insights and performance metrics',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Today & Recent Section
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
                            child: _buildAnalyticsCard(
                              title: 'Today',
                              amount: analytics.today,
                              color: AppTheme.successColor,
                              icon: Icons.today_rounded,
                              subtitle: 'Current day',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildAnalyticsCard(
                              title: 'Last 24h',
                              amount: analytics.last24Hours,
                              color: AppTheme.infoColor,
                              icon: Icons.access_time_rounded,
                              subtitle: 'Rolling 24h',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Monthly Section
                  const SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'Monthly Overview',
                      subtitle: 'Current and previous month data',
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
                                child: _buildAnalyticsCard(
                                  title: 'This Month',
                                  amount: analytics.thisMonth,
                                  color: AppTheme.primaryColor,
                                  icon: Icons.calendar_month_rounded,
                                  subtitle: 'Month to date',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildAnalyticsCard(
                                  title: 'Daily Average',
                                  amount: analytics.dailyAverageThisMonth,
                                  color: Colors.purple,
                                  icon: Icons.show_chart_rounded,
                                  subtitle: 'This month avg',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildAnalyticsCard(
                            title: 'Last Month',
                            amount: analytics.lastMonth,
                            color: AppTheme.warningColor,
                            icon: Icons.calendar_today_rounded,
                            subtitle: 'Previous month total',
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Yearly Section
                  const SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'Yearly Performance',
                      subtitle: 'Annual revenue tracking',
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildAnalyticsCard(
                        title: 'This Year',
                        amount: analytics.thisYear,
                        color: Colors.indigo,
                        icon: Icons.calendar_view_month_rounded,
                        subtitle: 'Year to date total',
                      ),
                    ),
                  ),
                  
                  // Footer
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.textTertiary.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AppTheme.textSecondary,
                            size: 24,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pull down to refresh data',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Data is cached for better performance',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Bottom padding
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 32),
                  ),
                ],
              );
            } else {
              return const EmptyState(
                icon: Icons.analytics_outlined,
                title: 'No Data Available',
                subtitle: 'No payment analytics data found',
              );
            }
          },
        ),
      ),
    );
  }
}


