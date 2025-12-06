import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  drive.DriveApi? _driveApi;
  String? _folderId;

  // Google Sign In with Drive scope
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '84571858980-qukssseon1lpja64113nt4kc82t222of.apps.googleusercontent.com',
    scopes: [
      drive.DriveApi.driveFileScope,
    ],
  );

  // Initialize Google Drive
  Future<bool> initialize() async {
    try {
      print('Attempting Google Sign-In...');

      // Check if already signed in
      if (_googleSignIn.currentUser != null) {
        print('Already signed in: ${_googleSignIn.currentUser?.email}');
        final account = _googleSignIn.currentUser!;
        final authHeaders = await account.authHeaders;
        final authenticateClient = GoogleAuthClient(authHeaders);
        _driveApi = drive.DriveApi(authenticateClient);
        await _ensureARAlbumsFolder();
        return true;
      }

      // Try silent sign-in first (auto sign-in if previously authorized)
      print('Attempting silent sign-in...');
      var account = await _googleSignIn.signInSilently();

      // If silent sign-in fails, show sign-in prompt
      if (account == null) {
        print('Silent sign-in failed, showing sign-in dialog...');
        account = await _googleSignIn.signIn();
        if (account == null) {
          print('Sign-in cancelled or failed');
          return false;
        }
      }

      print('Signed in successfully: ${account.email}');
      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(authenticateClient);

      // Create or get AR Albums folder
      await _ensureARAlbumsFolder();
      print('Drive initialized successfully');
      return true;
    } catch (e, stackTrace) {
      print('Drive initialization error: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  // Ensure AR Albums folder exists
  Future<void> _ensureARAlbumsFolder() async {
    if (_driveApi == null) return;

    try {
      // Search for existing folder
      final fileList = await _driveApi!.files.list(
        q: "name='AR_Albums' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        spaces: 'drive',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        _folderId = fileList.files!.first.id;
      } else {
        // Create folder
        final folder = drive.File();
        folder.name = 'AR_Albums';
        folder.mimeType = 'application/vnd.google-apps.folder';

        final createdFolder = await _driveApi!.files.create(folder);
        _folderId = createdFolder.id;
      }
    } catch (e) {
      print('Error ensuring folder: $e');
    }
  }

  // Upload file to Google Drive
  Future<String?> uploadFile({
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
    String? albumId,
  }) async {
    if (_driveApi == null || _folderId == null) {
      throw Exception('Drive not initialized');
    }

    try {
      // Create album folder if albumId provided
      String? targetFolderId = _folderId;
      if (albumId != null) {
        targetFolderId = await _getOrCreateAlbumFolder(albumId);
      }

      // Create file metadata
      final driveFile = drive.File();
      driveFile.name = fileName;
      driveFile.parents = [targetFolderId!];
      driveFile.mimeType = mimeType;

      // Upload file
      final media = drive.Media(
        Stream.value(fileBytes),
        fileBytes.length,
      );

      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );

      // Make file accessible with link
      await _driveApi!.permissions.create(
        drive.Permission()
          ..type = 'anyone'
          ..role = 'reader',
        uploadedFile.id!,
      );

      // Return file ID (mobile app will fetch directly from Drive API)
      return uploadedFile.id!;
    } catch (e) {
      print('Upload error: $e');
      return null;
    }
  }

  // Get or create album folder
  Future<String?> _getOrCreateAlbumFolder(String albumId) async {
    if (_driveApi == null || _folderId == null) return null;

    try {
      // Search for album folder
      final fileList = await _driveApi!.files.list(
        q: "name='$albumId' and mimeType='application/vnd.google-apps.folder' and '$_folderId' in parents and trashed=false",
        spaces: 'drive',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first.id;
      }

      // Create album folder
      final folder = drive.File();
      folder.name = albumId;
      folder.mimeType = 'application/vnd.google-apps.folder';
      folder.parents = [_folderId!];

      final createdFolder = await _driveApi!.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      print('Error creating album folder: $e');
      return null;
    }
  }

  // Get file download URL (CORS-friendly)
  Future<String?> getFileUrl(String fileId) async {
    if (_driveApi == null) return null;

    try {
      // Use Google Drive thumbnail API which supports CORS
      // For images: thumbnail, for videos: we'll need to handle differently
      return 'https://drive.google.com/thumbnail?id=$fileId&sz=w1000';
    } catch (e) {
      print('Error getting file URL: $e');
      return null;
    }
  }

  // Delete file
  Future<bool> deleteFile(String fileId) async {
    if (_driveApi == null) return false;

    try {
      await _driveApi!.files.delete(fileId);
      return true;
    } catch (e) {
      print('Delete error: $e');
      return false;
    }
  }

  // List files in album folder
  Future<List<drive.File>> listAlbumFiles(String albumId) async {
    if (_driveApi == null) return [];

    try {
      final folderId = await _getOrCreateAlbumFolder(albumId);
      if (folderId == null) return [];

      final fileList = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name, mimeType, size, createdTime)',
      );

      return fileList.files ?? [];
    } catch (e) {
      print('Error listing files: $e');
      return [];
    }
  }

  // Delete album folder and all contents
  Future<bool> deleteAlbumFolder(String albumId) async {
    if (_driveApi == null) return false;

    try {
      final folderId = await _getOrCreateAlbumFolder(albumId);
      if (folderId == null) return false;

      await _driveApi!.files.delete(folderId);
      return true;
    } catch (e) {
      print('Error deleting album folder: $e');
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _driveApi = null;
    _folderId = null;
  }
}

// Custom HTTP client for Google Sign-In authentication
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
