import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'cloudinary_service.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final CloudinaryService _cloudinary = CloudinaryService();
  final uuid = const Uuid();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign in admin
  Future<UserCredential> signInAdmin(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Check if current user is admin
  Future<bool> isAdmin() async {
    if (_auth.currentUser == null) return false;
    final doc = await _db.collection('users').doc(_auth.currentUser!.uid).get();
    return doc.exists && doc.data()?['role'] == 'admin';
  }

  // Create client and album
  // NOTE: In production, use Cloud Function to create user to avoid logging out admin
  Future<Map<String, String>> createClientAndAlbum({
    required String clientEmail,
    required String clientPassword,
    required String clientName,
    required String albumName,
  }) async {
    final clientId = uuid.v4();
    final albumId = uuid.v4();
    final albumCode = _generateAlbumCode();

    // For now, we create the client document without Auth user
    // In production: use Cloud Function to create Auth user
    await _db.collection('users').doc(clientId).set({
      'name': clientName,
      'email': clientEmail,
      'role': 'client',
      'albumID': albumId,
      'createdOn': FieldValue.serverTimestamp(),
    });

    // Create album
    await _db.collection('albums').doc(albumId).set({
      'albumName': albumName,
      'owner': clientId,
      'albumCode': albumCode,
      'createdBy': _auth.currentUser?.uid ?? 'studio',
      'createdOn': FieldValue.serverTimestamp(),
      'photoCount': 0,
    });

    return {
      'clientId': clientId,
      'albumId': albumId,
      'albumCode': albumCode,
    };
  }

  // Generate 6-character album code
  String _generateAlbumCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
        6,
        (index) => chars[(DateTime.now().millisecondsSinceEpoch + index) %
            chars.length]).join();
  }

  // Upload file to Cloudinary
  Future<String> uploadFile({
    required String albumId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _cloudinary.initialize();

    // Determine if it's a photo or video based on content type
    final isVideo = contentType.startsWith('video/');

    if (isVideo) {
      return await _cloudinary.uploadVideo(
        bytes: bytes,
        fileName: fileName,
        folder: albumId,
      );
    } else {
      return await _cloudinary.uploadPhoto(
        bytes: bytes,
        fileName: fileName,
        folder: albumId,
      );
    }
  }

  // Add photo-video mapping
  Future<void> addPhotoMapping({
    required String albumId,
    required String targetId,
    required String imageURL,
    required String videoURL,
    String? clientEmail,
    String? imageHash,
    String? simpleHash,
  }) async {
    final photoDoc = _db
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(targetId);

    await photoDoc.set({
      'targetID': targetId,
      'imageURL': imageURL,
      'videoURL': videoURL,
      'albumId': albumId,
      'clientEmail': clientEmail ?? '',
      'imageHash': imageHash ?? '',
      'simpleHash': simpleHash ?? '',
      'createdOn': FieldValue.serverTimestamp(),
    });

    // Ensure album document exists and increment photo count
    await _db.collection('albums').doc(albumId).set({
      'photoCount': FieldValue.increment(1),
      'updatedOn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Update photo mapping
  Future<void> updatePhotoMapping({
    required String albumId,
    required String targetId,
    String? imageURL,
    String? videoURL,
  }) async {
    final photoDoc = _db
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(targetId);

    Map<String, dynamic> updates = {
      'updatedOn': FieldValue.serverTimestamp(),
    };

    if (imageURL != null) updates['imageURL'] = imageURL;
    if (videoURL != null) updates['videoURL'] = videoURL;

    await photoDoc.update(updates);
  }

  // Delete photo mapping
  Future<void> deletePhotoMapping({
    required String albumId,
    required String targetId,
  }) async {
    // Get photo data to extract Cloudinary URLs
    final photoDoc = await _db
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(targetId)
        .get();

    if (photoDoc.exists) {
      final data = photoDoc.data();
      if (data != null) {
        print('\n🗑️  DELETING PHOTO PAIR: $targetId');

        // Try to delete from Cloudinary (will log instructions)
        if (data['imageURL'] != null) {
          await _cloudinary.deleteFile(data['imageURL']);
        }
        if (data['videoURL'] != null) {
          await _cloudinary.deleteFile(data['videoURL']);
        }
      }
    }

    // Delete from Firestore
    await _db
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(targetId)
        .delete();

    // Decrement photo count
    await _db.collection('albums').doc(albumId).set({
      'photoCount': FieldValue.increment(-1),
      'updatedOn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print('✅ Firestore data deleted for: $targetId');
  }

  // Delete ALL photos in an album
  Future<void> deleteAllPhotos({required String albumId}) async {
    print('\n🗑️  DELETING ALL PHOTOS IN ALBUM: $albumId');

    final photosSnapshot =
        await _db.collection('albums').doc(albumId).collection('photos').get();

    int count = 0;
    for (var doc in photosSnapshot.docs) {
      await doc.reference.delete();
      count++;
      print('   Deleted: ${doc.id}');
    }

    // Reset photo count
    await _db.collection('albums').doc(albumId).set({
      'photoCount': 0,
      'updatedOn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print('✅ Deleted $count photos from album: $albumId\n');
  }

  // Get all albums (admin only)
  Stream<QuerySnapshot> getAlbums() {
    return _db
        .collection('albums')
        .orderBy('createdOn', descending: true)
        .snapshots();
  }

  // Get album by ID
  Future<DocumentSnapshot> getAlbum(String albumId) async {
    return await _db.collection('albums').doc(albumId).get();
  }

  // Get photos for an album
  Stream<QuerySnapshot> getAlbumPhotos(String albumId) {
    return _db
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .orderBy('createdOn', descending: true)
        .snapshots();
  }

  // Get photo by target ID (for client app scanning)
  Future<DocumentSnapshot?> getPhotoByTarget({
    required String albumId,
    required String targetId,
  }) async {
    final doc = await _db
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(targetId)
        .get();
    if (doc.exists) return doc;
    return null;
  }

  // Delete album and all its photos
  Future<void> deleteAlbum(String albumId) async {
    print('\n🗑️  DELETING ALBUM: $albumId');
    print('═══════════════════════════════════════════════════════');

    // Delete all photos in subcollection
    final photosSnapshot =
        await _db.collection('albums').doc(albumId).collection('photos').get();

    print('Found ${photosSnapshot.docs.length} photos to delete');

    for (var doc in photosSnapshot.docs) {
      final data = doc.data();

      // Try to delete from Cloudinary (will log instructions)
      if (data['imageURL'] != null) {
        await _cloudinary.deleteFile(data['imageURL']);
      }
      if (data['videoURL'] != null) {
        await _cloudinary.deleteFile(data['videoURL']);
      }

      await doc.reference.delete();
    }

    // Delete album document
    await _db.collection('albums').doc(albumId).delete();

    print('\n✅ Album deleted from Firestore: $albumId');
    print('⚠️  Check console output above for Cloudinary cleanup instructions');
    print('═══════════════════════════════════════════════════════\n');
  }

  // Get user data
  Future<DocumentSnapshot> getUserData(String userId) async {
    return await _db.collection('users').doc(userId).get();
  }

  // Update album name
  Future<void> updateAlbumName(String albumId, String newName) async {
    await _db.collection('albums').doc(albumId).set({
      'albumName': newName,
      'updatedOn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
