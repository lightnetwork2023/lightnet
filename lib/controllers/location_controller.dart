import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:lightnetwork/controllers/ApiService.dart';

class LocationController extends GetxController {
  final RxList<String> locations = <String>[].obs;
  final RxList<Map<String, dynamic>> catalog = <Map<String, dynamic>>[].obs;
  final RxBool loading = false.obs;
  final RxnString error = RxnString();
  StreamSubscription<User?>? _authSub;

  @override
  void onInit() {
    super.onInit();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      ApiService.clearCache();
      if (user != null) {
        loadLocations();
      } else {
        locations.clear();
        catalog.clear();
        error.value = null;
      }
    });
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  static bool isMainLocation(Map<String, dynamic> loc) {
    final type = loc['type']?.toString();
    final parent = loc['parent_location']?.toString();
    return type == 'main' ||
        (type != 'sublocation' && (parent == null || parent.isEmpty));
  }

  List<String> get mainLocationIds => catalog
      .where(isMainLocation)
      .map((loc) => loc['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList();

  String displayName(String id) {
    for (final row in catalog) {
      if ('${row['id']}' == id) {
        final name = '${row['name'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return id;
  }

  Future<void> loadLocations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      error.value = 'Sign in required';
      return;
    }
    loading.value = true;
    error.value = null;
    try {
      final rows = await ApiService.fetchLocationCatalog();
      catalog.assignAll(rows);
      final ids = rows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList()
        ..sort();
      locations.assignAll(ids);
      print('LocationController: loaded ${ids.length} locations from server');
    } catch (e) {
      error.value = e.toString();
      print('LocationController: failed to load locations: $e');
    } finally {
      loading.value = false;
    }
  }

  Future<void> addLocation(
    String newLocation, {
    String? type,
    String? parentLocation,
  }) async {
    await ApiService.createLocation(
      id: newLocation,
      type: type,
      parentLocation: parentLocation,
    );
    await loadLocations();
  }

  Future<void> updateLocation(
    String locationId, {
    String? type,
    String? parentLocation,
    bool clearParent = false,
  }) async {
    await ApiService.updateLocation(
      locationId,
      type: type,
      parentLocation: parentLocation,
      clearParent: clearParent,
    );
    await loadLocations();
  }

  Future<void> deleteLocation(String locationId) async {
    await ApiService.deleteLocation(locationId);
    await loadLocations();
  }
}
