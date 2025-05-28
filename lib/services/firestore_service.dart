import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip_model.dart';

Future<List<Trip>> fetchTripsByLocation(String uid, String country, String city) async {
  final query = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('trips')
      .where('country', isEqualTo: country)
      .where('city', isEqualTo: city)
      .get();

  return query.docs.map((doc) => Trip.fromFirestore(doc)).toList();
}
