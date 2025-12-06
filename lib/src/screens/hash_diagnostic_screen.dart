import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';

// Data class
class PhotoHashInfo {
  final String id;
  final String albumId;
  final String imageHash;
  final String imageURL;
  final String videoURL;

  PhotoHashInfo({
    required this.id,
    required this.albumId,
    required this.imageHash,
    required this.imageURL,
    required this.videoURL,
  });

  bool get isValid {
    // New 256-bit hash should be 64 hex characters (32 bytes * 2)
    // 16x16 grid = 256 bits = 64 hex chars
    return imageHash.isNotEmpty && imageHash.length == 64;
  }

  String get hashStatus {
    if (imageHash.isEmpty) {
      return '❌ No hash (empty)';
    } else if (imageHash.length == 16) {
      return '⚠️ Old 64-bit hash (16 chars)';
    } else if (imageHash.length == 64) {
      return '✅ Valid 256-bit hash (64 chars)';
    } else {
      return '❓ Unknown format (${imageHash.length} chars)';
    }
  }
}

/// Diagnostic screen to check hash status in Firestore
class HashDiagnosticScreen extends StatefulWidget {
  const HashDiagnosticScreen({super.key});

  @override
  State<HashDiagnosticScreen> createState() => _HashDiagnosticScreenState();
}

class _HashDiagnosticScreenState extends State<HashDiagnosticScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = true;
  List<PhotoHashInfo> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);

    try {
      final snapshot =
          await FirebaseFirestore.instance.collectionGroup('photos').get();

      final photos = <PhotoHashInfo>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        photos.add(PhotoHashInfo(
          id: doc.id,
          albumId: data['albumId'] ?? 'unknown',
          imageHash: data['imageHash'] ?? '',
          imageURL: data['imageURL'] ?? '',
          videoURL: data['videoURL'] ?? '',
        ));
      }

      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading photos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePhoto(PhotoHashInfo photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content:
            Text('Delete ${photo.id}?\n\nThis photo has ${photo.hashStatus}.'),
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
          albumId: photo.albumId,
          targetId: photo.id,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Photo deleted'), backgroundColor: Colors.green),
          );
          _loadPhotos();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteAllInvalidPhotos() async {
    final invalidPhotos = _photos.where((p) => !p.isValid).toList();

    if (invalidPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invalid photos to delete')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Invalid Photos'),
        content: Text(
            'Delete ${invalidPhotos.length} photos with missing or old hashes?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        for (var photo in invalidPhotos) {
          await _firebaseService.deletePhotoMapping(
            albumId: photo.albumId,
            targetId: photo.id,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted ${invalidPhotos.length} invalid photos'),
              backgroundColor: Colors.green,
            ),
          );
          _loadPhotos();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final validPhotos = _photos.where((p) => p.isValid).length;
    final invalidPhotos = _photos.where((p) => !p.isValid).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hash Diagnostics'),
        backgroundColor: Colors.indigo,
        actions: [
          if (invalidPhotos > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _deleteAllInvalidPhotos,
              tooltip: 'Delete all invalid',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPhotos,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary Card
                Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.indigo[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Database Status',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                                'Total', _photos.length, Colors.blue),
                            _buildStatItem(
                                '✅ Valid', validPhotos, Colors.green),
                            _buildStatItem(
                                '❌ Invalid', invalidPhotos, Colors.red),
                          ],
                        ),
                        if (invalidPhotos > 0) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning, color: Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Found $invalidPhotos photo(s) with old or missing hashes. These must be deleted and re-uploaded.',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Photo List
                Expanded(
                  child: _photos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library_outlined,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No photos in database',
                                  style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _photos.length,
                          itemBuilder: (context, index) {
                            final photo = _photos[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: photo.isValid
                                  ? Colors.green[50]
                                  : Colors.red[50],
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      photo.isValid ? Colors.green : Colors.red,
                                  child: Icon(
                                    photo.isValid ? Icons.check : Icons.error,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  photo.id,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '📂 Album: ${photo.albumId}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      '🔑 Hash: ${photo.hashStatus}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: photo.isValid
                                            ? Colors.green[800]
                                            : Colors.red[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (photo.imageHash.isNotEmpty)
                                      Text(
                                        '   ${photo.imageHash.substring(0, photo.imageHash.length > 40 ? 40 : photo.imageHash.length)}...',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontFamily: 'monospace'),
                                      ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deletePhoto(photo),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
