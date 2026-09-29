import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copie les photos du materiel dans un dossier dedie de l'app :
/// trek_prep_photos/[uuid].[ext]
class MaterielPhotoStorage {
  static const _uuid = Uuid();

  Future<String> copyPhoto(String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'trek_prep_photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = p.extension(sourcePath);
    final destPath = p.join(dir.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Supprime physiquement une photo (best-effort).
  Future<void> deletePhoto(String? chemin) async {
    if (chemin == null || chemin.isEmpty) return;
    try {
      final file = File(chemin);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best-effort
    }
  }
}
