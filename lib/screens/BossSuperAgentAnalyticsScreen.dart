import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'PaymentAnalyticsPage.dart';

class BossSuperAgentAnalyticsScreen extends StatefulWidget {
  const BossSuperAgentAnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<BossSuperAgentAnalyticsScreen> createState() => _BossSuperAgentAnalyticsScreenState();
}

class _BossSuperAgentAnalyticsScreenState extends State<BossSuperAgentAnalyticsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allSuperAgents = [];
  List<Map<String, dynamic>> _filteredSuperAgents = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSuperAgents();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuperAgents() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'superagent')
          .get();

      _allSuperAgents = snap.docs.map((doc) {
        final data = doc.data();
        final List<String> locations = data['locations'] != null && data['locations'] is List
            ? List<String>.from(data['locations'])
            : (data['location'] != null && (data['location'] as String).isNotEmpty
                ? <String>[data['location']]
                : <String>[]);
        // Commission shares (defaults if not set)
        double saShare = 0.63;
        double coShare = 0.37;
        try {
          final comm = data['commission'];
          if (comm != null && comm is Map) {
            final saParsed = _parseShare(comm['superagent']);
            final coParsed = _parseShare(comm['company']);
            if (saParsed != null) saShare = saParsed;
            coShare = coParsed ?? (1.0 - saShare);
          } else if (data['superagent_percent'] != null) {
            final legacy = _parseShare(data['superagent_percent']);
            if (legacy != null) {
              saShare = legacy;
              coShare = 1.0 - saShare;
            }
          }
          saShare = saShare.clamp(0.0, 1.0);
          coShare = (1.0 - saShare).clamp(0.0, 1.0);
        } catch (_) {
          saShare = 0.63;
          coShare = 0.37;
        }
        return {
          'id': doc.id,
          'name': (data['name'] ?? data['email'] ?? 'Unnamed') as String,
          'email': (data['email'] ?? '') as String,
          'locations': locations,
          'commission_sa': saShare,
          'commission_co': coShare,
        };
      }).toList();

      _filteredSuperAgents = List<Map<String, dynamic>>.from(_allSuperAgents);
    } catch (e) {
      _error = 'Failed to load superagents: $e';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _filteredSuperAgents = List<Map<String, dynamic>>.from(_allSuperAgents);
      });
      return;
    }
    setState(() {
      _filteredSuperAgents = _allSuperAgents.where((sa) {
        final name = (sa['name'] ?? '').toString().toLowerCase();
        final email = (sa['email'] ?? '').toString().toLowerCase();
        final locations = (sa['locations'] as List<String>).join(', ').toLowerCase();
        return name.contains(q) || email.contains(q) || locations.contains(q);
      }).toList();
    });
  }

  void _openAnalytics(Map<String, dynamic> sa) {
    final List<String> locations = (sa['locations'] as List<String>);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentAnalyticsPage(
          userRole: 'superagent', // Force superagent context to enable split and location-filtered summary
          locations: locations,
          superAgentName: sa['name'] as String,
          commissionSuperAgent: (sa['commission_sa'] as double?) ?? 0.63,
          commissionCompany: (sa['commission_co'] as double?) ?? 0.37,
        ),
      ),
    );
  }

  // Helper to parse share values from number or string (supports 0-1 or 0-100)
  double? _parseShare(dynamic v) {
    if (v == null) return null;
    double? d;
    if (v is num) {
      d = v.toDouble();
    } else if (v is String) {
      d = double.tryParse(v);
    }
    if (d == null) return null;
    if (d > 1.0) return d / 100.0;
    if (d < 0.0) return 0.0;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'SuperAgent Analytics',
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
            onPressed: _loadSuperAgents,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const ModernLoading(message: 'Loading superagents...')
          : _error.isNotEmpty
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Error Loading SuperAgents',
                  subtitle: _error,
                  action: ElevatedButton.icon(
                    onPressed: _loadSuperAgents,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                )
              : Column(
                  children: [
                    ModernSearchBar(
                      hintText: 'Search by name, email or location...',
                      controller: _searchController,
                      onClear: () {
                        _searchController.clear();
                        _applyFilter();
                      },
                    ),
                    Expanded(
                      child: _filteredSuperAgents.isEmpty
                          ? const EmptyState(
                              icon: Icons.person_search_rounded,
                              title: 'No SuperAgents Found',
                              subtitle: 'Try a different search or check later',
                            )
                          : ListView.builder(
                              itemCount: _filteredSuperAgents.length,
                              itemBuilder: (context, index) {
                                final sa = _filteredSuperAgents[index];
                                final locations = (sa['locations'] as List<String>);
                                return ModernListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.supervisor_account_rounded, color: Colors.purple),
                                  ),
                                  title: Text(
                                    sa['name'] ?? 'Unnamed',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  subtitle: Text(
                                    locations.isNotEmpty
                                        ? 'Locations: ${locations.join(', ')}'
                                        : 'No locations assigned',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                  ),
                                  trailing: ElevatedButton.icon(
                                    onPressed: locations.isEmpty ? null : () => _openAnalytics(sa),
                                    icon: const Icon(Icons.analytics_rounded),
                                    label: const Text('View'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  onTap: locations.isEmpty ? null : () => _openAnalytics(sa),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
