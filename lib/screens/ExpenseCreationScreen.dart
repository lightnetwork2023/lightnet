import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/app_logger.dart';

class ExpenseCreationScreen extends StatefulWidget {
  final String? expenseId;
  final Map<String, dynamic>? existingExpense;

  const ExpenseCreationScreen({
    Key? key,
    this.expenseId,
    this.existingExpense,
  }) : super(key: key);

  @override
  _ExpenseCreationScreenState createState() => _ExpenseCreationScreenState();
}

class _ExpenseCreationScreenState extends State<ExpenseCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  // Form controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Item form controllers
  final _itemNameController = TextEditingController();
  final _itemQuantityController = TextEditingController();
  final _itemPriceController = TextEditingController();
  
  // State
  String? _selectedLocation;
  List<ExpenseItem> _cartItems = [];
  bool _isSubmitting = false;
  List<String> _locations = [];
  bool _loadingLocations = true;
  
  // Role check
  String? _userRole;
  bool _checkingRole = true;
  bool _hasAccess = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadLocations();
    _populateExistingData();
  }

  void _populateExistingData() {
    if (widget.existingExpense != null) {
      final expense = widget.existingExpense!;
      
      // Populate basic fields
      _titleController.text = expense['title'] ?? '';
      _descriptionController.text = expense['description'] ?? '';
      _notesController.text = expense['notes'] ?? '';
      _selectedLocation = expense['location_id'] ?? expense['location_name'];
      
      // Populate cart items
      final items = expense['items'] as List<dynamic>? ?? [];
      _cartItems = items.map((item) {
        final itemData = item as Map<String, dynamic>;
        return ExpenseItem(
          name: itemData['name'] ?? '',
          quantity: (itemData['quantity'] as num?)?.toInt() ?? 1,
          unitPrice: (itemData['unit_price'] as num?)?.toDouble() ?? 0,
          totalPrice: (itemData['total_price'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      
      setState(() {});
    }
  }

  Future<void> _checkUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('DEBUG: No user logged in');
        setState(() {
          _checkingRole = false;
          _hasAccess = false;
        });
        return;
      }
      
      print('DEBUG: Checking role for user: ${user.email} (UID: ${user.uid})');
      
      // Get user role from Firestore users collection (using UID, not email)
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      
      print('DEBUG: User doc exists: ${userDoc.exists}');
      
      if (userDoc.exists) {
        final data = userDoc.data();
        print('DEBUG: User doc data: $data');
        
        final role = data?['role'] as String?;
        print('DEBUG: Extracted role: "$role"');
        
        // Trim whitespace and convert to lowercase for comparison
        final normalizedRole = role?.trim().toLowerCase();
        print('DEBUG: Normalized role: "$normalizedRole"');
        
        final hasAccess = normalizedRole == 'technician' || normalizedRole == 'boss';
        print('DEBUG: Has access: $hasAccess');
        
        setState(() {
          _userRole = role;
          // Only technician and boss can create expenses
          _hasAccess = hasAccess;
          _checkingRole = false;
        });
      } else {
        print('DEBUG: User document not found in Firestore');
        setState(() {
          _checkingRole = false;
          _hasAccess = false;
        });
      }
    } catch (e) {
      print('ERROR checking user role: $e');
      setState(() {
        _checkingRole = false;
        _hasAccess = false;
      });
    }
  }

  Future<void> _loadLocations() async {
    try {
      final snapshot = await _firestore.collection('locations').get();
      
      // Filter for main locations only (type == 'main' or no parentLocation)
      final mainLocations = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        
        // Include if type is 'main' OR if it has no parentLocation field
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading locations: $e')),
      );
    }
  }

  double get _totalAmount {
    return _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  void _addItemToCart() {
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
        const SnackBar(content: Text('⚠️ Please enter valid quantity')),
      );
      return;
    }
    
    if (unitPrice == null || unitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter valid unit price')),
      );
      return;
    }
    
    setState(() {
      _cartItems.add(ExpenseItem(
        name: _itemNameController.text.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: quantity * unitPrice,
      ));
      
      // Clear item form
      _itemNameController.clear();
      _itemQuantityController.clear();
      _itemPriceController.clear();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Item added to cart')),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _cartItems.removeAt(index);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item removed from cart')),
    );
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please add at least one item to cart')),
      );
      return;
    }
    
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please select a location')),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      
      // Prepare items data
      final itemsData = _cartItems.map((item) => {
        'name': item.name,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total_price': item.totalPrice,
      }).toList();
      
      final expenseData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'items': itemsData,
        'total_amount': _totalAmount,
        'currency': 'TZS',
        'location_id': _selectedLocation,
        'location_name': _selectedLocation,
        'notes': _notesController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };
      
      if (widget.expenseId != null) {
        await _firestore.collection('expenses').doc(widget.expenseId).update(expenseData);
        AppLogger.logExpenseSubmitted(
          expenseId: widget.expenseId!,
          amount: _totalAmount,
          title: _titleController.text.trim(),
          location: _selectedLocation,
          isUpdate: true,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Expense updated successfully')),
        );
      } else {
        final now = DateTime.now();
        final timestamp = now.millisecondsSinceEpoch;
        final expenseId = 'EXP-$timestamp';
        
        expenseData.addAll({
          'expense_id': expenseId,
          'submitted_by': user.email,
          'submitted_by_name': user.displayName ?? user.email,
          'submitted_at': Timestamp.fromDate(now),
          'status': 'pending',
          'approved_by': null,
          'approved_by_name': null,
          'approved_at': null,
          'rejection_reason': null,
          'created_at': Timestamp.fromDate(now),
        });
        
        print('DEBUG: Creating expense $expenseId for user: ${user.email}');
        await _firestore.collection('expenses').doc(expenseId).set(expenseData);
        print('DEBUG: Expense created successfully');
        AppLogger.logExpenseSubmitted(
          expenseId: expenseId,
          amount: _totalAmount,
          title: _titleController.text.trim(),
          location: _selectedLocation,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Expense submitted for approval')),
        );
      }
      
      Navigator.pop(context);
    } catch (e) {
      AppLogger.logError('expense_submitted', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _itemNameController.dispose();
    _itemQuantityController.dispose();
    _itemPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.expenseId != null ? 'Edit Expense' : 'Create Expense',
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
      body: _checkingRole
          ? const Center(child: CircularProgressIndicator())
          : !_hasAccess
              ? _buildAccessDenied()
              : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Info Section
            _buildSectionHeader(Icons.info, 'Basic Information'),
            const SizedBox(height: 12),
            
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Expense Title *',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
                hintText: 'e.g., Network Equipment Purchase',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Title is required';
                }
                if (value.trim().length < 3) {
                  return 'Title must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description *',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
                hintText: 'Describe the purpose of this expense',
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Description is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            
            // Location Selection
            if (_loadingLocations)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<String>(
                value: _selectedLocation,
                decoration: const InputDecoration(
                  labelText: 'Location *',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select location for this expense'),
                items: _locations
                    .map((loc) => DropdownMenuItem(
                          value: loc,
                          child: Text(loc),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedLocation = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a location';
                  }
                  return null;
                },
              ),
            
            const SizedBox(height: 24),
            
            // Add Items Section
            _buildSectionHeader(Icons.add_shopping_cart, 'Add Items to Cart'),
            const SizedBox(height: 12),
            
            Card(
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
            
            const SizedBox(height: 24),
            
            // Cart Items Section
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
                      Icon(Icons.shopping_cart_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Cart is empty',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add items using the form above',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._cartItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return _buildCartItem(item, index);
              }).toList(),
            
            // Total Section
            if (_cartItems.isNotEmpty) ...[
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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
            
            const SizedBox(height: 24),
            
            // Notes Section (Optional)
            _buildSectionHeader(Icons.note, 'Additional Notes (Optional)'),
            const SizedBox(height: 12),
            
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.note_add),
                border: OutlineInputBorder(),
                hintText: 'Any additional information',
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 32),
            
            // Submit Button
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitExpense,
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
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.expenseId != null ? 'Update Expense' : 'Submit for Approval',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block,
              size: 80,
              color: Colors.red[300],
            ),
            const SizedBox(height: 24),
            Text(
              'Access Denied',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Only Technicians and Boss can create expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            if (_userRole != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Your role: ${_userRole}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
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

  Widget _buildCartItem(ExpenseItem item, int index) {
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
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Qty: ${item.quantity} × ${_formatCurrency(item.unitPrice)} = ${_formatCurrency(item.totalPrice)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
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

class ExpenseItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  ExpenseItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}
