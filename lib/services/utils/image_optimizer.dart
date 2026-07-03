import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../config/app_config.dart';

/// Utilitaires pour l'optimisation des images
class ImageOptimizer {
  /// Optimise une image avec la qualité de compression spécifiée
  static Uint8List optimizeImage(Uint8List imageBytes, {int? quality}) {
    final targetQuality = quality ?? AppConfig.imageCompressionQuality;
    return _optimizeImage(imageBytes, targetQuality);
  }

  /// Optimise une image (implémentation interne)
  static Uint8List _optimizeImage(Uint8List imageBytes, int compressionQuality) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return imageBytes;
      }

      final maxSize = 800;
      final width = image.width;
      final height = image.height;
      final ratio = width > height ? maxSize / width : maxSize / height;

      final targetQuality = compressionQuality.clamp(0, 100);

      if (ratio < 1.0) {
        final resized = img.copyResize(
          image,
          width: (width * ratio).round(),
          height: (height * ratio).round(),
        );
        return img.encodeJpg(resized, quality: targetQuality);
      }

      return img.encodeJpg(image, quality: targetQuality);
    } catch (e) {
      return imageBytes;
    }
  }

  /// Redimensionne une image à une taille maximale
  static Uint8List resizeImage(Uint8List imageBytes, {int maxWidth = 800, int maxHeight = 800}) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return imageBytes;
      }

      final width = image.width;
      final height = image.height;
      final ratio = width > height ? maxWidth / width : maxHeight / height;

      if (ratio < 1.0) {
        final resized = img.copyResize(
          image,
          width: (width * ratio).round(),
          height: (height * ratio).round(),
        );
        return img.encodeJpg(resized, quality: 85);
      }

      return imageBytes;
    } catch (e) {
      return imageBytes;
    }
  }
}