import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/firebase_service.dart';

class CreateAlbumScreen extends StatefulWidget {
  const CreateAlbumScreen({super.key});

  @override
  State<CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<CreateAlbumScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController albumNameController = TextEditingController();
  final TextEditingController clientNameController = TextEditingController();
  final TextEditingController clientEmailController = TextEditingController();
  final TextEditingController clientPasswordController = TextEditingController();

  String? albumId;
  String? albumCode;
  bool _isCreatingAlbum = false;
  bool _albumCreated = false;

  // Photo-Video pairs
  final List<MediaPair> _mediaPairs = [];
  bool _isUploading = false;

  @override
  void dispose() {
    albumNameController.dispose();
    clientNameController.dispose();
    clientEmailController.dispose();
    clientPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createAlbum() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreatingAlbum = true);

    try {
      final result = await _firebaseService.createClientAndAlbum(
        clientEmail: clientEmailController.text.trim(),
        clientPassword: clientPasswordController.text.trim(),
        clientName: clientNameController.text.trim(),
        albumName: albumNameController.text.trim(),
      );

      setState(() {
        albumId = result['albumId'];
        albumCode = result['albumCode'];
        _albumCreated = true;
        _isCreatingAlbum = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Album created successfully! Code: $albumCode'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isCreatingAlbum = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating album: $e')),
        );
      }
    }
  }

  Future<void> _addMediaPair() async {
    setState(() {
      _mediaPairs.add(MediaPair());
    });
  }

  Future<void> _pickFile(MediaPair pair, bool isPhoto) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: isPhoto ? ['jpg', 'jpeg', 'png'] : ['mp4', 'mov'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        if (isPhoto) {
          pair.photoBytes = result.files.single.bytes;
          pair.photoName = result.files.single.name;
        } else {
          pair.videoBytes = result.files.single.bytes;
          pair.videoName = result.files.single.name;
        }
      });
    }
  }

  Future<void> _uploadMediaPairs() async {
    if (albumId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create album first')),
      );
      return;
    }

    // Validate all pairs have both photo and video
    for (var pair in _mediaPairs) {
      if (pair.photoBytes == null || pair.videoBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All pairs must have both photo and video'),
          ),
        );
        return;
      }
    }

    setState(() => _isUploading = true);

    try {
      for (int i = 0; i < _mediaPairs.length; i++) {
        final pair = _mediaPairs[i];
        final targetId = 'target_${DateTime.now().millisecondsSinceEpoch}_$i';

        // Upload photo
        final imageURL = await _firebaseService.uploadFile(
          albumId: albumId!,
          fileName: 'photo_$targetId.jpg',
          bytes: pair.photoBytes!,
          contentType: 'image/jpeg',
        );

        // Upload video
        final videoURL = await _firebaseService.uploadFile(
          albumId: albumId!,
          fileName: 'video_$targetId.mp4',
          bytes: pair.videoBytes!,
          contentType: 'video/mp4',
        );

        // Create mapping
        await _firebaseService.addPhotoMapping(
          albumId: albumId!,
          targetId: targetId,
          imageURL: imageURL,
          videoURL: videoURL,
        );

        setState(() {
          pair.uploaded = true;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All media uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate back to dashboard
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading media: $e')),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Album'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step 1: Create Album
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 1: Album & Client Details',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Album Name
                      TextFormField(
                        controller: albumNameController,
                        decoration: const InputDecoration(
                          labelText: 'Album Name *',
                          hintText: 'e.g., Wedding Album - John & Jane',
                          prefixIcon: Icon(Icons.photo_album),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter album name';
                          }
                          return null;
                        },
                        enabled: !_albumCreated,
                      ),
                      const SizedBox(height: 16),

                      // Client Name
                      TextFormField(
                        controller: clientNameController,
                        decoration: const InputDecoration(
                          labelText: 'Client Name *',
                          hintText: 'e.g., John Doe',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter client name';
                          }
                          return null;
                        },
                        enabled: !_albumCreated,
                      ),
                      const SizedBox(height: 16),

                      // Client Email
                      TextFormField(
                        controller: clientEmailController,
                        decoration: const InputDecoration(
                          labelText: 'Client Email *',
                          hintText: 'client@example.com',
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter client email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter valid email';
                          }
                          return null;
                        },
                        enabled: !_albumCreated,
                      ),
                      const SizedBox(height: 16),

                      // Client Password
                      TextFormField(
                        controller: clientPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Client Password *',
                          hintText: 'Temporary password for client',
                          prefixIcon: Icon(Icons.lock),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        enabled: !_albumCreated,
                      ),
                      const SizedBox(height: 24),

                      if (!_albumCreated)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isCreatingAlbum ? null : _createAlbum,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: _isCreatingAlbum
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text('Create Album'),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Album created successfully!',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                    Text('Album Code: $albumCode'),
                                    Text('Album ID: $albumId'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (_albumCreated) ...[
              const SizedBox(height: 24),

              // Step 2: Upload Media
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Step 2: Upload Photos & Videos',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _addMediaPair,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Photo-Video Pair'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_mediaPairs.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.add_photo_alternate,
                                    size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text(
                                  'No media pairs added yet',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Click "Add Photo-Video Pair" to get started',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _mediaPairs.length,
                          itemBuilder: (context, index) {
                            final pair = _mediaPairs[index];
                            return _MediaPairCard(
                              index: index,
                              pair: pair,
                              onPickPhoto: () => _pickFile(pair, true),
                              onPickVideo: () => _pickFile(pair, false),
                              onRemove: () {
                                setState(() {
                                  _mediaPairs.removeAt(index);
                                });
                              },
                            );
                          },
                        ),

                      if (_mediaPairs.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isUploading ? null : _uploadMediaPairs,
                            icon: _isUploading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload),
                            label: Text(_isUploading
                                ? 'Uploading...'
                                : 'Upload All Media'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MediaPair {
  Uint8List? photoBytes;
  String? photoName;
  Uint8List? videoBytes;
  String? videoName;
  bool uploaded = false;
}

class _MediaPairCard extends StatelessWidget {
  final int index;
  final MediaPair pair;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickVideo;
  final VoidCallback onRemove;

  const _MediaPairCard({
    required this.index,
    required this.pair,
    required this.onPickPhoto,
    required this.onPickVideo,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: pair.uploaded ? Colors.green[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Pair ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (pair.uploaded)
                  const Icon(Icons.check_circle, color: Colors.green)
                else
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                    color: Colors.red,
                    tooltip: 'Remove',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: pair.uploaded ? null : onPickPhoto,
                    icon: Icon(
                      pair.photoBytes != null ? Icons.check : Icons.add_photo_alternate,
                    ),
                    label: Text(
                      pair.photoBytes != null
                          ? 'Photo: ${pair.photoName}'
                          : 'Select Photo',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pair.photoBytes != null ? Colors.green : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: pair.uploaded ? null : onPickVideo,
                    icon: Icon(
                      pair.videoBytes != null ? Icons.check : Icons.videocam,
                    ),
                    label: Text(
                      pair.videoBytes != null
                          ? 'Video: ${pair.videoName}'
                          : 'Select Video',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pair.videoBytes != null ? Colors.green : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
