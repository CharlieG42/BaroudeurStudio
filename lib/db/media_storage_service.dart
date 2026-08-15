import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/media.dart';

/// Gère la copie physique des fichiers médias dans un dossier dédié
/// de l'application (sous-dossier "media" du dossier Documents),
/// organisé par jour : media/jour_[jourId]/[uuid].[ext]
class MediaStorageService {
  static const _uuid = Uuid();

  // Réduction de la plus longue dimension à 1920px : largement suffisant
  // pour de l'impression et pour servir de base pour des illustrations IA.
  static const int _maxDimension = 1920;

  /// Retourne (et crée si besoin) le dossier racine des médias de l'app.
  Future<Directory> _mediaRootDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(docsDir.path, 'media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// Copie un fichier source vers le dossier géré par l'app, pour un jour
  /// donné, et retourne le chemin absolu du fichier copié.
  ///
  /// Si compress est true et que le fichier est une photo, l'image est
  /// redimensionnée/convertie en PNG avant d'être enregistrée. Sinon (ou si
  /// la conversion échoue, ou si le fichier n'est pas une photo), le fichier
  /// original est copié tel quel.
  Future<String> copyFileForJour({
    required int jourId,
    required String sourcePath,
    bool compress = false,
  }) async {
    final mediaRoot = await _mediaRootDir();
    final jourDir = Directory(p.join(mediaRoot.path, 'jour_$jourId'));
    if (!await jourDir.exists()) {
      await jourDir.create(recursive: true);
    }

    final isPhoto = detectType(sourcePath) == MediaType.photo;
    final canCompress = isPhoto && _isCompressibleExt(sourcePath);

    if (compress && canCompress) {
      final compressedPath = await _compressAndSave(
        sourcePath: sourcePath,
        destDir: jourDir.path,
      );
      if (compressedPath != null) {
        return compressedPath;
      }
      // En cas d'échec de compression, on retombe sur la copie classique.
    }

    final ext = p.extension(sourcePath); // inclut le point, ex: ".jpg"
    final newFileName = '${_uuid.v4()}$ext';
    final destPath = p.join(jourDir.path, newFileName);

    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);

    return destPath;
  }

  /// Compresse/convertit une image et l'enregistre en PNG dans [destDir].
  ///
  /// Utilise flutter_image_compress qui supporte nativement le HEIC sur
  /// Android/iOS. Le format de sortie est PNG (lossless) pour éviter tout
  /// problème de compatibilité avec le package `image` (Dart pur) utilisé
  /// lors de l'export ODP.
  ///
  /// Retourne le chemin du fichier converti, ou null en cas d'échec.
  Future<String?> _compressAndSave({
    required String sourcePath,
    required String destDir,
  }) async {
    try {
      final destPath = p.join(destDir, '${_uuid.v4()}.png');

      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        destPath,
        quality: 90,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        keepExif: false,
        format: CompressFormat.png,
      );

      if (result == null) return null;
      return result.path;
    } catch (_) {
      return null;
    }
  }

  bool _isCompressibleExt(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    // Formats gérés par flutter_image_compress sur Android/iOS.
    // HEIC est inclus : flutter_image_compress le convertit nativement en PNG.
    const supported = {'.jpg', '.jpeg', '.png', '.heic', '.webp', '.bmp'};
    return supported.contains(ext);
  }

  /// Retourne la taille d'un fichier en octets (0 si introuvable).
  Future<int> fileSizeBytes(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Détermine le type de média à partir de l'extension du fichier.
  MediaType detectType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    const photoExts = {'.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp'};
    const videoExts = {'.mp4', '.mov', '.avi', '.mkv', '.webm'};
    const audioExts = {'.mp3', '.wav', '.m4a', '.aac', '.ogg'};

    if (photoExts.contains(ext)) return MediaType.photo;
    if (videoExts.contains(ext)) return MediaType.video;
    if (audioExts.contains(ext)) return MediaType.audio;
    return MediaType.photo; // par défaut
  }

  /// Supprime physiquement le fichier média du disque (best-effort).
  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best-effort : si la suppression physique échoue,
      // on ne bloque pas la suppression en base.
    }
  }
}
