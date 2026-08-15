import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../config/app_config.dart';

/// Utilitaires pour l'optimisation des images.
///
/// L'export se fait en PNG (et non JPEG) pour éviter les problèmes de
/// décodage avec les images HEIC importées depuis iPhone. Le package `image`
/// (Dart pur) ne supporte pas le décodage HEIC, mais il peut encoder en PNG
/// après décodage via `flutter_image_compress` (qui gère le HEIC nativement).
///
/// Le PNG est lossless, donc le paramètre `quality` n'affecte que le
/// redimensionnement (taille maximale en pixels).
class ImageOptimizer {
  /// Optimise une image: redimensionne si nécessaire et encode en PNG.
  static Uint8List optimizeImage(Uint8List imageBytes, {int? quality}) {
    return _optimizeImage(imageBytes);
  }

  /// Optimise une image (implémentation interne).
  static Uint8List _optimizeImage(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        // Le décodage a échoué (HEIC non supporté par le package `image`).
        // On retourne l'image originale — elle sera ajoutée telle quelle
        // à l'archive ODP.
        return imageBytes;
      }

      final maxSize = 800;
      final width = image.width;
      final height = image.height;
      final ratio = width > height ? maxSize / width : maxSize / height;

      if (ratio < 1.0) {
        final resized = img.copyResize(
          image,
          width: (width * ratio).round(),
          height: (height * ratio).round(),
        );
        return Uint8List.fromList(img.encodePng(resized));
      }

      return Uint8List.fromList(img.encodePng(image));
    } catch (e) {
      return imageBytes;
    }
  }

  /// Redimensionne une image à une taille maximale.
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
        return Uint8List.fromList(img.encodePng(resized));
      }

      return imageBytes;
    } catch (e) {
      return imageBytes;
    }
  }
}
