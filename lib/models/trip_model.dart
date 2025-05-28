import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final String id;
  final String country;
  final String city;
  final String place;
  final int color;

  Trip({
    required this.id,
    required this.country,
    required this.city,
    required this.place,
    required this.color,
  });

  factory Trip.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Trip(
      id: doc.id,
      country: data['country'] ?? '',
      city: data['city'] ?? '',
      place: data['place'] ?? '',
      color: data['color'] ?? 0xFFCCCCCC,
    );
  }
}
