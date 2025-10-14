import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:lightnetwork/controllers/auth_controller.dart';
import 'package:lightnetwork/controllers/HomeInternetService.dart';
import 'package:lightnetwork/models/home_customer.dart';
import '../theme/app_theme.dart';

class HomeUserPaymentScreen extends StatefulWidget {
  const HomeUserPaymentScreen({super.key});

  @override
  State<HomeUserPaymentScreen> createState() => _HomeUserPaymentScreenState();
}

class _HomeUserPaymentScreenState extends State<HomeUserPaymentScreen> {
  final _auth = Get.find<AuthController>();
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  
  String _provider = 'Airtel';
  bool _loading = false;
  HomeCustomer? _customer;

  final List<String> _providers = ['Airtel', 'Tigo', 'Mpesa', 'Halopesa', 'Azampesa'];

  @override
  void initState() {
    super.initState();
    _loadCustomer();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    try {
      final customerId = _auth.homeCustomerId;
      if (customerId.isEmpty) return;
      
      final customer = await HomeInternetService.getCustomer(customerId);
      if (!mounted) return;
      
      setState(() {
        _customer = customer;
        if (customer != null) {
          _phoneCtrl.text = customer.phone;
        }
      });
    } catch (e) {
      // Silently fail, customer data is optional
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Make Payment'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primaryGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_customer != null) ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.account_circle_rounded, color: AppTheme.primaryColor, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Account Information',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _buildInfoRow('Name', _customer!.name),
                        const SizedBox(height: 12),
                        _buildInfoRow('Customer ID', _customer!.id),
                        const SizedBox(height: 12),
                        _buildInfoRow('Plan Amount', 'TZS ${NumberFormat('#,##0').format(_customer!.planAmount)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const Text(
                'Payment Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: 'Amount (TZS)',
                  prefixIcon: const Icon(Icons.payments_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  helperText: 'Enter the amount you want to pay',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Amount is required';
                  final amount = double.tryParse(v);
                  if (amount == null || amount <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  helperText: 'Enter your mobile money number',
                ),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Phone number is required';
                  if (v.length < 10) return 'Enter a valid phone number';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Payment Provider',
                  prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _provider,
                    items: _providers
                        .map((p) => DropdownMenuItem<String>(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => _provider = v ?? 'Airtel'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: AppTheme.primaryColor.withOpacity(0.05),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: AppTheme.primaryColor, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Payment Instructions',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text('1. Enter the amount you want to pay', style: TextStyle(fontSize: 13)),
                      SizedBox(height: 6),
                      Text('2. Confirm your phone number', style: TextStyle(fontSize: 13)),
                      SizedBox(height: 6),
                      Text('3. Select your mobile money provider', style: TextStyle(fontSize: 13)),
                      SizedBox(height: 6),
                      Text('4. Approve the payment on your phone', style: TextStyle(fontSize: 13)),
                      SizedBox(height: 6),
                      Text('5. Your payment will be recorded automatically', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _makePayment,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.payment_rounded),
                  label: Text(_loading ? 'Processing Payment...' : 'Pay Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }

  Future<void> _makePayment() async {
    if (!_formKey.currentState!.validate()) return;

    final customerId = _auth.homeCustomerId;
    if (customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer ID not found')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final amount = double.parse(_amountCtrl.text.trim());
      final phone = _phoneCtrl.text.trim();

      // Call the payment API
      final response = await http.post(
        Uri.parse('http://167.179.100.104:5000/make-paymentagent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'amount': amount.toString(),
          'provider': _provider,
          'location': 'HOME_USER',
          'days': 30, // Default to 30 days for home internet
          'durationSeconds': 2592000, // 30 days in seconds
          'quantity': customerId, // Pass customer ID as quantity for tracking
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Payment successful - backend callback will store the payment in Firestore
          // No need to store manually to avoid double recording
          
          if (!mounted) return;
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment successful! Your payment has been recorded.'),
              backgroundColor: AppTheme.successColor,
            ),
          );
          
          // Clear form
          _amountCtrl.clear();
          
          // Navigate back after short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context, true);
          });
        } else {
          throw Exception(data['error'] ?? 'Payment failed');
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'Payment request failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

}
