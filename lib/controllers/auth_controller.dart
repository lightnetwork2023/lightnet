import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Rx<User?> _user = Rx<User?>(null);
  final RxString _userRole = 'employee'.obs;

  User? get user => _user.value;
  String get userRole => _userRole.value;
  bool get isBoss => _userRole.value == 'boss';

  @override
  void onInit() {
    super.onInit();
    _user.bindStream(_auth.authStateChanges());
    _user.listen((User? user) async {
      if (user != null) {
        // Load user role from Firestore when user state changes
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          _userRole.value = userData['role'] ?? 'employee';
        }
      } else {
        _userRole.value = 'employee';
      }
    });
  }

  void setUserRole(String role) {
    _userRole.value = role;
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

  Future<UserCredential?> createNewAccount(String email, String password, String role) async {
    if (!isBoss) {
      throw 'Only boss can create new accounts.';
    }
    
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document in Firestore with specified role
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        throw 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        throw 'An account already exists for that email.';
      }
      throw e.message ?? 'An error occurred during account creation.';
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      _userRole.value = 'employee';
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