import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all photos for testing (no client filter)
  Stream<List<PhotoData>> getAllPhotos() {
    print('\n📡 FIRESTORE: Querying all photos (collectionGroup)...');

    return _firestore.collectionGroup('photos').snapshots().map((snapshot) {
      print('   ✅ Query returned ${snapshot.docs.length} documents');

      final photos = snapshot.docs.map((doc) {
        final data = doc.data();
        print('\n   📄 Document: ${doc.id}');
        print('      ├─ imageHash: ${data['imageHash'] ?? 'MISSING'}');
        print(
            '      ├─ imageURL: ${data['imageURL']?.substring(0, 30) ?? 'MISSING'}...');
        print(
            '      ├─ videoURL: ${data['videoURL']?.substring(0, 30) ?? 'MISSING'}...');
        print('      ├─ albumId: ${data['albumId'] ?? 'MISSING'}');
        print('      └─ clientEmail: ${data['clientEmail'] ?? 'MISSING'}');

        return PhotoData(
          id: doc.id,
          imageHash: data['imageHash'] ?? '',
          imageURL: data['imageURL'] ?? '',
          videoURL: data['videoURL'] ?? '',
          albumId: data['albumId'] ?? '',
          clientEmail: data['clientEmail'] ?? '',
        );
      }).toList();

      print('\n   📦 Returning ${photos.length} PhotoData objects');
      return photos;
    });
  }

  /// Get all photos with their hashes for matching
  Stream<List<PhotoData>> getPhotosForClient(String clientEmail) {
    return _firestore
        .collectionGroup('photos')
        .where('clientEmail', isEqualTo: clientEmail)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return PhotoData(
          id: doc.id,
          imageHash: data['imageHash'] ?? '',
          simpleHash: data['simpleHash'],
          imageURL: data['imageURL'] ?? '',
          videoURL: data['videoURL'] ?? '',
          albumId: data['albumId'] ?? '',
          clientEmail: data['clientEmail'] ?? '',
        );
      }).toList();
    });
  }

  /// Get specific photo by ID
  Future<PhotoData?> getPhoto(String albumId, String photoId) async {
    try {
      final doc = await _firestore
          .collection('albums')
          .doc(albumId)
          .collection('photos')
          .doc(photoId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      return PhotoData(
        id: doc.id,
        imageHash: data['imageHash'] ?? '',
        simpleHash: data['simpleHash'],
        imageURL: data['imageURL'] ?? '',
        videoURL: data['videoURL'] ?? '',
        albumId: data['albumId'] ?? '',
        clientEmail: data['clientEmail'] ?? '',
      );
    } catch (e) {
      throw Exception('Failed to get photo: $e');
    }
  }
}

class PhotoData {
  final String id;
  final String imageHash;
  final String? simpleHash; // Optional simple hash for hybrid matching
  final String imageURL; // Google Drive file ID
  final String videoURL; // Google Drive file ID
  final String albumId;
  final String clientEmail;

  PhotoData({
    required this.id,
    required this.imageHash,
    this.simpleHash,
    required this.imageURL,
    required this.videoURL,
    required this.albumId,
    required this.clientEmail,
  });
}
