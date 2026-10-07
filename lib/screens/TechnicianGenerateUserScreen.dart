import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/ApiService.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

/// One voucher per request at 10M/10M. Location is the technician's name.
class TechnicianGenerateUserScreen extends StatefulWidget {
  const TechnicianGenerateUserScreen({super.key});

  @override
  State<TechnicianGenerateUserScreen> createState() => _TechnicianGenerateUserScreenState();
}

class _TechnicianGenerateUserScreenState extends State<TechnicianGenerateUserScreen> {
  String _durationKey = '4h';
  bool _busy = false;
  bool _loadingActive = true;
  String? _activeError;
  List<Map<String, dynamic>> _active = [];

  static const Map<String, String> _durations = {
    '4h': '4 hours',
    '1d': '24 hours',
  };

  String get _techName {
    final auth = Get.find<AuthController>();
    final name = auth.userName.trim();
    if (name.isNotEmpty) return name;
    return auth.user?.email ?? 'Technician';
  }

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    setState(() {
      _loadingActive = _active.isEmpty;
      _activeError = null;
    });
    try {
      final data = await ApiService.fetchTechnicianActiveVouchers();
      final raw = (data['vouchers'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _active = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadingActive = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeError = e.toString().replaceFirst('Exception: ', '');
        _loadingActive = false;
      });
    }
  }

  String _durationLabel(Map<String, dynamic> v) {
    final key = v['duration_key']?.toString() ?? '';
    if (_durations.containsKey(key)) return _durations[key]!;
    final timeout = v['session_timeout'];
    final secs = timeout is num ? timeout.toInt() : int.tryParse('$timeout') ?? 0;
    if (secs > 0 && secs <= 4 * 3600 + 60) return '4 hours';
    if (secs > 0 && secs <= 24 * 3600 + 60) return '24 hours';
    return key.isNotEmpty ? key : 'Voucher';
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voucher code copied')));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final result = await ApiService.generateOneUser(durationKey: _durationKey);
      if (!mounted) return;
      final user = result['user'] as Map<String, dynamic>?;
      final username = user?['username']?.toString() ?? '';
      final location = user?['location']?.toString() ?? _techName;
      final daily = result['daily_count_today'];
      final limit = result['daily_limit'];
      final monthly = result['monthly_count'];
      final durLabel = _durations[_durationKey] ?? _durationKey;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Voucher created'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Location: $location',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        'Voucher code\n$username',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy voucher code',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => _copy(username),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Duration: $durLabel'),
                Text('Speed: ${user?['speed_limit'] ?? '10M/10M'}'),
                if (daily != null && limit != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Today: $daily / $limit',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
                if (monthly != null)
                  Text(
                    'This month: $monthly',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      await _loadActive();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _activeCard(Map<String, dynamic> v) {
    final code = v['username']?.toString() ?? '';
    final used = v['used'] == true;
    final statusColor = used ? Colors.orange : Colors.green;
    final statusLabel = used ? 'In use' : 'Available';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Row(
        children: [
          Icon(Icons.confirmation_number_outlined, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  code,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_durationLabel(v)} · $statusLabel',
                  style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: code.isEmpty ? null : () => _copy(code),
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Generate voucher'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _loadActive,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadActive,
        color: AppTheme.primaryColor,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Creates one voucher at your name as location (10 Mbps). Choose 4 hours or 24 hours.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8ECF0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Location', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
                        Text(_techName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Duration', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: _durations.entries.map((e) {
                final selected = _durationKey == e.key;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: e.key == '4h' ? 8 : 0),
                    child: ChoiceChip(
                      label: Center(child: Text(e.value)),
                      selected: selected,
                      onSelected: _busy
                          ? null
                          : (sel) {
                              if (sel) setState(() => _durationKey = e.key);
                            },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          SizedBox(width: 12),
                          Text('Please wait…'),
                        ],
                      )
                    : const Text('Generate voucher'),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Active vouchers at $_techName',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Unused or still running. Copy a code if you closed the dialog.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_loadingActive)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_activeError != null)
              Text(_activeError!, style: const TextStyle(color: AppTheme.errorColor))
            else if (_active.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8ECF0)),
                ),
                child: const Text(
                  'No active vouchers at this location yet.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._active.map(_activeCard),
          ],
        ),
      ),
    );
  }
}
