import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:lightnetwork/screens/HomeScreen.dart';
import 'package:lightnetwork/screens/LoginScreen.dart';
import 'package:lightnetwork/screens/AgentHomeScreen.dart';
import 'controllers/location_controller.dart';
import 'controllers/auth_controller.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';

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
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
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
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading your profile...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
