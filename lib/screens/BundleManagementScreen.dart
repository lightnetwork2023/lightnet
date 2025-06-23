import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BundleManagementScreen extends StatefulWidget {
  const BundleManagementScreen({super.key});

  @override
  State<BundleManagementScreen> createState() => _BundleManagementScreenState();
}

class _BundleManagementScreenState extends State<BundleManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bundleQuantityController = TextEditingController();

  Future<void> _addBundle() async {
    if (_formKey.currentState!.validate()) {
      final quantity = _bundleQuantityController.text.trim();
      
      // Check if bundle already exists
      final doc = await FirebaseFirestore.instance.collection('bundle_configurations').doc(quantity).get();
      if (doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bundle $quantity already exists!')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('bundle_configurations')
          .doc(quantity)
          .set({
        'quantity': quantity,
        'created_at': FieldValue.serverTimestamp(),
      });
      _bundleQuantityController.clear();
      Navigator.pop(context); // Close the dialog
    }
  }

  void _showAddBundleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Bundle'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _bundleQuantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Voucher Quantity (e.g., 50)',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty || int.tryParse(value) == null) {
                return 'Please enter a valid number';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _addBundle,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Bundles'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddBundleDialog,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bundle_configurations').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final bundles = snapshot.data!.docs;
          if (bundles.isEmpty) {
            return const Center(child: Text('No bundles created yet. Add one!'));
          }

          return ListView.builder(
            itemCount: bundles.length,
            itemBuilder: (context, index) {
              final bundle = bundles[index];
              return ListTile(
                title: Text('Voucher Bundle: ${bundle.id}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('bundle_configurations')
                        .doc(bundle.id)
                        .delete();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
} 