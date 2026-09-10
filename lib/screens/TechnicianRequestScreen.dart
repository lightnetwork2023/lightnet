import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class TechnicianRequestScreen extends StatefulWidget {
  final String? expenseId;
  final Map<String, dynamic>? existingExpense;

  const TechnicianRequestScreen({
    Key? key,
    this.expenseId,
    this.existingExpense,
  }) : super(key: key);

  @override
  _TechnicianRequestScreenState createState() => _TechnicianRequestScreenState();
}

class _TechnicianRequestScreenState extends State<TechnicianRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _descriptionController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _itemQuantityController = TextEditingController();
  final _itemPriceController = TextEditingController();

  String? _selectedLocation;
  List<_RequestItem> _cartItems = [];
  bool _isSubmitting = false;
  List<String> _locations = [];
  bool _loadingLocations = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _populateExistingData();
  }

  void _populateExistingData() {
    if (widget.existingExpense != null) {
      final e = widget.existingExpense!;
      _descriptionController.text = e['description'] ?? '';
      _selectedLocation = e['location_id'] ?? e['location_name'];
      final items = e['items'] as List<dynamic>? ?? [];
      _cartItems = items.map((item) {
        final d = item as Map<String, dynamic>;
        return _RequestItem(
          name: d['name'] ?? '',
          quantity: (d['quantity'] as num?)?.toInt() ?? 1,
          unitPrice: (d['unit_price'] as num?)?.toDouble() ?? 0,
          totalPrice: (d['total_price'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      setState(() {});
    }
  }

  Future<void> _loadLocations() async {
    try {
      final snapshot = await _firestore.collection('locations').get();
      final mainLocations = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        final type = data['type'] as String?;
        final hasParent = data.containsKey('parentLocation');
        return type == 'main' || (!hasParent && type != 'sublocation');
      }).map((doc) => doc.id).toList();
      setState(() {
        _locations = mainLocations;
        _loadingLocations = false;
      });
    } catch (e) {
      setState(() => _loadingLocations = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading locations: $e')),
        );
      }
    }
  }

  double get _totalAmount =>
      _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);

  void _addItemToCart() {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select a location first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_itemNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter item name')),
      );
      return;
    }
    final quantity = int.tryParse(_itemQuantityController.text);
    final unitPrice = double.tryParse(_itemPriceController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter a valid quantity')),
      );
      return;
    }
    if (unitPrice == null || unitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter a valid unit price')),
      );
      return;
    }
    setState(() {
      _cartItems.add(_RequestItem(
        name: _itemNameController.text.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: quantity * unitPrice,
      ));
      _itemNameController.clear();
      _itemQuantityController.clear();
      _itemPriceController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Item added to cart')),
    );
  }

  void _removeItem(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  Future<void> _submitRequest() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please select a location first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please add at least one item to cart')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final itemsData = _cartItems.map((item) => {
            'name': item.name,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'total_price': item.totalPrice,
          }).toList();

      final problem = _descriptionController.text.trim();
      final requestData = <String, dynamic>{
        'title': problem.length > 60 ? '${problem.substring(0, 60)}…' : problem,
        'description': problem,
        'items': itemsData,
        'total_amount': _totalAmount,
        'currency': 'TZS',
        'location_id': _selectedLocation,
        'location_name': _selectedLocation,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (widget.expenseId != null) {
        await _firestore.collection('expenses').doc(widget.expenseId).update(requestData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Request updated successfully')),
          );
        }
      } else {
        final now = DateTime.now();
        final expenseId = 'REQ-${now.millisecondsSinceEpoch}';
        requestData.addAll({
          'expense_id': expenseId,
          'submitted_by': user.email,
          'submitted_by_name': user.displayName ?? user.email,
          'submitted_at': FieldValue.serverTimestamp(),
          'status': 'pending',
          'approved_by': null,
          'approved_by_name': null,
          'approved_at': null,
          'rejection_reason': null,
          'created_at': FieldValue.serverTimestamp(),
        });
        await _firestore.collection('expenses').doc(expenseId).set(requestData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Request submitted for approval')),
          );
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _itemNameController.dispose();
    _itemQuantityController.dispose();
    _itemPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationSelected = _selectedLocation != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.expenseId != null ? 'Edit Request' : 'New Request',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 1. Location (required, first) ──────────────────────────────
            _buildSectionHeader(Icons.location_on, 'Select Location *'),
            const SizedBox(height: 12),
            _loadingLocations
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    value: _selectedLocation,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.location_on),
                      border: const OutlineInputBorder(),
                      hintText: 'Select location',
                      filled: !locationSelected,
                      fillColor: locationSelected ? null : Colors.orange.shade50,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: locationSelected
                              ? Colors.grey
                              : Colors.orange,
                          width: locationSelected ? 1 : 2,
                        ),
                      ),
                    ),
                    items: _locations
                        .map((loc) => DropdownMenuItem(value: loc, child: Text(loc)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLocation = v),
                    validator: (v) => v == null ? 'Please select a location' : null,
                  ),

            const SizedBox(height: 24),

            // ── 2. What is the problem? ──────────────────────────────────
            _buildSectionHeader(Icons.help_outline_rounded, 'Problem Description'),
            const SizedBox(height: 12),
            AbsorbPointer(
              absorbing: !locationSelected,
              child: Opacity(
                opacity: locationSelected ? 1.0 : 0.4,
                child: TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'What is the problem? *',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                    hintText: 'Describe the issue clearly',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please describe the problem';
                    return null;
                  },
                ),
              ),
            ),
            if (!locationSelected)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Select location first to enable this field',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ── 3. Add Items to Cart ────────────────────────────────────
            _buildSectionHeader(Icons.add_shopping_cart, 'Add Items to Cart'),
            const SizedBox(height: 12),
            AbsorbPointer(
              absorbing: !locationSelected,
              child: Opacity(
                opacity: locationSelected ? 1.0 : 0.4,
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _itemNameController,
                          decoration: const InputDecoration(
                            labelText: 'Item Name',
                            prefixIcon: Icon(Icons.shopping_bag),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _itemQuantityController,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity',
                                  prefixIcon: Icon(Icons.numbers),
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _itemPriceController,
                                decoration: const InputDecoration(
                                  labelText: 'Unit Price (TZS)',
                                  prefixIcon: Icon(Icons.attach_money),
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _addItemToCart,
                            icon: const Icon(Icons.add),
                            label: const Text('Add to Cart'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!locationSelected)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: Colors.orange[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Select location first to add items',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ── Cart Items ─────────────────────────────────────────────
            _buildSectionHeader(
              Icons.shopping_cart,
              'Cart Items (${_cartItems.length})',
            ),
            const SizedBox(height: 12),
            if (_cartItems.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Cart is empty',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add items using the form above',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ..._cartItems.asMap().entries.map((entry) =>
                  _buildCartItem(entry.value, entry.key)),
              const SizedBox(height: 16),
              Card(
                color: AppTheme.primaryColor.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Amount:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'TZS ${_formatCurrency(_totalAmount)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── Submit ─────────────────────────────────────────────────
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        widget.expenseId != null
                            ? 'Update Request'
                            : 'Submit Request',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCartItem(_RequestItem item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.inventory_2, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Qty: ${item.quantity} × ${_formatCurrency(item.unitPrice)} = ${_formatCurrency(item.totalPrice)}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.red[700]),
              onPressed: () => _removeItem(index),
              tooltip: 'Remove item',
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }
}

class _RequestItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  _RequestItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}
