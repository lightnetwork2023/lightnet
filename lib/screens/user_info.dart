// screens/user_info_screen.dart
import 'package:flutter/material.dart';

import '../controllers/ApiService.dart';


class UserInfoScreen extends StatefulWidget {
  @override
  _UserInfoScreenState createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _userInfo = [];
  bool _loading = false;

  void _getUserInfo() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _loading = true;
        _userInfo = [];
      });

      final data = await ApiService.getUserInfo(_usernameController.text);

      setState(() {
        _userInfo = List<Map<String, dynamic>>.from(data['user_info'] ?? []);
        _loading = false;
      });
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
      appBar: AppBar(title: const Text("Get User Info")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: "Username"),
                validator: (value) =>
                value == null || value.isEmpty ? "Enter a username" : null,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getUserInfo,
              child: const Text("Get Info"),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : _userInfo.isEmpty
                ? const Text("No information found.")
                : Expanded(
              child: ListView.builder(
                itemCount: _userInfo.length,
                itemBuilder: (context, index) {
                  final info = _userInfo[index];
                  return ListTile(
                    title: Text(info['attribute']),
                    subtitle: Text(info['value']),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
