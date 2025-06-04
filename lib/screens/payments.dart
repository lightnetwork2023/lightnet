// screens/payments_screen.dart
import 'package:flutter/material.dart';
import '../controllers/ApiService.dart';

class PaymentsScreen extends StatefulWidget {
  @override
  _PaymentsScreenState createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List<dynamic> _payments = [];
  List<dynamic> _filteredPayments = [];
  bool _loading = false;
  String _searchText = '';

  void _fetchPayments() async {
    setState(() => _loading = true);
    final payments = await ApiService.fetchRecentPayments();
    setState(() {
      _payments = payments.reversed.toList(); // Newest at the top
      _applySearch();
      _loading = false;
    });
  }

  void _applySearch() {
    setState(() {
      _filteredPayments = _payments.where((p) {
        final phone = p['phone']?.toString().toLowerCase() ?? '';
        return phone.contains(_searchText.toLowerCase());
      }).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🔄 Recent Payments (24h)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPayments,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search by phone number',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                  _applySearch();
                });
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPayments.isEmpty
                    ? const Center(child: Text("No recent payments found."))
                    : ListView.builder(
                        itemCount: _filteredPayments.length,
                        itemBuilder: (context, index) {
                          final payment = _filteredPayments[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.payment, color: Colors.green),
                              title: Text(payment['username'] ?? 'Unknown'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Phone: ${payment['phone'] ?? 'N/A'}"),
                                  Text("Location: ${payment['location'] ?? 'N/A'}"),
                                  Text("Amount: ${payment['amount'] ?? 'N/A'}"),
                                  Text("Duration: ${payment['duration'] ?? 'N/A'}"),
                                ],
                              ),
                              trailing: Text(
                                payment['timestamp']?.toString().split('.')[0] ?? 'N/A',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
