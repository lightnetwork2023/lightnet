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
  final RxString _homeCustomerId = ''.obs;
  final RxDouble _commissionSuperAgent = 0.63.obs; // default 63%
  final RxDouble _commissionCompany = 0.37.obs;    // default 37%
  final RxBool _isDataLoaded = false.obs; // Track if user data has been loaded

  User? get user => _user.value;
  String get userRole => _userRole.value;
  String get userName => _userName.value;
  String get userLocation => _userLocation.value;
  List<String> get userLocations => _userLocations.toList();
  RxString get userLocationStream => _userLocation;
  String get homeCustomerId => _homeCustomerId.value;
  RxList<String> get userLocationsStream => _userLocations;
  RxMap<String, dynamic> get allowedBundlesStream => _allowedBundles;
  Map<String, dynamic> get allowedBundles => _allowedBundles;
  double get commissionSuperAgent => _commissionSuperAgent.value;
  double get commissionCompany => _commissionCompany.value;
  bool get isBoss => _userRole.value == 'boss';
  bool get isAgent => _userRole.value == 'agent';
  bool get isSuperAgent => _userRole.value == 'superagent';
  bool get isHomeUser => _userRole.value == 'homeuser';
  bool get isDataLoaded => _isDataLoaded.value; // Expose data loaded state

  @override
  void onInit() {
    super.onInit();
    // Don't use bindStream, manually listen to avoid Firebase Auth internal errors
    _auth.authStateChanges().listen((User? user) async {
      try {
        _user.value = user;
        if (user != null) {
          await _loadUserData(user);
        } else {
          await _clearUserData();
        }
      } catch (e) {
        print('Error in auth state listener: $e');
        // If error occurs, still try to load from cache/prefs
        if (user != null) {
          _user.value = user;
          try {
            final loaded = await _loadUserFromPrefs();
            if (loaded) {
              _isDataLoaded.value = true;
            }
          } catch (_) {}
        }
      }
    }, onError: (error) {
      print('Firebase Auth stream error: $error');
      // Silently catch Firebase Auth internal errors
    });
  }

  Future<void> _loadUserData(User user) async {
    try {
      DocumentSnapshot<Map<String, dynamic>>? cacheDoc;
      try {
        cacheDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {}

      if (cacheDoc != null && cacheDoc.exists) {
        final userData = cacheDoc.data() as Map<String, dynamic>;
        _userRole.value = userData['role'] ?? 'technician';
        print('DEBUG AUTH: Loaded from CACHE - role: ${_userRole.value}, uid: ${user.uid}');
        _userName.value = userData['name'] ?? '';
        _userLocation.value = userData['location'] ?? '';
        _homeCustomerId.value = userData['home_customer_id'] ?? '';
        if (userData['locations'] != null && userData['locations'] is List) {
          _userLocations.assignAll(List<String>.from(userData['locations']));
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
            final bundlesRaw = userData['allowed_bundles'];
            if (bundlesRaw is Map) {
              _allowedBundles.value = Map<String, dynamic>.from(bundlesRaw);
            } else if (bundlesRaw is List) {
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
        } else {
          _allowedBundles.clear();
        }
        try {
          double saShare = 0.63;
          double coShare = 0.37;
          dynamic comm = userData['commission'];
          if (comm != null) {
            if (comm is Map) {
              final m = Map<String, dynamic>.from(comm);
              saShare = _parseShare(m['superagent']) ?? saShare;
              final parsedCompany = _parseShare(m['company']);
              coShare = parsedCompany ?? (1.0 - saShare);
            } else {
              final legacy = _parseShare(comm);
              if (legacy != null) {
                saShare = legacy;
                coShare = 1.0 - saShare;
              }
            }
          } else if (userData['superagent_percent'] != null) {
            final legacy = _parseShare(userData['superagent_percent']);
            if (legacy != null) {
              saShare = legacy;
              coShare = 1.0 - saShare;
            }
          }
          saShare = saShare.clamp(0.0, 1.0);
          coShare = (1.0 - saShare).clamp(0.0, 1.0);
          _commissionSuperAgent.value = saShare;
          _commissionCompany.value = coShare;
        } catch (e) {
          _commissionSuperAgent.value = 0.63;
          _commissionCompany.value = 0.37;
          print('Warning: failed to parse commission shares: $e');
        }
        await _saveUserToPrefs();
        _isDataLoaded.value = true;
      }

      try {
        final serverDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (serverDoc.exists) {
          final userData = serverDoc.data() as Map<String, dynamic>;
          _userRole.value = userData['role'] ?? 'technician';
          print('DEBUG AUTH: Loaded from SERVER - role: ${_userRole.value}, uid: ${user.uid}');
          _userName.value = userData['name'] ?? '';
          _userLocation.value = userData['location'] ?? '';
          _homeCustomerId.value = userData['home_customer_id'] ?? '';
          if (userData['locations'] != null && userData['locations'] is List) {
            _userLocations.assignAll(List<String>.from(userData['locations']));
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
              final bundlesRaw = userData['allowed_bundles'];
              if (bundlesRaw is Map) {
                _allowedBundles.value = Map<String, dynamic>.from(bundlesRaw);
              } else if (bundlesRaw is List) {
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
          } else {
            _allowedBundles.clear();
          }
          try {
            double saShare = 0.63;
            double coShare = 0.37;
            dynamic comm = userData['commission'];
            if (comm != null) {
              if (comm is Map) {
                final m = Map<String, dynamic>.from(comm);
                saShare = _parseShare(m['superagent']) ?? saShare;
                final parsedCompany = _parseShare(m['company']);
                coShare = parsedCompany ?? (1.0 - saShare);
              } else {
                final legacy = _parseShare(comm);
                if (legacy != null) {
                  saShare = legacy;
                  coShare = 1.0 - saShare;
                }
              }
            } else if (userData['superagent_percent'] != null) {
              final legacy = _parseShare(userData['superagent_percent']);
              if (legacy != null) {
                saShare = legacy;
                coShare = 1.0 - saShare;
              }
            }
            saShare = saShare.clamp(0.0, 1.0);
            coShare = (1.0 - saShare).clamp(0.0, 1.0);
            _commissionSuperAgent.value = saShare;
            _commissionCompany.value = coShare;
          } catch (e) {
            _commissionSuperAgent.value = 0.63;
            _commissionCompany.value = 0.37;
            print('Warning: failed to parse commission shares: $e');
          }
          await _saveUserToPrefs();
          _isDataLoaded.value = true;
          print('DEBUG AUTH: Data loaded COMPLETE - Final role: ${_userRole.value}');
        } else {
          if (!_isDataLoaded.value) {
            final loaded = await _loadUserFromPrefs();
            if (!loaded) _isDataLoaded.value = false;
          }
        }
      } catch (e) {
        if (!_isDataLoaded.value) {
          final loaded = await _loadUserFromPrefs();
          if (!loaded) _isDataLoaded.value = false;
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      if (!_isDataLoaded.value) {
        final loaded = await _loadUserFromPrefs();
        if (!loaded) _isDataLoaded.value = false;
      }
    }
  }

  // Helper to parse share from number or string; accepts 0-1 fractions or 0-100 percents
  double? _parseShare(dynamic v) {
    if (v == null) return null;
    double? d;
    if (v is num) {
      d = v.toDouble();
    } else if (v is String) {
      d = double.tryParse(v);
    }
    if (d == null) return null;
    if (d > 1.0) return (d / 100.0);
    if (d < 0) return 0.0;
    return d;
  }

  Future<void> _clearUserData() async {
    _userRole.value = '';
    _userName.value = '';
    _userLocation.value = '';
    _homeCustomerId.value = '';
    _allowedBundles.clear();
    _commissionSuperAgent.value = 0.63;
    _commissionCompany.value = 0.37;
    _isDataLoaded.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await prefs.remove('user_name');
    await prefs.remove('user_location');
    await prefs.remove('home_customer_id');
    await prefs.remove('user_locations_json');
  }

  Future<void> _loadUserRoleFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole.value = prefs.getString('user_role') ?? '';
  }

  Future<void> _saveUserRoleToPrefs(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  Future<void> _saveUserToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', _userRole.value);
    await prefs.setString('user_name', _userName.value);
    await prefs.setString('user_location', _userLocation.value);
    await prefs.setString('home_customer_id', _homeCustomerId.value);
    await prefs.setString('user_locations_json', jsonEncode(_userLocations.toList()));
  }

  Future<bool> _loadUserFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';
    if (role.isEmpty) return false;
    _userRole.value = role;
    _userName.value = prefs.getString('user_name') ?? '';
    _userLocation.value = prefs.getString('user_location') ?? '';
    _homeCustomerId.value = prefs.getString('home_customer_id') ?? '';
    final locsJson = prefs.getString('user_locations_json');
    if (locsJson != null) {
      try {
        final list = List<String>.from(jsonDecode(locsJson));
        _userLocations.assignAll(list);
      } catch (_) {
        if (_userLocation.value.isNotEmpty) {
          _userLocations.assignAll([_userLocation.value]);
        } else {
          _userLocations.clear();
        }
      }
    } else if (_userLocation.value.isNotEmpty) {
      _userLocations.assignAll([_userLocation.value]);
    } else {
      _userLocations.clear();
    }
    _isDataLoaded.value = true;
    return true;
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
      // Reset data loaded flag before login
      _isDataLoaded.value = false;
      
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

  Future<UserCredential?> createNewAccount(String email, String password, String role, {String? name, String? location, List<String>? locations, String? homeCustomerId}) async {
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
          'home_customer_id': homeCustomerId,
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

  Future<void> deleteAppUser({String? uid, String? email}) async {
    if (!isBoss) {
      throw 'Only boss can delete users.';
    }
    if ((uid == null || uid.isEmpty) && (email == null || email.isEmpty)) {
      throw 'Provide uid or email to delete user.';
    }
    try {
      final resp = await http.post(
        Uri.parse('https://us-central1-lightnet-d2de9.cloudfunctions.net/deleteAppUser'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (uid != null && uid.isNotEmpty) 'uid': uid,
          if (email != null && email.isNotEmpty) 'email': email,
        }),
      );
      if (resp.statusCode != 200) {
        final data = jsonDecode(resp.body);
        throw data['error'] ?? 'Delete failed with status ${resp.statusCode}';
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Send password reset email to user
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw 'No user found with this email address.';
      } else if (e.code == 'invalid-email') {
        throw 'Invalid email address.';
      }
      throw e.message ?? 'Failed to send password reset email.';
    } catch (e) {
      throw 'An error occurred while sending password reset email.';
    }
  }
} 