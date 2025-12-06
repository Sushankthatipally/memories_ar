import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';
import '../services/resource_cache_service.dart';

/// Main screen showing list of AR-enabled photos
class PhotoListScreen extends ConsumerStatefulWidget {
  const PhotoListScreen({super.key});

  @override
  ConsumerState<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends ConsumerState<PhotoListScreen> {
  static const platform = MethodChannel('com.arstudio.ar_client/ar');

  final FirestoreService _firestoreService = FirestoreService();
  final ResourceCacheService _cacheService = ResourceCacheService();

  List<PhotoData> _photos = [];
  bool _isLoading = true;
  String _cacheSize = '0 MB';

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _updateCacheSize();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);

    try {
      _firestoreService.getAllPhotos().listen((photos) {
        if (mounted) {
          setState(() {
            _photos = photos;
            _isLoading = false;
          });
          print('Loaded ${photos.length} photos');
        }
      });
    } catch (e) {
      print('Error loading photos: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading photos: $e')),
        );
      }
    }
  }

  Future<void> _updateCacheSize() async {
    final sizeBytes = await _cacheService.getCacheSize();
    final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
    if (mounted) {
      setState(() => _cacheSize = '$sizeMB MB');
    }
  }

  Future<void> _startAR(PhotoData photo) async {
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
                  Text('Preparing AR experience...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Cache photo and video resources
      print('\n🚀 Starting AR for photo: ${photo.id}');
      final paths = await _cacheService.cachePhotoResources(
        photo.id,
        photo.imageURL,
        photo.videoURL,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
      }

      // Launch native AR activity
      await platform.invokeMethod('startAR', {
        'photoId': photo.id,
        'targetImagePath': paths['imagePath']!,
        'videoPath': paths['videoPath']!,
      });

      await _updateCacheSize();
    } on PlatformException catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start AR: ${e.message}')),
        );
      }
      print('Platform error: ${e.message}');
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      print('Error starting AR: $e');
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: Text('Delete all cached images and videos ($_cacheSize)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _cacheService.clearCache();
      await _updateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Photo Album'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear cache ($_cacheSize)',
            onPressed: _clearCache,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadPhotos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No AR photos available',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload photos from admin dashboard',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPhotos,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _photos.length,
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      return _buildPhotoCard(photo);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadPhotos,
        icon: const Icon(Icons.cloud_download),
        label: Text('${_photos.length} Photos'),
      ),
    );
  }

  Widget _buildPhotoCard(PhotoData photo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _startAR(photo),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo preview
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                photo.imageURL,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: Icon(Icons.broken_image, size: 64),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              photo.id,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Album: ${photo.albumId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_filled,
                                size: 16, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(
                              'AR Ready',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.videocam, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Tap to start AR experience',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
