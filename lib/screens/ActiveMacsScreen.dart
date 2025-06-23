import 'package:flutter/material.dart';

class ActiveMacsScreen extends StatelessWidget {
  final List<dynamic> activeMacs;
  const ActiveMacsScreen({Key? key, required this.activeMacs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Devices'),
      ),
      body: activeMacs.isEmpty
          ? const Center(child: Text('No active devices found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: activeMacs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final mac = activeMacs[index];
                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Icon(Icons.memory, color: Colors.green.shade800),
                    ),
                    title: Text(
                      mac['mac_address'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.router, size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 4),
                            Text('IP: ${mac['ip_address'] ?? 'N/A'}'),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text('Location: ${mac['location'] ?? 'N/A'}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
} 