import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Alternative image recognition using simpler average hash
/// More robust for photo-of-photo scenarios
class SimpleImageRecognitionService {
  // Use smaller hash for better real-world matching
  static const int hashSize = 8;

  /// Compute average hash (aHash) - simpler and more robust than pHash
  /// Works better for photo-of-photo scenarios
  String computeHash(Uint8List imageBytes) {
    try {
      print('   📸 Computing simple hash (aHash)...');
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // 1. Resize to small square (reduces noise and variations)
      final resized = img.copyResize(
        image,
        width: hashSize,
        height: hashSize,
        interpolation: img.Interpolation.average,
      );

      // 2. Convert to grayscale
      var grayscale = img.grayscale(resized);

      // 3. Normalize brightness (critical for different lighting)
      grayscale = img.normalize(grayscale, min: 0, max: 255);

      // 4. Calculate average pixel value
      int sum = 0;
      for (int y = 0; y < hashSize; y++) {
        for (int x = 0; x < hashSize; x++) {
          final pixel = grayscale.getPixel(x, y);
          sum += pixel.r.toInt();
        }
      }
      final average = sum / (hashSize * hashSize);

      // 5. Create binary hash (1 if above average, 0 if below)
      final bits = StringBuffer();
      for (int y = 0; y < hashSize; y++) {
        for (int x = 0; x < hashSize; x++) {
          final pixel = grayscale.getPixel(x, y);
          bits.write(pixel.r > average ? '1' : '0');
        }
      }

      // 6. Convert to hex
      final hash = _binaryToHex(bits.toString());
      print('   ✅ Simple hash (aHash): $hash (${hash.length} chars)');

      return hash;
    } catch (e) {
      print('   ❌ Simple hash computation error: $e');
      throw Exception('Error computing hash: $e');
    }
  }

  String _binaryToHex(String binary) {
    final buffer = StringBuffer();
    for (int i = 0; i < binary.length; i += 4) {
      final chunk = binary.substring(i, math.min(i + 4, binary.length));
      final paddedChunk = chunk.padRight(4, '0');
      final value = int.parse(paddedChunk, radix: 2);
      buffer.write(value.toRadixString(16));
    }
    return buffer.toString();
  }

  /// Calculate Hamming distance
  int hammingDistance(String hash1, String hash2) {
    if (hash1.length != hash2.length) {
      throw Exception('Hash lengths must match');
    }

    int distance = 0;
    for (int i = 0; i < hash1.length; i++) {
      final val1 = int.parse(hash1[i], radix: 16);
      final val2 = int.parse(hash2[i], radix: 16);
      final xor = val1 ^ val2;

      // Count set bits
      int bits = xor;
      while (bits > 0) {
        distance += bits & 1;
        bits >>= 1;
      }
    }
    return distance;
  }

  /// Check similarity with adaptive threshold
  bool areSimilar(String hash1, String hash2, {int threshold = 15}) {
    final distance = hammingDistance(hash1, hash2);
    return distance <= threshold;
  }
}
