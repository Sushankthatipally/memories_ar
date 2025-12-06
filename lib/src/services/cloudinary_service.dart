import 'dart:typed_data';
import 'package:cloudinary_public/cloudinary_public.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  late final CloudinaryPublic _cloudinary;
  bool _initialized = false;

  // Cloudinary credentials
  static const String _cloudName = 'dh18h3kgv';
  static const String _uploadPreset = 'ar_album'; // We'll create this

  Future<void> initialize() async {
    if (_initialized) return;

    _cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
    _initialized = true;
    print('Cloudinary initialized: $_cloudName');
  }

  /// Upload photo to Cloudinary
  /// Returns the public URL of the uploaded file
  Future<String> uploadPhoto({
    required Uint8List bytes,
    required String fileName,
    String? folder,
  }) async {
    if (!_initialized) await initialize();

    try {
      print('Uploading photo to Cloudinary: $fileName');

      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          bytes,
          identifier: fileName,
          folder: folder ?? 'ar_photos',
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      print('Photo uploaded successfully: ${response.secureUrl}');
      return response.secureUrl;
    } catch (e) {
      print('Cloudinary photo upload error: $e');
      throw Exception('Failed to upload photo: $e');
    }
  }

  /// Upload video to Cloudinary
  /// Returns the public URL of the uploaded file
  Future<String> uploadVideo({
    required Uint8List bytes,
    required String fileName,
    String? folder,
  }) async {
    if (!_initialized) await initialize();

    try {
      print('Uploading video to Cloudinary: $fileName');

      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          bytes,
          identifier: fileName,
          folder: folder ?? 'ar_videos',
          resourceType: CloudinaryResourceType.Video,
        ),
      );

      print('Video uploaded successfully: ${response.secureUrl}');
      return response.secureUrl;
    } catch (e) {
      print('Cloudinary video upload error: $e');
      throw Exception('Failed to upload video: $e');
    }
  }

  /// Extract public_id from Cloudinary URL
  /// Example: https://res.cloudinary.com/dh18h3kgv/image/upload/v1234/folder/file.jpg
  /// Returns: folder/file
  String? extractPublicId(String cloudinaryUrl) {
    try {
      final uri = Uri.parse(cloudinaryUrl);
      final pathSegments = uri.pathSegments;

      // Find 'upload' segment and get everything after version number
      final uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex + 2 >= pathSegments.length) {
        return null;
      }

      // Skip 'upload' and version (vXXXX), get the rest
      final publicIdSegments = pathSegments.sublist(uploadIndex + 2);
      var publicId = publicIdSegments.join('/');

      // Remove file extension
      if (publicId.contains('.')) {
        publicId = publicId.substring(0, publicId.lastIndexOf('.'));
      }

      return publicId;
    } catch (e) {
      print('Error extracting public_id from URL: $e');
      return null;
    }
  }

  /// Delete file from Cloudinary
  /// Note: This logs the public_id but doesn't actually delete
  /// Cloudinary deletion requires API secret (should use Cloud Function)
  Future<bool> deleteFile(String cloudinaryUrl) async {
    if (!_initialized) await initialize();

    try {
      final publicId = extractPublicId(cloudinaryUrl);

      if (publicId != null) {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('⚠️  CLOUDINARY FILE NOT DELETED');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('URL: $cloudinaryUrl');
        print('Public ID: $publicId');
        print('');
        print('To delete manually:');
        print('1. Go to: https://console.cloudinary.com/console');
        print('2. Navigate to Media Library');
        print('3. Search for: $publicId');
        print('4. Delete the file');
        print('');
        print('Or implement a Cloud Function for automatic deletion.');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      } else {
        print('❌ Could not extract public_id from: $cloudinaryUrl');
      }

      return false;
    } catch (e) {
      print('Delete error: $e');
      return false;
    }
  }
}
