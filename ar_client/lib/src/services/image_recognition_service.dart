import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class ImageRecognitionService {
  // Perceptual hashing parameters - increased for better accuracy
  static const int hashSize = 16; // Increased from 8 for more detail
  static const int highFreqFactor = 2; // Adjusted to maintain 32x32 processing

  /// Compute perceptual hash (pHash) of an image
  /// This creates a hash that's resistant to minor variations
  String computeHash(Uint8List imageBytes) {
    try {
      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // 1. Resize to 32x32 for DCT calculation (using bicubic for better quality)
      final resized = img.copyResize(
        image,
        width: hashSize * highFreqFactor,
        height: hashSize * highFreqFactor,
        interpolation: img.Interpolation.average,
      );

      // 2. Convert to grayscale and enhance contrast
      var grayscale = img.grayscale(resized);
      // Normalize to handle different lighting
      grayscale = img.normalize(grayscale, min: 0, max: 255);
      // Apply contrast adjustment to help with photos of photos
      grayscale = img.adjustColor(grayscale, contrast: 1.2);

      // 3. Compute DCT (Discrete Cosine Transform) - simplified version
      final dctData = _computeDCT(grayscale);

      // 4. Extract low frequency components (top-left 8x8)
      final lowFreq = <double>[];
      for (int y = 0; y < hashSize; y++) {
        for (int x = 0; x < hashSize; x++) {
          lowFreq.add(dctData[y][x]);
        }
      }

      // 5. Compute median
      final sorted = List<double>.from(lowFreq)..sort();
      final median = sorted[sorted.length ~/ 2];

      // 6. Create binary hash
      final bits = lowFreq.map((val) => val > median ? '1' : '0').join();

      // 7. Convert to hex string
      return _binaryToHex(bits);
    } catch (e) {
      throw Exception('Error computing hash: $e');
    }
  }

  /// Simplified DCT computation
  List<List<double>> _computeDCT(img.Image image) {
    final size = hashSize * highFreqFactor;
    final dct = List.generate(size, (_) => List<double>.filled(size, 0.0));

    for (int v = 0; v < size; v++) {
      for (int u = 0; u < size; u++) {
        double sum = 0.0;
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            final pixel = image.getPixel(x, y);
            final luminance = pixel.r.toDouble();
            sum += luminance *
                _cosTable(2 * x + 1, u, size) *
                _cosTable(2 * y + 1, v, size);
          }
        }
        dct[v][u] = sum * _alpha(u, size) * _alpha(v, size);
      }
    }
    return dct;
  }

  double _cosTable(int x, int u, int size) {
    return math.cos((x * u * math.pi) / (2.0 * size));
  }

  double _alpha(int u, int size) {
    return u == 0 ? math.sqrt(1.0 / size) : math.sqrt(2.0 / size);
  }

  String _binaryToHex(String binary) {
    final buffer = StringBuffer();
    for (int i = 0; i < binary.length; i += 4) {
      final chunk = binary.substring(i, (i + 4).clamp(0, binary.length));
      final paddedChunk = chunk.padRight(4, '0');
      final value = int.parse(paddedChunk, radix: 2);
      buffer.write(value.toRadixString(16));
    }
    return buffer.toString();
  }

  /// Calculate Hamming distance between two hashes
  /// Lower distance = more similar images
  int hammingDistance(String hash1, String hash2) {
    if (hash1.length != hash2.length) {
      throw Exception('Hash lengths must match');
    }

    int distance = 0;
    for (int i = 0; i < hash1.length; i++) {
      final val1 = int.parse(hash1[i], radix: 16);
      final val2 = int.parse(hash2[i], radix: 16);
      final xor = val1 ^ val2;

      // Count bits in XOR result
      int bits = xor;
      while (bits > 0) {
        distance += bits & 1;
        bits >>= 1;
      }
    }
    return distance;
  }

  /// Check if two images are similar (threshold = 25 bits difference)
  /// High threshold for real-world photo-of-photo matching
  bool areSimilar(String hash1, String hash2, {int threshold = 25}) {
    return hammingDistance(hash1, hash2) <= threshold;
  }
}
