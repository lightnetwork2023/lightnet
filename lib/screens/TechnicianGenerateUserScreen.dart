import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ApiService.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_components.dart';

/// One voucher per request at 10M/10M; location is always general on the server (`3h` or `1d`).
class TechnicianGenerateUserScreen extends StatefulWidget {
  const TechnicianGenerateUserScreen({super.key});

  @override
  State<TechnicianGenerateUserScreen> createState() => _TechnicianGenerateUserScreenState();
}

class _TechnicianGenerateUserScreenState extends State<TechnicianGenerateUserScreen> {
  String _durationKey = '1d';
  bool _busy = false;

  static const Map<String, String> _durations = {
    '3h': '3 hours',
    '1d': '1 day',
  };

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final result = await ApiService.generateOneUser(durationKey: _durationKey);
      if (!mounted) return;
      final user = result['user'] as Map<String, dynamic>?;
      final username = user?['username']?.toString() ?? '';
      final daily = result['daily_count_today'];
      final limit = result['daily_limit'];

      final messenger = ScaffoldMessenger.of(context);

      void copySnack(String label) {
        messenger.showSnackBar(
          SnackBar(content: Text('$label copied')),
        );
      }

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
                  'Location: general',
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
                        copySnack('Voucher code');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Password is not shown in the app.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Text('Speed: ${user?['speed_limit'] ?? '10M/10M'}'),
                Text('Session (seconds): ${user?['session_timeout'] ?? ''}'),
                if (daily != null && limit != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Today: $daily / $limit generations',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
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
        title: const Text('Generate one user'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Creates one voucher at location general (10 Mbps). Pick duration, then generate.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          Text('Duration', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durations.entries.map((e) {
              final selected = _durationKey == e.key;
              return ChoiceChip(
                label: Text(e.value),
                selected: selected,
                onSelected: _busy
                    ? null
                    : (sel) {
                        if (sel) setState(() => _durationKey = e.key);
                      },
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
                  : const Text('Generate one voucher'),
            ),
          ),
        ],
      ),
    );
  }
}
