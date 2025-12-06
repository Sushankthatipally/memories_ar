import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Service to download and cache images/videos for native AR
class ResourceCacheService {
  static const String _imageCacheDir = 'ar_images';
  static const String _videoCacheDir = 'ar_videos';

  /// Download and cache image from URL
  Future<String> cacheImage(String imageUrl, String photoId) async {
    try {
      // Validate URL
      if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
        throw Exception('Invalid image URL: $imageUrl');
      }

      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/$_imageCacheDir');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final filePath = '${cacheDir.path}/$photoId.jpg';
      final file = File(filePath);

      // Check if already cached
      if (await file.exists()) {
        print('Image already cached: $filePath');
        return filePath;
      }

      // Download image
      print('Downloading image: $imageUrl');
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print('Image cached: $filePath');
        return filePath;
      } else {
        throw Exception('Failed to download image: ${response.statusCode}');
      }
    } catch (e) {
      print('Error caching image: $e');
      rethrow;
    }
  }

  /// Download and cache video from URL
  Future<String> cacheVideo(String videoUrl, String photoId) async {
    try {
      // Validate URL
      if (videoUrl.isEmpty || !videoUrl.startsWith('http')) {
        throw Exception('Invalid video URL: $videoUrl');
      }

      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/$_videoCacheDir');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final filePath = '${cacheDir.path}/$photoId.mp4';
      final file = File(filePath);

      // Check if already cached
      if (await file.exists()) {
        print('Video already cached: $filePath');
        return filePath;
      }

      // Download video
      print('Downloading video: $videoUrl');
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print('Video cached: $filePath (${response.bodyBytes.length} bytes)');
        return filePath;
      } else {
        throw Exception('Failed to download video: ${response.statusCode}');
      }
    } catch (e) {
      print('Error caching video: $e');
      rethrow;
    }
  }

  /// Cache both image and video for a photo
  Future<Map<String, String>> cachePhotoResources(
    String photoId,
    String imageUrl,
    String videoUrl,
  ) async {
    print('\n📦 Caching resources for photo: $photoId');

    final imagePath = await cacheImage(imageUrl, photoId);
    final videoPath = await cacheVideo(videoUrl, photoId);

    print('✅ Resources cached successfully');
    print('   Image: $imagePath');
    print('   Video: $videoPath\n');

    return {
      'imagePath': imagePath,
      'videoPath': videoPath,
    };
  }

  /// Clear all cached resources
  Future<void> clearCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final imageDir = Directory('${dir.path}/$_imageCacheDir');
      if (await imageDir.exists()) {
        await imageDir.delete(recursive: true);
      }

      final videoDir = Directory('${dir.path}/$_videoCacheDir');
      if (await videoDir.exists()) {
        await videoDir.delete(recursive: true);
      }

      print('Cache cleared');
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  /// Get cache size
  Future<int> getCacheSize() async {
    try {
      int totalSize = 0;
      final dir = await getApplicationDocumentsDirectory();

      final imageDir = Directory('${dir.path}/$_imageCacheDir');
      if (await imageDir.exists()) {
        await for (var file in imageDir.list(recursive: true)) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }

      final videoDir = Directory('${dir.path}/$_videoCacheDir');
      if (await videoDir.exists()) {
        await for (var file in videoDir.list(recursive: true)) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      print('Error getting cache size: $e');
      return 0;
    }
  }
}
