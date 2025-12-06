import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';
import '../services/image_recognition_service.dart';

class AlbumEditorScreen extends StatefulWidget {
  final String albumId;
  final String albumName;

  const AlbumEditorScreen({
    super.key,
    required this.albumId,
    required this.albumName,
  });

  @override
  State<AlbumEditorScreen> createState() => _AlbumEditorScreenState();
}

class _AlbumEditorScreenState extends State<AlbumEditorScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final ImageRecognitionService _imageRecognition = ImageRecognitionService();
  final TextEditingController _albumNameController = TextEditingController();
  bool _isEditingName = false;
  bool _isUpdatingName = false;

  @override
  void initState() {
    super.initState();
    _albumNameController.text = widget.albumName;
  }

  @override
  void dispose() {
    _albumNameController.dispose();
    super.dispose();
  }

  Future<void> _updateAlbumName() async {
    if (_albumNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album name cannot be empty')),
      );
      return;
    }

    setState(() => _isUpdatingName = true);

    try {
      await _firebaseService.updateAlbumName(
        widget.albumId,
        _albumNameController.text.trim(),
      );

      setState(() {
        _isEditingName = false;
        _isUpdatingName = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Album name updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUpdatingName = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating name: $e')),
        );
      }
    }
  }

  Future<void> _addNewPhotoVideoPair() async {
    // Pick photo
    final photoResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );

    if (photoResult == null) return;

    // Pick video
    final videoResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov'],
      withData: true,
    );

    if (videoResult == null) return;

    final photoBytes = photoResult.files.single.bytes!;
    final videoBytes = videoResult.files.single.bytes!;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Uploading media...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final targetId = 'target_${DateTime.now().millisecondsSinceEpoch}';

      // Upload photo
      final imageURL = await _firebaseService.uploadFile(
        albumId: widget.albumId,
        fileName: 'photo_$targetId.jpg',
        bytes: photoBytes,
        contentType: 'image/jpeg',
      );

      // Compute image hash
      final imageHash = _imageRecognition.computeHash(photoBytes);
      print('Computed hash for $targetId: $imageHash');

      // Upload video
      final videoURL = await _firebaseService.uploadFile(
        albumId: widget.albumId,
        fileName: 'video_$targetId.mp4',
        bytes: videoBytes,
        contentType: 'video/mp4',
      );

      // Get album owner's email
      final albumDoc = await FirebaseFirestore.instance
          .collection('albums')
          .doc(widget.albumId)
          .get();
      final ownerId = albumDoc.data()?['owner'] as String?;
      String? clientEmail;
      if (ownerId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .get();
        clientEmail = userDoc.data()?['email'] as String?;
      }

      // Create mapping
      await _firebaseService.addPhotoMapping(
        albumId: widget.albumId,
        targetId: targetId,
        imageURL: imageURL,
        videoURL: videoURL,
        clientEmail: clientEmail,
        imageHash: imageHash,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo-video pair added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading: $e')),
        );
      }
    }
  }

  Future<void> _deletePhoto(String targetId, String photoName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo-Video Pair'),
        content: Text('Are you sure you want to delete "$photoName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firebaseService.deletePhotoMapping(
          albumId: widget.albumId,
          targetId: targetId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo-video pair deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e')),
          );
        }
      }
    }
  }

  Future<void> _updatePhoto(String targetId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );

    if (result == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Updating photo...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final imageURL = await _firebaseService.uploadFile(
        albumId: widget.albumId,
        fileName:
            'photo_${targetId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes: result.files.single.bytes!,
        contentType: 'image/jpeg',
      );

      await _firebaseService.updatePhotoMapping(
        albumId: widget.albumId,
        targetId: targetId,
        imageURL: imageURL,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating photo: $e')),
        );
      }
    }
  }

  Future<void> _updateVideo(String targetId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov'],
      withData: true,
    );

    if (result == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Updating video...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final videoURL = await _firebaseService.uploadFile(
        albumId: widget.albumId,
        fileName:
            'video_${targetId}_${DateTime.now().millisecondsSinceEpoch}.mp4',
        bytes: result.files.single.bytes!,
        contentType: 'video/mp4',
      );

      await _firebaseService.updatePhotoMapping(
        albumId: widget.albumId,
        targetId: targetId,
        videoURL: videoURL,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating video: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isEditingName
            ? TextField(
                controller: _albumNameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Album name',
                  hintStyle: TextStyle(color: Colors.white70),
                ),
              )
            : Text(_albumNameController.text),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          if (_isEditingName)
            IconButton(
              icon: _isUpdatingName
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check),
              onPressed: _isUpdatingName ? null : _updateAlbumName,
              tooltip: 'Save',
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditingName = true;
                });
              },
              tooltip: 'Edit name',
            ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: _addNewPhotoVideoPair,
            tooltip: 'Add photo-video pair',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firebaseService.getAlbumPhotos(widget.albumId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text('Error loading photos: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final photos = snapshot.data?.docs ?? [];

          if (photos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No photos in this album yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add photo-video pairs to get started',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _addNewPhotoVideoPair,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Photo-Video Pair'),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              final data = photo.data() as Map<String, dynamic>;

              return _PhotoVideoCard(
                targetId: data['targetID'] ?? photo.id,
                imageURL: data['imageURL'] ?? '',
                videoURL: data['videoURL'] ?? '',
                createdOn: data['createdOn'] as Timestamp?,
                onUpdatePhoto: () => _updatePhoto(photo.id),
                onUpdateVideo: () => _updateVideo(photo.id),
                onDelete: () =>
                    _deletePhoto(photo.id, data['targetID'] ?? photo.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewPhotoVideoPair,
        icon: const Icon(Icons.add),
        label: const Text('Add Pair'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }
}

class _PhotoVideoCard extends StatelessWidget {
  final String targetId;
  final String imageURL;
  final String videoURL;
  final Timestamp? createdOn;
  final VoidCallback onUpdatePhoto;
  final VoidCallback onUpdateVideo;
  final VoidCallback onDelete;

  const _PhotoVideoCard({
    required this.targetId,
    required this.imageURL,
    required this.videoURL,
    required this.createdOn,
    required this.onUpdatePhoto,
    required this.onUpdateVideo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = createdOn != null
        ? DateFormat('MMM d, yyyy HH:mm').format(createdOn!.toDate())
        : 'Unknown';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview (showing file ID since preview not available)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.grey[200],
              child: imageURL.isNotEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 48),
                        const SizedBox(height: 8),
                        const Text(
                          'Photo Uploaded',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'ID: ${imageURL.substring(0, imageURL.length > 20 ? 20 : imageURL.length)}...',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : const Icon(Icons.image_outlined, size: 48),
            ),
          ),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    targetId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onUpdatePhoto,
                          icon: const Icon(Icons.photo, size: 16),
                          label: const Text('Photo',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onUpdateVideo,
                          icon: const Icon(Icons.videocam, size: 16),
                          label: const Text('Video',
                              style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label:
                          const Text('Delete', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
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
