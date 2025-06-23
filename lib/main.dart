import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:lightnetwork/screens/HomeScreen.dart';
import 'package:lightnetwork/screens/LoginScreen.dart';
import 'package:lightnetwork/screens/AgentHomeScreen.dart';
import 'controllers/location_controller.dart';
import 'controllers/auth_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize controllers globally
  Get.put(LocationController(), permanent: true);
  Get.put(AuthController(), permanent: true);

  runApp(const FreeRadiusApp());
}

class FreeRadiusApp extends StatelessWidget {
  const FreeRadiusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'lightNET',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    return Obx(() {
      // If user is logged in but role is not yet determined, show loading screen
      if (authController.user != null && authController.userRole.isEmpty) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      
      // If user is logged in and role is determined, show the correct screen
      if (authController.user != null) {
        if (authController.isAgent) {
          return const AgentHomeScreen();
        } else {
          return const HomeScreen(); // For 'boss' or 'technician'
        }
      }
      
      // Otherwise, show login screen
      return const LoginScreen();
    });
  }
}
