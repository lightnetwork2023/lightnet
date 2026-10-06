import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/q20_monitor_tab.dart';

class Q20MonitorScreen extends StatelessWidget {
  const Q20MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LightNet Q20'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: const Q20MonitorContent(),
    );
  }
}
