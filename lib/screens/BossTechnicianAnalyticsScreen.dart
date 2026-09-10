import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';
import 'TechnicianCommissionPage.dart';

class BossTechnicianAnalyticsScreen extends StatefulWidget {
  const BossTechnicianAnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<BossTechnicianAnalyticsScreen> createState() => _BossTechnicianAnalyticsScreenState();
}

class _BossTechnicianAnalyticsScreenState extends State<BossTechnicianAnalyticsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allTechnicians = [];
  List<Map<String, dynamic>> _filteredTechnicians = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .get();

      // Diagnostic: log every unique role + any user matching 'shafi'/'shafy'
      final Set<String> rolesSeen = {};
      for (final d in snap.docs) {
        final data = d.data();
        final role = (data['role'] ?? '<null>').toString();
        rolesSeen.add(role);
        final name = (data['name'] ?? '').toString().toLowerCase();
        final email = (data['email'] ?? '').toString().toLowerCase();
        if (name.contains('shaf') || email.contains('shaf')) {
          debugPrint('[TechAnalytics] Shaf* match: id=${d.id} '
              'name="${data['name']}" email="${data['email']}" '
              'role="${data['role']}" location="${data['location']}" '
              'locations=${data['locations']}');
        }
      }
      debugPrint('[TechAnalytics] Total users=${snap.docs.length} '
          'distinctRoles=$rolesSeen');

      _allTechnicians = snap.docs
          .where((doc) {
            final data = doc.data();
            final role = (data['role'] ?? '').toString().trim().toLowerCase();
            // Accept exact 'technician', or any role that contains 'tech'
            // (covers 'Tech', 'tech support', 'tecnician' typos, etc.)
            return role == 'technician' || role.contains('tech');
          })
          .map((doc) {
        final data = doc.data();
        final String location = (data['location'] ?? '').toString();
        final List<String> locations = (data['locations'] is List)
            ? List<String>.from(data['locations'])
            : <String>[];
        final String resolvedName = () {
          final n = (data['name'] ?? '').toString().trim();
          if (n.isNotEmpty) return n;
          final e = (data['email'] ?? '').toString().trim();
          if (e.isNotEmpty) return e;
          return 'Unnamed';
        }();
        return {
          'id': doc.id,
          'name': resolvedName,
          'email': (data['email'] ?? '') as String,
          'location': location,
          'locations': locations,
        };
      }).toList();

      _filteredTechnicians = List<Map<String, dynamic>>.from(_allTechnicians);
    } catch (e) {
      _error = 'Failed to load technicians: $e';
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
        _filteredTechnicians = List<Map<String, dynamic>>.from(_allTechnicians);
      });
      return;
    }
    setState(() {
      _filteredTechnicians = _allTechnicians.where((t) {
        final name = (t['name'] ?? '').toString().toLowerCase();
        final email = (t['email'] ?? '').toString().toLowerCase();
        final location = (t['location'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q) || location.contains(q);
      }).toList();
    });
  }

  void _openAnalytics(Map<String, dynamic> tech) {
    final String location = (tech['location'] ?? '').toString();
    final List<String> locations = (tech['locations'] is List)
        ? List<String>.from(tech['locations'] as List)
        : <String>[];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechnicianCommissionPage(
          location: locations.isEmpty && location.isNotEmpty ? location : null,
          locations: locations.isNotEmpty ? locations : null,
          technicianName: tech['name'] as String,
          technicianId: tech['id'] as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Technician Analytics',
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
            onPressed: _loadTechnicians,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const ModernLoading(message: 'Loading technicians...')
          : _error.isNotEmpty
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Error Loading Technicians',
                  subtitle: _error,
                  action: ElevatedButton.icon(
                    onPressed: _loadTechnicians,
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
                      child: _filteredTechnicians.isEmpty
                          ? const EmptyState(
                              icon: Icons.person_search_rounded,
                              title: 'No Technicians Found',
                              subtitle: 'Try a different search or check later',
                            )
                          : ListView.builder(
                              itemCount: _filteredTechnicians.length,
                              itemBuilder: (context, index) {
                                final tech = _filteredTechnicians[index];
                                final String location = (tech['location'] ?? '').toString();
                                final List<String> locations = (tech['locations'] is List)
                                    ? List<String>.from(tech['locations'] as List)
                                    : <String>[];
                                return ModernListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.handyman_rounded, color: Colors.teal),
                                  ),
                                  title: Text(
                                    tech['name'] ?? 'Unnamed',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  subtitle: Text(
                                    locations.isNotEmpty
                                        ? 'Locations: ${locations.join(', ')}'
                                        : (location.isNotEmpty ? 'Location: $location' : 'No location assigned'),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                  ),
                                  trailing: ElevatedButton.icon(
                                    onPressed: () => _openAnalytics(tech),
                                    icon: const Icon(Icons.analytics_rounded),
                                    label: const Text('View'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  onTap: () => _openAnalytics(tech),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
