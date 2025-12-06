import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Color histogram matching for image recognition
/// More robust to lighting changes and viewing angles
class ColorHistogramService {
  static const int bins = 8; // 8x8x8 = 512 bins for RGB

  /// Compute color histogram
  List<int> computeHistogram(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Resize to reduce computation (but keep color info)
      final resized = img.copyResize(
        image,
        width: 64,
        height: 64,
        interpolation: img.Interpolation.average,
      );

      // Initialize histogram bins
      final histogram = List<int>.filled(bins * bins * bins, 0);

      // Count pixels in each bin
      for (int y = 0; y < resized.height; y++) {
        for (int x = 0; x < resized.width; x++) {
          final pixel = resized.getPixel(x, y);
          final r = (pixel.r * bins / 256).floor().clamp(0, bins - 1);
          final g = (pixel.g * bins / 256).floor().clamp(0, bins - 1);
          final b = (pixel.b * bins / 256).floor().clamp(0, bins - 1);
          final binIndex = r * bins * bins + g * bins + b;
          histogram[binIndex]++;
        }
      }

      // Normalize histogram
      final total = resized.width * resized.height;
      return histogram.map((count) => (count * 1000 / total).round()).toList();
    } catch (e) {
      throw Exception('Error computing histogram: $e');
    }
  }

  /// Compare histograms using Chi-Square distance
  /// Lower values = more similar
  double compareHistograms(List<int> hist1, List<int> hist2) {
    if (hist1.length != hist2.length) {
      throw Exception('Histogram lengths must match');
    }

    double distance = 0.0;
    for (int i = 0; i < hist1.length; i++) {
      final sum = hist1[i] + hist2[i];
      if (sum > 0) {
        final diff = hist1[i] - hist2[i];
        distance += (diff * diff) / sum;
      }
    }
    return distance;
  }

  /// Check if histograms are similar
  bool areSimilar(List<int> hist1, List<int> hist2,
      {double threshold = 200.0}) {
    final distance = compareHistograms(hist1, hist2);
    return distance < threshold;
  }

  /// Encode histogram to string for storage
  String encodeHistogram(List<int> histogram) {
    return histogram.join(',');
  }

  /// Decode histogram from string
  List<int> decodeHistogram(String encoded) {
    return encoded.split(',').map((s) => int.parse(s)).toList();
  }
}
