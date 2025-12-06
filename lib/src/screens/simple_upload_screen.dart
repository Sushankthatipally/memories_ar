import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/firebase_service.dart';
import '../services/image_recognition_service.dart';
import '../services/simple_image_recognition_service.dart';

class SimpleUploadScreen extends StatefulWidget {
  const SimpleUploadScreen({super.key});

  @override
  State<SimpleUploadScreen> createState() => _SimpleUploadScreenState();
}

class _SimpleUploadScreenState extends State<SimpleUploadScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final ImageRecognitionService _imageRecognition = ImageRecognitionService();
  final SimpleImageRecognitionService _simpleRecognition =
      SimpleImageRecognitionService();

  final List<MediaPair> _mediaPairs = [];
  final List<UploadedPair> _uploadedPairs = [];
  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadUploadedPairs();
  }

  void _loadUploadedPairs() {
    _firebaseService.getAlbumPhotos('default').listen((snapshot) {
      setState(() {
        _uploadedPairs.clear();
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          _uploadedPairs.add(UploadedPair(
            id: doc.id,
            targetId: data['targetID'] ?? '',
            imageURL: data['imageURL'] ?? '',
            videoURL: data['videoURL'] ?? '',
            imageHash: data['imageHash'] ?? '',
          ));
        }
      });
    });
  }

  void _addMediaPair() async {
    try {
      // Pick photo first (must be synchronous with user gesture)
      final photoResult = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );

      if (photoResult == null || photoResult.files.isEmpty) {
        print('Photo selection cancelled');
        return;
      }

      final photoBytes = photoResult.files.first.bytes;
      final photoName = photoResult.files.first.name;

      if (photoBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to read photo data')),
          );
        }
        return;
      }

      // Pick video second
      final videoResult = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
        allowMultiple: false,
      );

      if (videoResult == null || videoResult.files.isEmpty) {
        print('Video selection cancelled');
        return;
      }

      final videoBytes = videoResult.files.first.bytes;
      final videoName = videoResult.files.first.name;

      if (videoBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to read video data')),
          );
        }
        return;
      }

      // Add pair to list
      setState(() {
        _mediaPairs.add(MediaPair(
          photoBytes: photoBytes,
          photoName: photoName,
          videoBytes: videoBytes,
          videoName: videoName,
        ));
      });

      print('Added pair: $photoName + $videoName');
    } catch (e) {
      print('Error picking files: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting files: $e')),
        );
      }
    }
  }

  Future<void> _uploadAll() async {
    if (_mediaPairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please add at least one photo-video pair')),
      );
      return;
    }

    print('\n═══════════════════════════════════════════════════════');
    print('🚀 STARTING UPLOAD PROCESS');
    print('═══════════════════════════════════════════════════════');
    print('   Total pairs to upload: ${_mediaPairs.length}');

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading...';
    });

    try {
      for (int i = 0; i < _mediaPairs.length; i++) {
        print('\n📦 UPLOADING PAIR ${i + 1}/${_mediaPairs.length}');
        print('─────────────────────────────────────────────────────');

        setState(() {
          _uploadStatus = 'Uploading pair ${i + 1} of ${_mediaPairs.length}...';
        });

        final pair = _mediaPairs[i];
        final targetId = 'target_${DateTime.now().millisecondsSinceEpoch}_$i';
        print('   Target ID: $targetId');

        // Compute both image hashes for hybrid matching
        print('\n   🔢 COMPUTING HASHES...');
        print('   Computing pHash (complex perceptual hash)...');
        final imageHash = _imageRecognition.computeHash(pair.photoBytes);
        print('   ✅ pHash: $imageHash (${imageHash.length} chars)');

        print('   Computing aHash (simple average hash)...');
        final simpleHash = _simpleRecognition.computeHash(pair.photoBytes);
        print('   ✅ aHash: $simpleHash (${simpleHash.length} chars)');
        print('   Both hashes ready for hybrid matching!');

        // Upload photo to Cloudinary
        print('\n   📤 UPLOADING PHOTO TO CLOUDINARY...');
        print('   File: ${pair.photoName}');
        print('   Size: ${pair.photoBytes.length} bytes');
        final imageURL = await _firebaseService.uploadFile(
          albumId: 'default',
          fileName: 'photo_$targetId.jpg',
          bytes: pair.photoBytes,
          contentType: 'image/jpeg',
        );
        print('   ✅ Photo uploaded: $imageURL');

        // Upload video to Cloudinary
        print('\n   🎥 UPLOADING VIDEO TO CLOUDINARY...');
        print('   File: ${pair.videoName}');
        print('   Size: ${pair.videoBytes.length} bytes');
        final videoURL = await _firebaseService.uploadFile(
          albumId: 'default',
          fileName: 'video_$targetId.mp4',
          bytes: pair.videoBytes,
          contentType: 'video/mp4',
        );
        print('   ✅ Video uploaded: $videoURL');

        // Save to Firestore
        print('\n   💾 SAVING TO FIRESTORE...');
        print('   Collection: albums/default/photos');
        print('   Document ID: $targetId');
        print('   Data:');
        print('      ├─ imageHash (pHash): $imageHash');
        print('      ├─ simpleHash (aHash): $simpleHash');
        print('      ├─ imageURL: $imageURL');
        print('      └─ videoURL: $videoURL');

        await _firebaseService.addPhotoMapping(
          albumId: 'default',
          targetId: targetId,
          imageURL: imageURL,
          videoURL: videoURL,
          imageHash: imageHash,
          simpleHash: simpleHash,
        );
        print('   ✅ Saved to Firestore successfully!');

        pair.isUploaded = true;
        setState(() {});
        print('\n   ✅ PAIR ${i + 1} COMPLETE!');
      }

      print('\n═══════════════════════════════════════════════════════');
      print('✅ ALL UPLOADS COMPLETE!');
      print('═══════════════════════════════════════════════════════\n');

      setState(() {
        _isUploading = false;
        _uploadStatus = 'All uploads complete!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully uploaded ${_mediaPairs.length} photo-video pairs!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('\n❌ UPLOAD FAILED!');
      print('═══════════════════════════════════════════════════════');
      print('Error: $e');
      print('═══════════════════════════════════════════════════════\n');

      setState(() {
        _isUploading = false;
        _uploadStatus = 'Upload failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removePair(int index) {
    setState(() {
      _mediaPairs.removeAt(index);
    });
  }

  Future<void> _deleteUploadedPair(UploadedPair pair) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pair'),
        content: Text('Delete ${pair.targetId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firebaseService.deletePhotoMapping(
          albumId: 'default',
          targetId: pair.id,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pair deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteAllPhotos() async {
    if (_uploadedPairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos to delete')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Photos'),
        content: Text(
          'This will permanently delete all ${_uploadedPairs.length} uploaded photo-video pairs from Firestore.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE ALL',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Deleting all photos...'),
                  ],
                ),
              ),
            ),
          ),
        );

        await _firebaseService.deleteAllPhotos(albumId: 'default');

        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All photos deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _clearAll() {
    setState(() {
      _mediaPairs.clear();
      _uploadStatus = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Photo Upload'),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          if (_mediaPairs.isNotEmpty && !_isUploading)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearAll,
              tooltip: 'Clear all',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _firebaseService.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          // Upload status banner
          if (_uploadStatus.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _isUploading ? Colors.blue[100] : Colors.green[100],
              child: Row(
                children: [
                  if (_isUploading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _uploadStatus,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Media pairs list
          Expanded(
            child: _mediaPairs.isEmpty && _uploadedPairs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No photo-video pairs yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Upload photo and video pairs for AR',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed:
                              _isUploading ? null : () => _addMediaPair(),
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Add Photo-Video Pair'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Already uploaded pairs section
                      if (_uploadedPairs.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_done, color: Colors.green[700]),
                              const SizedBox(width: 8),
                              Text(
                                'Uploaded Pairs (${_uploadedPairs.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _deleteAllPhotos,
                                icon: const Icon(Icons.delete_sweep, size: 18),
                                label: const Text('Delete All'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._uploadedPairs.map((pair) => Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: Colors.green[50],
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green,
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  pair.targetId,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '📷 Photo: ${pair.imageURL.substring(0, 20)}...',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      '🎥 Video: ${pair.videoURL.substring(0, 20)}...',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      '🔑 Hash: ${pair.imageHash.substring(0, 16)}...',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deleteUploadedPair(pair),
                                ),
                              ),
                            )),
                        const SizedBox(height: 16),
                      ],

                      // Pending upload pairs section
                      if (_mediaPairs.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.upload_file,
                                  color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              Text(
                                'Pending Upload (${_mediaPairs.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._mediaPairs.asMap().entries.map((entry) {
                          final index = entry.key;
                          final pair = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.orange[50],
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: pair.isUploaded
                                    ? Colors.green
                                    : Theme.of(context).primaryColor,
                                child: Icon(
                                  pair.isUploaded ? Icons.check : Icons.photo,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                'Pair ${index + 1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '📷 ${pair.photoName}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    '🎥 ${pair.videoName}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: _isUploading
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => _removePair(index),
                                    ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_mediaPairs.isNotEmpty && !_isUploading)
            FloatingActionButton.extended(
              onPressed: _uploadAll,
              backgroundColor: Colors.green,
              icon: const Icon(Icons.cloud_upload),
              label: Text('Upload All (${_mediaPairs.length})'),
              heroTag: 'upload',
            ),
          if (_mediaPairs.isNotEmpty && !_isUploading)
            const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: _isUploading ? null : () => _addMediaPair(),
            backgroundColor:
                _isUploading ? Colors.grey : Theme.of(context).primaryColor,
            heroTag: 'add',
            tooltip: 'Add Photo-Video Pair',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class MediaPair {
  final Uint8List photoBytes;
  final String photoName;
  final Uint8List videoBytes;
  final String videoName;
  bool isUploaded;

  MediaPair({
    required this.photoBytes,
    required this.photoName,
    required this.videoBytes,
    required this.videoName,
    this.isUploaded = false,
  });
}

class UploadedPair {
  final String id;
  final String targetId;
  final String imageURL;
  final String videoURL;
  final String imageHash;

  UploadedPair({
    required this.id,
    required this.targetId,
    required this.imageURL,
    required this.videoURL,
    required this.imageHash,
  });
}
