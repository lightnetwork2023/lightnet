import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationController extends GetxController {
  final RxList<String> locations = <String>[].obs;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void onInit() {
    super.onInit();
    loadLocations();
  }

  Future<void> loadLocations() async {
    print('LocationController: Loading locations from Firestore...');
    final snapshot = await _firestore.collection('locations').get();
    print('LocationController: Got ${snapshot.docs.length} locations from Firestore');
    print('LocationController: Location IDs: ${snapshot.docs.map((doc) => doc.id).toList()}');
    locations.assignAll(snapshot.docs.map((doc) => doc.id).toList());
    print('LocationController: Updated locations list: ${locations}');
  }

  Future<void> addLocation(String newLocation) async {
    final docRef = _firestore.collection('locations').doc(newLocation);
    final exists = (await docRef.get()).exists;

    if (!exists) {
      await docRef.set({});
      loadLocations();
    } else {
      throw Exception("Location already exists");
    }
  }
}
