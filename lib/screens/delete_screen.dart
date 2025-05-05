// screens/delete_user_screen.dart
import 'package:flutter/material.dart';

import '../controllers/ApiService.dart';


class DeleteUserScreen extends StatefulWidget {
  @override
  _DeleteUserScreenState createState() => _DeleteUserScreenState();
}

class _DeleteUserScreenState extends State<DeleteUserScreen> {
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _deleteUser() async {
    if (_formKey.currentState!.validate()) {
      final result = await ApiService.deleteUser(_usernameController.text);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Delete User"),
          content: Text(result['message'] ?? 'User deleted'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Delete User")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: "Username"),
                validator: (value) => value == null || value.isEmpty ? "Enter a username" : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _deleteUser,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Delete User"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
