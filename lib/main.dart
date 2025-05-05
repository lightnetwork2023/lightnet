import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:lightnetwork/screens/HomeScreen.dart';
import 'controllers/location_controller.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize LocationController globally
  Get.put(LocationController(), permanent: true);

  runApp(const FreeRadiusApp());
}

class FreeRadiusApp extends StatelessWidget {
  const FreeRadiusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'lightNET',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const HomeScreen(),
    );
  }
}
