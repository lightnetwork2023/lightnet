import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Rx<User?> _user = Rx<User?>(null);
  final RxString _userRole = ''.obs;
  final RxString _userName = ''.obs;
  final RxString _userLocation = ''.obs;
  final RxMap<String, dynamic> _allowedBundles = <String, dynamic>{}.obs;
  final RxList<String> _userLocations = <String>[].obs;

  User? get user => _user.value;
  String get userRole => _userRole.value;
  String get userName => _userName.value;
  String get userLocation => _userLocation.value;
  List<String> get userLocations => _userLocations.toList();
  RxString get userLocationStream => _userLocation;
  RxList<String> get userLocationsStream => _userLocations;
  RxMap<String, dynamic> get allowedBundlesStream => _allowedBundles;
  Map<String, dynamic> get allowedBundles => _allowedBundles;
  bool get isBoss => _userRole.value == 'boss';
  bool get isAgent => _userRole.value == 'agent';
  bool get isSuperAgent => _userRole.value == 'superagent';

  @override
  void onInit() {
    super.onInit();
    _loadUserRoleFromPrefs();
    _user.bindStream(_auth.authStateChanges());
    _user.listen((User? user) async {
      if (user != null) {
        await _loadUserData(user);
      } else {
        await _clearUserData();
      }
    });
  }

  Future<void> _loadUserData(User user) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      final userData = userDoc.data() as Map<String, dynamic>;
      _userRole.value = userData['role'] ?? 'technician';
      _userName.value = userData['name'] ?? '';
      _userLocation.value = userData['location'] ?? '';
      
      // Handle locations for superagents
      if (userData['locations'] != null && userData['locations'] is List) {
        _userLocations.assignAll(List<String>.from(userData['locations']));
        // Set current location to first location if available
        if (_userLocations.isNotEmpty) {
          _userLocation.value = _userLocations.first;
        }
      } else if (userData['location'] != null && userData['location'].isNotEmpty) {
        _userLocations.assignAll([userData['location']]);
      } else {
        _userLocations.clear();
      }
      
      if (userData['allowed_bundles'] != null) {
        try {
          // Handle both List and Map types for allowed_bundles
          final bundlesRaw = userData['allowed_bundles'];
          if (bundlesRaw is Map) {
            final bundlesData = Map<String, dynamic>.from(bundlesRaw);
            _allowedBundles.value = bundlesData;
          } else if (bundlesRaw is List) {
            // Convert List to Map if needed, or handle as appropriate for your app
            _allowedBundles.clear();
            print('Warning: allowed_bundles is a List, expected Map. Data: $bundlesRaw');
          } else {
            _allowedBundles.clear();
            print('Warning: allowed_bundles has unexpected type: ${bundlesRaw.runtimeType}');
          }
        } catch (e) {
          print('Error processing allowed_bundles: $e');
          _allowedBundles.clear();
        }
        // Moved to try-catch block above
      } else {
        _allowedBundles.clear();
      }
      await _saveUserRoleToPrefs(_userRole.value);
    }
  }

  Future<void> _clearUserData() async {
    _userRole.value = '';
    _userName.value = '';
    _userLocation.value = '';
    _allowedBundles.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
  }

  Future<void> _loadUserRoleFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole.value = prefs.getString('user_role') ?? '';
  }

  Future<void> _saveUserRoleToPrefs(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  void setUserRole(String role) {
    _userRole.value = role;
    _saveUserRoleToPrefs(role);
  }

  void setCurrentLocation(String location) {
    if (_userLocations.contains(location)) {
      _userLocation.value = location;
    }
  }

  Future<UserCredential?> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        throw 'Wrong password provided for that user.';
      }
      throw e.message ?? 'An error occurred during login.';
    }
  }

  Future<UserCredential?> createNewAccount(String email, String password, String role, {String? name, String? location, List<String>? locations}) async {
    print('AuthController: Starting user creation for email: $email, role: $role');
    
    if (!isBoss) {
      print('AuthController: Error - Only boss can create new accounts');
      throw 'Only boss can create new accounts.';
    }

    try {
      print('AuthController: Calling Cloud Function to create user...');
      // Call the Cloud Function to create user
      final response = await http.post(
        Uri.parse('https://us-central1-lightnet-d2de9.cloudfunctions.net/createUser'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
          'role': role,
          'name': name,
          'location': location,
          'locations': locations,
        }),
      );

      print('AuthController: Cloud Function response status: ${response.statusCode}');
      print('AuthController: Cloud Function response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('AuthController: User created successfully via Cloud Function');
        // User created successfully via Cloud Function
        // Return null to indicate success without UserCredential
        return null;
      } else {
        // Handle Cloud Function errors
        final errorMessage = responseData['error'] ?? 'Failed to create user';
        print('AuthController: Cloud Function error: $errorMessage');
        throw errorMessage;
      }
    } on FirebaseAuthException catch (e) {
      print('AuthController: FirebaseAuthException: ${e.code} - ${e.message}');
      if (e.code == 'weak-password') {
        throw 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        throw 'An account already exists for that email.';
      }
      throw e.message ?? 'An error occurred during account creation.';
    } catch (e) {
      print('AuthController: General error during account creation: $e');
      throw 'An error occurred during account creation: $e';
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      await _clearUserData();
    } catch (e) {
      throw 'An error occurred during logout.';
    }
  }

  Future<void> updateUserRole(String userId, String newRole) async {
    if (!isBoss) {
      throw 'Only boss can update user roles.';
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'role': newRole});
    } catch (e) {
      throw 'Failed to update user role.';
    }
  }
} 