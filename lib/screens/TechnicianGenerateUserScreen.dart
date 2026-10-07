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

      final messenger = ScaffoldMessenger.of(context);

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
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: username));
                        messenger.showSnackBar(const SnackBar(content: Text('Voucher code copied')));
                      },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Generate voucher'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: ListView(
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
          const SizedBox(height: 32),
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
        ],
      ),
    );
  }
}
