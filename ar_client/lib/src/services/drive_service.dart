import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Service to download files from Cloudinary (or any public URL)
class DriveService {
  /// Download file content from a public URL
  /// Works with Cloudinary URLs and any other public file URLs
  Future<Uint8List> downloadFile(String url) async {
    try {
      print('Downloading file from: $url');
      final response = await http.get(Uri.parse(url));

      print('Download response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        print(
          'File downloaded successfully: ${response.bodyBytes.length} bytes',
        );
        return response.bodyBytes;
      } else {
        print('Download error response: ${response.body}');
        throw Exception(
          'Failed to download file: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Download error: $e');
      throw Exception('Failed to download file: $e');
    }
  }
}
