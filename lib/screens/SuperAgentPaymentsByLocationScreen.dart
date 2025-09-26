import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/ApiService.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

class SuperAgentPaymentsByLocationScreen extends StatefulWidget {
  const SuperAgentPaymentsByLocationScreen({Key? key}) : super(key: key);

  @override
  State<SuperAgentPaymentsByLocationScreen> createState() => _SuperAgentPaymentsByLocationScreenState();
}

class _SuperAgentPaymentsByLocationScreenState extends State<SuperAgentPaymentsByLocationScreen> {
  final AuthController _authController = Get.find<AuthController>();

  String _period = 'last24h'; // options: 'today' | 'last24h'
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _counts = [];
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final locations = _authController.userLocations;
      if (locations.isEmpty) {
        setState(() {
          _counts = [];
          _totalCount = 0;
          _loading = false;
        });
        return;
      }
      final data = await ApiService.fetchPaymentsByLocation(locations: locations, period: _period);
      final list = (data['counts'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _counts = list;
        _totalCount = (data['total_count'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load payments by location: $e';
        _loading = false;
      });
    }
  }

  void _setPeriod(String period) {
    if (_period != period) {
      setState(() => _period = period);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _period == 'today' ? 'Today\'s payments by location' : 'Last 24 hours payments by location';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Payments by Location',
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
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primaryColor,
        child: _loading
            ? const ModernLoading(message: 'Loading payments by location...')
            : _error.isNotEmpty
                ? EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Error Loading Data',
                    subtitle: _error,
                    action: ElevatedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: SectionHeader(
                          title: 'Payments by Location',
                          subtitle: subtitle,
                          action: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ChoiceChip(
                                label: const Text('Today'),
                                selected: _period == 'today',
                                onSelected: (v) => _setPeriod('today'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Last 24h'),
                                selected: _period == 'last24h',
                                onSelected: (v) => _setPeriod('last24h'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: ModernCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.location_city_rounded, color: AppTheme.warningColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Total payments: $_totalCount',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_counts.isEmpty)
                                const Text('No payments found for selected period and locations')
                              else
                                ..._counts.map((row) {
                                  final loc = (row['location'] ?? 'Unknown').toString();
                                  final count = (row['count'] ?? 0) as int;
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
                                            loc,
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                        ModernBadge(
                                          text: '$count',
                                          backgroundColor: AppTheme.warningColor,
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
      ),
    );
  }
}
