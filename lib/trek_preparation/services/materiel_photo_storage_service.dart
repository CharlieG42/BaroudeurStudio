import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Copie les photos du materiel dans un dossier dedie de l'application
/// (sous-dossier "trek_preparation_photos" du dossier Documents), sur
/// le meme modele que DocumentStorageService (module planification de
/// voyage), pour rester independant des autres modules.
class MaterielPhotoStorageService {
  static const _uuid = Uuid();

  Future<Directory> _rootDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'trek_preparation_photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copie un fichier image source et retourne le chemin absolu de la
  /// copie geree par l'app.
  Future<String> copierPhoto(String sourcePath) async {
    final root = await _rootDir();
    final ext = p.extension(sourcePath);
    final destPath = p.join(root.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Supprime physiquement une photo (best-effort : si la suppression
  /// echoue, on ne bloque pas l'operation en base, deja effectuee).
  Future<void> supprimerPhoto(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
