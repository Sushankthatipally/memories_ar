import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import '../services/firestore_service.dart';
import '../services/image_recognition_service.dart';
import '../services/simple_image_recognition_service.dart';
import '../services/drive_service.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  CameraController? _cameraController;
  final ImageRecognitionService _recognitionService = ImageRecognitionService();
  final SimpleImageRecognitionService _simpleRecognition =
      SimpleImageRecognitionService();
  final FirestoreService _firestoreService = FirestoreService();
  final DriveService _driveService = DriveService();

  List<PhotoData> _clientPhotos = [];
  bool _isScanning = false;
  bool _isLoadingVideo = false;
  VideoPlayerController? _videoController;
  Timer? _scanTimer;
  String _statusMessage = 'Point camera at a photo';
  int _matchThreshold =
      40; // Increased threshold for better real-world matching

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadAllPhotos();
  }

  Future<void> _initializeCamera() async {
    print('\n📷 INITIALIZING CAMERA...');
    try {
      final cameras = await availableCameras();
      print('   Found ${cameras.length} cameras');

      if (cameras.isEmpty) {
        print('   ❌ No cameras available');
        setState(() {
          _statusMessage = 'No camera found';
        });
        return;
      }

      print('   Using camera: ${cameras.first.name}');
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high, // Increased from medium for better quality
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      print('   ✅ Camera initialized successfully');

      if (mounted) {
        setState(() {});
        _startScanning();
      }
    } catch (e) {
      print('   ❌ Camera initialization error: $e');
      setState(() {
        _statusMessage = 'Camera error: $e';
      });
    }
  }

  void _loadAllPhotos() {
    print('═══════════════════════════════════════');
    print('📡 STARTING: Loading photos from Firestore');
    print('═══════════════════════════════════════');

    _firestoreService.getAllPhotos().listen((photos) {
      print('\n✅ FIRESTORE RESPONSE RECEIVED');
      print('   Total photos: ${photos.length}');

      setState(() {
        _clientPhotos = photos;
        print('\n📊 PHOTO DETAILS:');
        print('   Photos stored in memory: ${_clientPhotos.length}');

        if (photos.isEmpty) {
          print('   ⚠️  WARNING: No photos found in Firestore!');
          print('   Check if admin has uploaded any photos.');
        } else {
          for (var i = 0; i < photos.length; i++) {
            var photo = photos[i];
            print('\n   Photo #${i + 1}:');
            print('   ├─ ID: ${photo.id}');
            print('   ├─ Hash: ${photo.imageHash}');
            print('   ├─ Hash Length: ${photo.imageHash.length} chars');
            print(
                '   ├─ Image URL: ${photo.imageURL.substring(0, photo.imageURL.length > 50 ? 50 : photo.imageURL.length)}...');
            print(
                '   └─ Video URL: ${photo.videoURL.substring(0, photo.videoURL.length > 50 ? 50 : photo.videoURL.length)}...');
          }
        }
      });
      print('═══════════════════════════════════════\n');
    }, onError: (error) {
      print('\n❌ FIRESTORE ERROR: $error');
      print('═══════════════════════════════════════\n');
    });
  }

  void _startScanning() {
    print('\n🔄 STARTING SCAN TIMER (every 1.5 seconds)');
    _scanTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (_isScanning || _videoController != null) {
        return;
      }
      print('\n⏱️  SCAN TICK: Initiating frame capture...');
      _scanFrame();
    });
  }

  Future<void> _scanFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('   ⚠️  Camera not ready');
      return;
    }
    if (_isScanning) {
      print('   ⚠️  Already scanning, skipping...');
      return;
    }
    if (_clientPhotos.isEmpty) {
      print('   ⚠️  No photos loaded yet, skipping scan...');
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning...';
    });

    print('\n🔍 SCANNING FRAME:');
    print('   Photos to match against: ${_clientPhotos.length}');

    try {
      final image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      print('   ✅ Frame captured: ${imageBytes.length} bytes');

      // Compute hash of captured frame - use BOTH methods
      print('\n   🔢 METHOD 1: Complex Perceptual Hash (pHash)...');
      final scannedHash = _recognitionService.computeHash(imageBytes);
      print('   ✅ pHash: $scannedHash');

      print('\n   🔢 METHOD 2: Simple Average Hash (aHash)...');
      final simpleHash = _simpleRecognition.computeHash(imageBytes);
      print('   ✅ aHash: $simpleHash');

      // Try to match with stored photos using WEIGHTED SCORING
      PhotoData? bestMatch;
      double bestScore = 0.0; // Higher score = better match
      int bestPHashDist = 999;
      int bestAHashDist = 999;
      String matchMethod = '';

      print('\n   📊 INTELLIGENT WEIGHTED MATCHING:');
      print('   ════════════════════════════════════════════════════');
      for (final photo in _clientPhotos) {
        if (photo.imageHash.isEmpty) {
          print('   ├─ ${photo.id}: SKIPPED (no pHash)');
          continue;
        }

        // Compute pHash distance
        int pHashDistance = 999;
        try {
          pHashDistance = _recognitionService.hammingDistance(
            scannedHash,
            photo.imageHash,
          );
        } catch (e) {
          print('   ├─ ${photo.id}: pHash comparison failed: $e');
        }

        // Compute aHash distance if available
        int aHashDistance = 999;
        if (photo.simpleHash != null && photo.simpleHash!.isNotEmpty) {
          try {
            aHashDistance = _simpleRecognition.hammingDistance(
              simpleHash,
              photo.simpleHash!,
            );
          } catch (e) {
            print('   ├─ ${photo.id}: aHash comparison failed: $e');
          }
        }

        // Calculate weighted score (0-100)
        // Lower distance = higher score
        // pHash weight: 40%, aHash weight: 60% (aHash more reliable for photos)
        double pHashScore = math.max(0, 100 - (pHashDistance * 100 / 256));
        double aHashScore = math.max(0, 100 - (aHashDistance * 100 / 64));
        double totalScore = (pHashScore * 0.4) + (aHashScore * 0.6);

        print('   ├─ ${photo.id}:');
        print(
            '   │  ├─ pHash: $pHashDistance bits (score: ${pHashScore.toStringAsFixed(1)})');
        print(
            '   │  ├─ aHash: $aHashDistance bits (score: ${aHashScore.toStringAsFixed(1)})');
        print('   │  └─ Total Score: ${totalScore.toStringAsFixed(1)}/100');

        if (totalScore > bestScore) {
          bestScore = totalScore;
          bestPHashDist = pHashDistance;
          bestAHashDist = aHashDistance;
          bestMatch = photo;
          matchMethod = aHashDistance < pHashDistance ? 'aHash' : 'pHash';
        }
      }
      print('   ════════════════════════════════════════════════════');

      // Require minimum score of 40/100 for match (adaptive threshold)
      const double minScore = 40.0;

      if (bestMatch != null && bestScore >= minScore) {
        print('\n   🎯 MATCH FOUND!');
        print('   ├─ Photo ID: ${bestMatch.id}');
        print('   ├─ Confidence Score: ${bestScore.toStringAsFixed(1)}/100');
        print('   ├─ pHash distance: $bestPHashDist bits');
        print('   ├─ aHash distance: $bestAHashDist bits');
        print('   ├─ Best method: $matchMethod');
        print('   ├─ Scanned pHash: $scannedHash');
        print('   ├─ Scanned aHash: $simpleHash');
        print('   └─ Playing video...');
        await _playVideo(bestMatch);
      } else {
        print('\n   ❌ NO MATCH FOUND');
        print('   ════════════════════════════════════════════════════');
        print(
            '   Best score: ${bestScore.toStringAsFixed(1)}/100 (need: $minScore)');
        print('   Best pHash: $bestPHashDist bits');
        print('   Best aHash: $bestAHashDist bits');
        print('   ');
        print('   Scanned hashes:');
        print('   ├─ pHash: $scannedHash');
        print('   └─ aHash: $simpleHash');
        print('   ');
        print('   💡 TROUBLESHOOTING:');
        if (bestScore < 20) {
          print('   ├─ Score <20: Completely different image');
          print('   ├─ ⚠️  Make sure you uploaded the EXACT same photo');
          print('   ├─ ⚠️  Check if photo has both hashes in database');
          print('   └─ ⚠️  Try re-uploading with the new algorithm');
        } else if (bestScore < 40) {
          print('   ├─ Score 20-40: Close but significant differences');
          print('   ├─ 💡 Improve lighting (avoid shadows/glare)');
          print('   ├─ 💡 Hold camera steady and parallel to photo');
          print('   ├─ 💡 Ensure good focus (tap to focus on photo)');
          print('   └─ 💡 Try different angle or distance');
        }
        print('   ════════════════════════════════════════════════════');

        setState(() {
          _statusMessage =
              'No match (score: ${bestScore.toStringAsFixed(0)}/100). Check lighting/angle';
          _isScanning = false;
        });
      }
    } catch (e) {
      print('\n   ❌ SCAN ERROR: $e');
      setState(() {
        _statusMessage = 'Scan error';
        _isScanning = false;
      });
    }
  }

  Future<void> _playVideo(PhotoData photo) async {
    print('\n🎬 LOADING VIDEO:');
    print('   Video URL: ${photo.videoURL}');

    setState(() {
      _isLoadingVideo = true;
      _statusMessage = 'Loading video...';
    });

    try {
      // Download video from Cloudinary
      print('   📥 Downloading from Cloudinary...');
      final videoBytes = await _driveService.downloadFile(photo.videoURL);
      print('   ✅ Downloaded: ${videoBytes.length} bytes');

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final videoFile = File(
        '${tempDir.path}/ar_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await videoFile.writeAsBytes(videoBytes);
      print('   💾 Saved to: ${videoFile.path}');

      // Initialize video player
      print('   🎥 Initializing video player...');
      _videoController = VideoPlayerController.file(videoFile);
      await _videoController!.initialize();
      print('   ✅ Video player initialized');

      setState(() {
        _isLoadingVideo = false;
        _isScanning = false;
        _statusMessage = 'Playing video - Tap to close';
      });

      // Auto-play video
      print('   ▶️  Playing video...');
      await _videoController!.play();
      _videoController!.setLooping(true);
      print('   ✅ Video playing successfully!');

      // Clean up video file when done
      videoFile.delete().catchError((e) {
        print('   ⚠️  Failed to delete temp file: $e');
        return videoFile;
      });
    } catch (e) {
      print('\n   ❌ VIDEO LOAD ERROR: $e');
      setState(() {
        _statusMessage = 'Failed to load video';
        _isLoadingVideo = false;
        _isScanning = false;
      });
    }
  }

  void _stopVideo() async {
    if (_videoController != null) {
      await _videoController!.pause();
      await _videoController!.dispose();
    }
    setState(() {
      _videoController = null;
      _statusMessage = 'Point camera at a photo';
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Photo Scanner'),
        actions: [
          // Manual scan button
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _isScanning ? null : _scanFrame,
            tooltip: 'Scan Now',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            SizedBox.expand(child: CameraPreview(_cameraController!))
          else
            const Center(child: CircularProgressIndicator()),

          // Video overlay
          if (_videoController != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _stopVideo,
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
              ),
            ),

          // Status overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_clientPhotos.length} photos | Threshold: $_matchThreshold bits',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  if (_isScanning || _isLoadingVideo)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Scanning frame indicator
          if (_videoController == null)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isScanning ? Colors.blue : Colors.white,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

          // Close video button
          if (_videoController != null)
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, size: 32),
                color: Colors.white,
                onPressed: _stopVideo,
              ),
            ),

          // Threshold adjustment controls (bottom)
          if (_videoController == null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Sensitivity',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$_matchThreshold bits',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Strict',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Expanded(
                          child: Slider(
                            value: _matchThreshold.toDouble(),
                            min: 10,
                            max: 40,
                            divisions: 30,
                            activeColor: Colors.blue,
                            onChanged: (value) {
                              setState(() {
                                _matchThreshold = value.round();
                              });
                            },
                          ),
                        ),
                        const Text(
                          'Lenient',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _matchThreshold < 15
                          ? 'Strict matching'
                          : _matchThreshold < 25
                              ? 'Balanced matching'
                              : _matchThreshold < 35
                                  ? 'Lenient matching'
                                  : 'Very lenient matching',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
