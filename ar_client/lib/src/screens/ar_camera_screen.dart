import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera-first AR screen with batch download capability
/// Downloads all photo pairs from Firestore, then launches native AR
class ARCameraScreen extends StatefulWidget {
  const ARCameraScreen({super.key});

  @override
  State<ARCameraScreen> createState() => _ARCameraScreenState();
}

class _ARCameraScreenState extends State<ARCameraScreen> {
  static const platform = MethodChannel('com.arstudio.ar_client/ar');

  bool _isDownloading = false;
  bool _isReady = false;
  String _statusMessage = "Press Download to get AR targets";
  double _downloadProgress = 0.0;

  // Lists to pass to native Android
  final List<String> _localImagePaths = [];
  final List<String> _localVideoPaths = [];

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  /// Request camera permission at startup
  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() {
        _statusMessage = "Camera permission denied. Please enable in settings.";
      });
    }
  }

  /// Downloads all photo pairs from Firestore - only from 'default' album
  Future<void> _downloadAllAssets() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = "Fetching photo pairs...";
      _downloadProgress = 0.0;
    });

    try {
      // 1. Fetch photos only from the 'default' album (matches admin portal)
      print('📡 Fetching photos from albums/default/photos...');
      final snapshot = await FirebaseFirestore.instance
          .collection('albums')
          .doc('default')
          .collection('photos')
          .get();

      print('📊 Found ${snapshot.docs.length} documents in default album');

      if (snapshot.docs.isEmpty) {
        setState(() {
          _isDownloading = false;
          _statusMessage = "No photo pairs found in database";
        });
        return;
      }

      // Filter only valid documents with proper Cloudinary URLs
      final validDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        final imageUrl = data['imageURL'] as String?;
        final videoUrl = data['videoURL'] as String?;

        // Must have both URLs
        if (imageUrl == null || videoUrl == null) {
          print('⚠️ Skipping ${doc.id}: missing URL fields');
          return false;
        }

        // Must be valid Cloudinary URLs (or at least valid http URLs)
        final isValidImage =
            imageUrl.startsWith('https://res.cloudinary.com/') ||
                imageUrl.startsWith('http');
        final isValidVideo =
            videoUrl.startsWith('https://res.cloudinary.com/') ||
                videoUrl.startsWith('http');

        if (!isValidImage || !isValidVideo) {
          print('⚠️ Skipping ${doc.id}: invalid URL format');
          print('   imageURL: $imageUrl');
          print('   videoURL: $videoUrl');
          return false;
        }

        return true;
      }).toList();

      print('✅ Valid documents: ${validDocs.length}');

      if (validDocs.isEmpty) {
        setState(() {
          _isDownloading = false;
          _statusMessage = "No valid photo pairs found";
        });
        return;
      }

      final totalCount = validDocs.length;
      final dir = await getApplicationDocumentsDirectory();
      final targetsDir = Directory('${dir.path}/ar_targets');
      final videosDir = Directory('${dir.path}/ar_videos');

      // Create directories if they don't exist
      if (!await targetsDir.exists()) await targetsDir.create(recursive: true);
      if (!await videosDir.exists()) await videosDir.create(recursive: true);

      _localImagePaths.clear();
      _localVideoPaths.clear();

      // 2. Download each valid pair
      for (int i = 0; i < validDocs.length; i++) {
        final doc = validDocs[i];
        final data = doc.data();
        final photoId = doc.id;
        final imageUrl = data['imageURL'] as String;
        final videoUrl = data['videoURL'] as String;

        setState(() {
          _statusMessage = "Downloading ${i + 1}/$totalCount...";
          _downloadProgress = (i + 1) / totalCount;
        });

        try {
          // Download image
          final imageResponse = await http.get(Uri.parse(imageUrl));
          if (imageResponse.statusCode == 200) {
            final imageFile = File('${targetsDir.path}/${photoId}_target.jpg');
            await imageFile.writeAsBytes(imageResponse.bodyBytes);
            _localImagePaths.add(imageFile.path);
          } else {
            print(
                'Failed to download image $photoId: ${imageResponse.statusCode}');
            continue;
          }

          // Download video
          final videoResponse = await http.get(Uri.parse(videoUrl));
          if (videoResponse.statusCode == 200) {
            final videoFile = File('${videosDir.path}/${photoId}_video.mp4');
            await videoFile.writeAsBytes(videoResponse.bodyBytes);
            _localVideoPaths.add(videoFile.path);
          } else {
            print(
                'Failed to download video $photoId: ${videoResponse.statusCode}');
            // Remove image path if video failed
            _localImagePaths.removeLast();
          }
        } catch (e) {
          print('Error downloading $photoId: $e');
        }
      }

      setState(() {
        _isDownloading = false;
        _isReady = _localImagePaths.isNotEmpty;
        _statusMessage = _isReady
            ? "Downloaded ${_localImagePaths.length} targets. Ready!"
            : "No valid targets downloaded";
        _downloadProgress = 1.0;
      });

      // Automatically start AR if we have targets
      if (_isReady) {
        await Future.delayed(const Duration(milliseconds: 500));
        _startARActivity();
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  /// Launches native AR activity with all downloaded targets
  Future<void> _startARActivity() async {
    if (_localImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No targets downloaded. Press Download first.')),
      );
      return;
    }

    // Check camera permission before launching AR
    final status = await Permission.camera.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final result = await Permission.camera.request();
      if (!result.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required for AR'),
            action:
                SnackBarAction(label: 'Settings', onPressed: openAppSettings),
          ),
        );
        return;
      }
    }

    try {
      await platform.invokeMethod('startAR', {
        'imagePaths': _localImagePaths,
        'videoPaths': _localVideoPaths,
      });
    } on PlatformException catch (e) {
      print("Failed to start AR: '${e.message}'.");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AR Error: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera placeholder with status
          Center(
            child: _isDownloading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 20),
                      Text(
                        _statusMessage,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.grey[800],
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isReady ? Icons.check_circle : Icons.camera_alt,
                        size: 80,
                        color: _isReady ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _statusMessage,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),

          // Action buttons overlay
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: _isReady
                  ? FloatingActionButton.extended(
                      onPressed: _startARActivity,
                      label: const Text("Start Camera"),
                      icon: const Icon(Icons.videocam),
                      backgroundColor: Colors.green,
                    )
                  : FloatingActionButton.extended(
                      onPressed: _isDownloading ? null : _downloadAllAssets,
                      label: const Text("Download All Targets"),
                      icon: const Icon(Icons.download),
                      backgroundColor: Colors.blueAccent,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
