import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/q20_monitor_tab.dart';

class Q20MonitorScreen extends StatefulWidget {
  const Q20MonitorScreen({super.key});

  @override
  State<Q20MonitorScreen> createState() => _Q20MonitorScreenState();
}

class _Q20MonitorScreenState extends State<Q20MonitorScreen> {
  final GlobalKey<Q20MonitorContentState> _tabKey = GlobalKey<Q20MonitorContentState>();
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _tabKey.currentState?.refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'LIGHTNET Q20',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Q20MonitorContent(key: _tabKey),
    );
  }
}
