import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'LocationManagementScreen.dart';

class LocationAnalyticsScreen extends StatefulWidget {
  const LocationAnalyticsScreen({super.key});

  @override
  State<LocationAnalyticsScreen> createState() => _LocationAnalyticsScreenState();
}

enum TimePeriod {
  today,
  last24Hours,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

class _LocationAnalyticsScreenState extends State<LocationAnalyticsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<LocationStats> _locationStats = [];
  String? _error;
  TimePeriod _selectedPeriod = TimePeriod.thisMonth; // Default: this month
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _loadLocationAnalytics();
  }

  Future<void> _loadLocationAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Calculate date range based on selected period
      final dateRange = _getDateRange();
      
      // Query payments within the selected period
      Query query = _firestore.collection('payments');
      
      if (dateRange['start'] != null) {
        query = query.where('created_at', isGreaterThanOrEqualTo: dateRange['start']);
      }
      if (dateRange['end'] != null) {
        query = query.where('created_at', isLessThan: dateRange['end']);
      }

      final paymentsSnapshot = await query.get();

      // Group payments by location
      Map<String, LocationStatsData> locationData = {};

      for (var doc in paymentsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final location = data['location'] as String? ?? 'Unknown';
        final amount = (data['amount'] ?? 0).toDouble();
        final createdAt = data['created_at'] as Timestamp?;

        if (!locationData.containsKey(location)) {
          locationData[location] = LocationStatsData(
            totalRevenue: 0,
            paymentCount: 0,
            lastPaymentAt: null,
          );
        }

        locationData[location]!.totalRevenue += amount;
        locationData[location]!.paymentCount += 1;
        
        if (createdAt != null) {
          if (locationData[location]!.lastPaymentAt == null ||
              createdAt.compareTo(locationData[location]!.lastPaymentAt!) > 0) {
            locationData[location]!.lastPaymentAt = createdAt;
          }
        }
      }

      // Get ALL locations from locations collection
      final locationsSnapshot = await _firestore.collection('locations').get();

      // Build stats list - include ALL locations, even those with no payments
      List<LocationStats> stats = [];
      
      for (var doc in locationsSnapshot.docs) {
        final locationId = doc.id;
        final metadata = doc.data();
        
        // Get payment data for this location (if any)
        final paymentData = locationData[locationId];
        
        stats.add(LocationStats(
          locationId: locationId,
          totalRevenue: paymentData?.totalRevenue ?? 0.0,
          paymentCount: paymentData?.paymentCount ?? 0,
          lastPaymentAt: paymentData?.lastPaymentAt,
          parentLocation: metadata['parent_location'] as String?,
          type: metadata['type'] as String?,
        ));
      }

      // Aggregate sublocation data into main locations
      for (var mainLocation in stats.where((s) => s.type == 'main')) {
        // Find all sublocations of this main location
        final sublocations = stats.where((s) => s.parentLocation == mainLocation.locationId);
        
        double sublocationRevenue = 0;
        int sublocationPayments = 0;
        Timestamp? latestPayment = mainLocation.lastPaymentAt;
        
        for (var sublocation in sublocations) {
          sublocationRevenue += sublocation.totalRevenue;
          sublocationPayments += sublocation.paymentCount;
          
          // Track the latest payment across all sublocations
          if (sublocation.lastPaymentAt != null) {
            if (latestPayment == null || 
                sublocation.lastPaymentAt!.compareTo(latestPayment) > 0) {
              latestPayment = sublocation.lastPaymentAt;
            }
          }
        }
        
        // Update main location with aggregated totals
        if (sublocationRevenue > 0 || sublocationPayments > 0) {
          final index = stats.indexOf(mainLocation);
          stats[index] = LocationStats(
            locationId: mainLocation.locationId,
            totalRevenue: mainLocation.totalRevenue + sublocationRevenue,
            paymentCount: mainLocation.paymentCount + sublocationPayments,
            lastPaymentAt: latestPayment,
            parentLocation: mainLocation.parentLocation,
            type: mainLocation.type,
          );
        }
      }

      // Sort by total revenue (highest to lowest)
      stats.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

      setState(() {
        _locationStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, Timestamp?> _getDateRange() {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;

    switch (_selectedPeriod) {
      case TimePeriod.today:
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case TimePeriod.last24Hours:
        start = now.subtract(const Duration(hours: 24));
        end = now;
        break;
      case TimePeriod.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        break;
      case TimePeriod.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        start = lastMonth;
        end = DateTime(now.year, now.month, 1);
        break;
      case TimePeriod.thisYear:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year + 1, 1, 1);
        break;
      case TimePeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          start = _customStartDate;
          end = _customEndDate!.add(const Duration(days: 1));
        }
        break;
    }

    return {
      'start': start != null ? Timestamp.fromDate(start) : null,
      'end': end != null ? Timestamp.fromDate(end) : null,
    };
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case TimePeriod.today:
        return 'Today';
      case TimePeriod.last24Hours:
        return 'Last 24 Hours';
      case TimePeriod.thisMonth:
        return 'This Month';
      case TimePeriod.lastMonth:
        return 'Last Month';
      case TimePeriod.thisYear:
        return 'This Year';
      case TimePeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${_formatDate(_customStartDate!)} - ${_formatDate(_customEndDate!)}';
        }
        return 'Custom Period';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatCurrency(double amount) {
    return 'TZS ${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}';
  }

  String _formatCurrencyCompact(double amount) {
    if (amount >= 1000000000) {
      // Billions
      return '${(amount / 1000000000).toStringAsFixed(1)}B';
    } else if (amount >= 1000000) {
      // Millions
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      // Thousands
      return '${(amount / 1000).toStringAsFixed(1)}K';
    } else {
      // Less than 1000, show full amount
      return amount.toStringAsFixed(0);
    }
  }

  String _formatLastPayment(Timestamp? timestamp) {
    if (timestamp == null) return 'No payments yet';
    
    final dateTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Color _getRankColor(int rank) {
    if (rank == 0) return Colors.amber;
    if (rank == 1) return Colors.grey[400]!;
    if (rank == 2) return Colors.brown[400]!;
    return AppTheme.primaryColor;
  }

  IconData _getRankIcon(int rank) {
    if (rank == 0) return Icons.emoji_events;
    if (rank == 1) return Icons.military_tech;
    if (rank == 2) return Icons.workspace_premium;
    return Icons.location_on;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location Analytics',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _getPeriodLabel(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LocationManagementScreen(),
                ),
              ).then((_) => _loadLocationAnalytics());
            },
            tooltip: 'Manage Locations',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLocationAnalytics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Time Period',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildFilterOption(
              'Today',
              TimePeriod.today,
              Icons.today,
            ),
            _buildFilterOption(
              'Last 24 Hours',
              TimePeriod.last24Hours,
              Icons.access_time,
            ),
            _buildFilterOption(
              'This Month',
              TimePeriod.thisMonth,
              Icons.calendar_today,
            ),
            _buildFilterOption(
              'Last Month',
              TimePeriod.lastMonth,
              Icons.calendar_month,
            ),
            _buildFilterOption(
              'This Year',
              TimePeriod.thisYear,
              Icons.date_range,
            ),
            _buildFilterOption(
              'Custom Period',
              TimePeriod.custom,
              Icons.date_range_outlined,
              onTap: () async {
                Navigator.pop(context);
                await _selectCustomDateRange();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(
    String title,
    TimePeriod period,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedPeriod == period;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppTheme.primaryColor : Colors.grey,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppTheme.primaryColor : Colors.black,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppTheme.primaryColor)
          : null,
      onTap: onTap ??
          () {
            setState(() {
              _selectedPeriod = period;
            });
            Navigator.pop(context);
            _loadLocationAnalytics();
          },
    );
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedPeriod = TimePeriod.custom;
      });
      _loadLocationAnalytics();
    }
  }

  void _showLocationReassignDialog(LocationStats stats) {
    String locationType = stats.type == 'main' ? 'main' : 'sublocation';
    String? selectedParent = stats.parentLocation;
    
    // Get list of locations marked as 'main' type ONLY for parent selection
    final mainLocations = _locationStats
        .where((loc) {
          print('Location: ${loc.locationId}, Type: ${loc.type}'); // Debug
          return loc.type == 'main' && loc.locationId != stats.locationId;
        })
        .map((loc) => loc.locationId)
        .toList();
    
    print('Main locations found: $mainLocations'); // Debug

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.location_on, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reassign Location',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location Name
                  Text(
                    stats.locationId,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Location Type Selection
                  const Text(
                    'Location Type:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('Main Location'),
                    subtitle: const Text('Independent location'),
                    value: 'main',
                    groupValue: locationType,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (value) {
                      setDialogState(() {
                        locationType = value!;
                        selectedParent = null;
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Sublocation'),
                    subtitle: const Text('Under a main location'),
                    value: 'sublocation',
                    groupValue: locationType,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (value) {
                      setDialogState(() {
                        locationType = value!;
                      });
                    },
                  ),
                  // Parent Location Selection (only if sublocation)
                  if (locationType == 'sublocation') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Parent Location:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (mainLocations.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning, color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No main locations available',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'First, mark other locations as "Main Location" before you can assign them as parents.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: selectedParent,
                            hint: const Text('Select parent location'),
                            items: mainLocations.map((location) {
                              return DropdownMenuItem(
                                value: location,
                                child: Text(location),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedParent = value;
                              });
                            },
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (locationType == 'sublocation' && selectedParent == null && mainLocations.isNotEmpty)
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await _updateLocationAssignment(
                          stats.locationId,
                          locationType,
                          selectedParent,
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateLocationAssignment(
    String locationId,
    String locationType,
    String? parentLocation,
  ) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Updating location...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Update Firestore
      final locationDoc = _firestore.collection('locations').doc(locationId);
      
      if (locationType == 'main') {
        // Set as main location (no parent)
        await locationDoc.set({
          'parent_location': null,
          'type': 'main',
        }, SetOptions(merge: true));
      } else {
        // Set as sublocation with parent
        await locationDoc.set({
          'parent_location': parentLocation,
          'type': 'sublocation',
        }, SetOptions(merge: true));
      }

      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Successfully updated $locationId to ${locationType == 'main' ? 'main location' : 'sublocation of $parentLocation'}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // Reload data to reflect changes
        _loadLocationAnalytics();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: ModernLoading(message: 'Loading analytics...'));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadLocationAnalytics,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_locationStats.isEmpty) {
      return const EmptyState(
        icon: Icons.analytics_outlined,
        title: 'No locations found',
        subtitle: 'Create locations in Firestore to see them here',
      );
    }

    // Filter to show only main locations on front page
    final mainLocationsOnly = _locationStats
        .where((s) => s.type == 'main' || s.parentLocation == null)
        .toList();

    return Column(
      children: [
        // Summary Header
        _buildSummaryHeader(),
        // Location List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadLocationAnalytics,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mainLocationsOnly.length,
              itemBuilder: (context, index) {
                return _buildLocationCard(mainLocationsOnly[index], index);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader() {
    // Only count main locations and standalone locations (not sublocations)
    // because main locations already include their sublocation totals
    final locationsToCount = _locationStats.where((s) => 
      s.parentLocation == null || s.type == 'main'
    );
    
    final totalRevenue = locationsToCount.fold<double>(
      0,
      (sum, stat) => sum + stat.totalRevenue,
    );
    final totalPayments = locationsToCount.fold<int>(
      0,
      (sum, stat) => sum + stat.paymentCount,
    );
    final activeLocations = locationsToCount.where((s) => s.paymentCount > 0).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryColor, AppTheme.accentColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Total Performance',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                null,
                _formatCurrency(totalRevenue),
                'Total Revenue',
              ),
              _buildSummaryItem(
                Icons.receipt_long,
                totalPayments.toString(),
                'Payments',
              ),
              _buildSummaryItem(
                Icons.location_city,
                activeLocations.toString(),
                'Active Locations',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData? icon, String value, String label) {
    return Column(
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 8),
        ],
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(LocationStats stats, int rank) {
    final isMainLocation = stats.parentLocation == null;
    final hasRevenue = stats.totalRevenue > 0;
    
    // Count sublocations if this is a main location
    final sublocations = stats.type == 'main'
        ? _locationStats.where((s) => s.parentLocation == stats.locationId).toList()
        : <LocationStats>[];
    
    final sublocationCount = sublocations.length;
    final dormantCount = sublocations.where((s) => s.totalRevenue == 0).length;

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showLocationDetails(stats),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rank and Location Name
              Row(
                children: [
                  // Rank Badge
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _getRankColor(rank).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getRankIcon(rank),
                          color: _getRankColor(rank),
                          size: 20,
                        ),
                        Text(
                          '#${rank + 1}',
                          style: TextStyle(
                            color: _getRankColor(rank),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Location Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                stats.locationId,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isMainLocation)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Sub',
                                  style: TextStyle(
                                    color: Colors.orange[800],
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (stats.parentLocation != null)
                          Text(
                            'Parent: ${stats.parentLocation}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        if (sublocationCount > 0)
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_tree,
                                    size: 12,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$sublocationCount sublocation${sublocationCount > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (dormantCount > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning_rounded,
                                      size: 12,
                                      color: Colors.red[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$dormantCount dormant',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Edit Button
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    color: AppTheme.primaryColor,
                    onPressed: () => _showLocationReassignDialog(stats),
                    tooltip: 'Reassign Location',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Stats Grid
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      null,
                      'Revenue',
                      _formatCurrencyCompact(stats.totalRevenue),
                      AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatItem(
                      Icons.receipt,
                      'Payments',
                      stats.paymentCount.toString(),
                      AppTheme.accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatItem(
                      Icons.access_time,
                      'Last Payment',
                      _formatLastPayment(stats.lastPaymentAt),
                      Colors.blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData? icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationDetails(LocationStats stats) {
    // Get sublocations if this is a main location
    final sublocations = stats.type == 'main'
        ? _locationStats.where((s) => s.parentLocation == stats.locationId).toList()
        : <LocationStats>[];
    
    // Sort sublocations: active first, dormant last
    sublocations.sort((a, b) {
      final aActive = a.totalRevenue > 0 ? 1 : 0;
      final bActive = b.totalRevenue > 0 ? 1 : 0;
      if (aActive != bActive) return bActive.compareTo(aActive); // Active first
      return b.totalRevenue.compareTo(a.totalRevenue); // Then by revenue
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stats.locationId,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (sublocations.isNotEmpty)
                            Text(
                              'Includes ${sublocations.length} sublocation${sublocations.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Details
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDetailRow('Total Revenue', _formatCurrency(stats.totalRevenue)),
                    _buildDetailRow('Total Payments', stats.paymentCount.toString()),
                    _buildDetailRow(
                      'Average per Payment',
                      stats.paymentCount > 0
                          ? _formatCurrency(stats.totalRevenue / stats.paymentCount)
                          : 'TZS 0',
                    ),
                    _buildDetailRow(
                      'Last Payment',
                      stats.lastPaymentAt != null
                          ? '${stats.lastPaymentAt!.toDate()}'
                          : 'No payments yet',
                    ),
                    if (stats.parentLocation != null)
                      _buildDetailRow('Parent Location', stats.parentLocation!),
                    _buildDetailRow('Type', stats.type ?? 'Unknown'),
                    
                    // Sublocation Breakdown
                    if (sublocations.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.account_tree, 
                            color: AppTheme.primaryColor, 
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Sublocation Breakdown',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...sublocations.map((subloc) {
                        final isDormant = subloc.totalRevenue == 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDormant ? Colors.red[50] : Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDormant ? Colors.red[200]! : Colors.grey[200]!,
                              width: isDormant ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      subloc.locationId,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDormant ? Colors.red[900] : Colors.black,
                                      ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Sub',
                                          style: TextStyle(
                                            color: Colors.orange[800],
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (isDormant)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.warning_rounded,
                                                size: 10,
                                                color: Colors.red[800],
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                'Dormant',
                                                style: TextStyle(
                                                  color: Colors.red[800],
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Revenue',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        _formatCurrency(subloc.totalRevenue),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Payments',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        '${subloc.paymentCount}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class LocationStatsData {
  double totalRevenue;
  int paymentCount;
  Timestamp? lastPaymentAt;

  LocationStatsData({
    required this.totalRevenue,
    required this.paymentCount,
    this.lastPaymentAt,
  });
}

class LocationStats {
  final String locationId;
  final double totalRevenue;
  final int paymentCount;
  final Timestamp? lastPaymentAt;
  final String? parentLocation;
  final String? type;

  LocationStats({
    required this.locationId,
    required this.totalRevenue,
    required this.paymentCount,
    this.lastPaymentAt,
    this.parentLocation,
    this.type,
  });
}
