import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Utilitaire pour gérer les différents formats d'image dans l'export ODP
/// 
/// Formats supportés:
/// - JPEG/JPG (.jpg, .jpeg) -> image/jpeg
/// - PNG (.png) -> image/png
/// - HEIC/HEIF (.heic, .heif) -> converti en JPEG (LibreOffice ne supporte pas HEIC)
class ImageFormatUtils {
  /// Extensions d'image supportées nativement par LibreOffice
  static const List<String> supportedExtensions = ['.jpg', '.jpeg', '.png'];
  
  /// Extensions qui nécessitent une conversion
  static const List<String> convertibleExtensions = ['.heic', '.heif'];
  
  /// Map des extensions vers les MIME types
  static const Map<String, String> mimeTypes = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.heic': 'image/heic',
    '.heif': 'image/heif',
  };
  
  /// Extension par défaut pour les images converties
  static const String defaultOutputExtension = '.jpg';
  
  /// MIME type par défaut pour les images converties
  static const String defaultOutputMimeType = 'image/jpeg';
  
  /// Obtient l'extension et le MIME type pour un fichier image
  /// 
  /// Pour les formats non supportés (HEIC/HEIF), retourne l'extension et MIME type
  /// pour le format converti (JPEG)
  static (String extension, String mimeType) getImageFormatInfo(String filePath) {
    final lowerPath = filePath.toLowerCase();
    
    // Vérifier les extensions supportées
    for (final ext in supportedExtensions) {
      if (lowerPath.endsWith(ext)) {
        return (ext, mimeTypes[ext]!);
      }
    }
    
    // Vérifier les extensions convertibles
    for (final ext in convertibleExtensions) {
      if (lowerPath.endsWith(ext)) {
        // Ces formats seront convertis en JPEG
        return (defaultOutputExtension, defaultOutputMimeType);
      }
    }
    
    // Par défaut, on suppose JPEG
    return (defaultOutputExtension, defaultOutputMimeType);
  }
  
  /// Vérifie si un fichier doit être converti
  static bool needsConversion(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return convertibleExtensions.any((ext) => lowerPath.endsWith(ext));
  }
  
  /// Convertit une image HEIC/HEIF en JPEG
  /// 
  /// Utilise flutter_image_compress pour la conversion
  /// Retourne les bytes de l'image convertie en JPEG
  static Future<Uint8List> convertToJpeg(Uint8List imageBytes) async {
    try {
      // Utiliser flutter_image_compress pour convertir en JPEG
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        format: CompressFormat.jpeg,
        quality: 90,
      );
      return result;
    } catch (e) {
      // Si la conversion échoue, retourner les bytes originaux
      // (LibreOffice affichera une erreur, mais c'est mieux que de planter)
      return imageBytes;
    }
  }
  
  /// Génère un nom de fichier unique pour l'archive ODP
  /// 
  /// Utilise le pageIndex et mediaIndex, avec l'extension appropriée
  static String generateImagePath(int pageIndex, int mediaIndex, String originalFilePath) {
    final (extension, _) = getImageFormatInfo(originalFilePath);
    return 'Pictures/image_$pageIndex-$mediaIndex$extension';
  }
}
