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
    final payments = await ApiService.fetchPayments();
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
      appBar: AppBar(title: const Text("💰 Payments")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search by phone number',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _searchText = value;
                _applySearch();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPayments.isEmpty
                ? const Center(child: Text("No payments found."))
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredPayments.length,
              itemBuilder: (context, index) {
                final p = _filteredPayments[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet, size: 36, color: Colors.green),
                    title: Text(
                      p['username'] ?? 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text("📍 Location: ${p['location']}"),
                        Text("💵 Amount: ${p['amount']}"),
                        Text("⏳ Duration: ${p['duration']}"),
                        Text("📞 Phone: ${p['phone']}"),
                        Text("🕒 Timestamp: ${p['timestamp']}"),
                      ],
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
