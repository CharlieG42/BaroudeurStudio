import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Gere la copie physique des documents attaches a une etape, dans un
/// dossier dedie de l'application (sous-dossier "trip_planner_documents"
/// du dossier Documents), organise par etape :
/// trip_planner_documents/etape_[etapeId]/[uuid].[ext]
///
/// Meme logique que MediaStorageService (module carnet de trek), mais
/// dans son propre dossier pour rester independant.
class DocumentStorageService {
  static const _uuid = Uuid();

  Future<Directory> _rootDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'trip_planner_documents'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Ecrit des octets directement dans le dossier gere par l'app, pour
  /// une etape donnee (utilise a l'import : les documents proviennent
  /// d'une archive, pas d'un fichier deja present sur le disque), et
  /// retourne le chemin absolu du fichier cree.
  Future<String> enregistrerBytesPourEtape({
    required int etapeId,
    required String nomFichier,
    required List<int> bytes,
  }) async {
    final root = await _rootDir();
    final etapeDir = Directory(p.join(root.path, 'etape_$etapeId'));
    if (!await etapeDir.exists()) {
      await etapeDir.create(recursive: true);
    }

    final ext = p.extension(nomFichier);
    final newFileName = '${_uuid.v4()}$ext';
    final destPath = p.join(etapeDir.path, newFileName);

    await File(destPath).writeAsBytes(bytes);

    return destPath;
  }

  /// Copie un fichier source vers le dossier gere par l'app, pour une
  /// etape donnee, et retourne le chemin absolu du fichier copie.
  Future<String> copierFichierPourEtape({
    required int etapeId,
    required String sourcePath,
  }) async {
    final root = await _rootDir();
    final etapeDir = Directory(p.join(root.path, 'etape_$etapeId'));
    if (!await etapeDir.exists()) {
      await etapeDir.create(recursive: true);
    }

    final ext = p.extension(sourcePath); // inclut le point, ex: ".pdf"
    final newFileName = '${_uuid.v4()}$ext';
    final destPath = p.join(etapeDir.path, newFileName);

    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);

    return destPath;
  }

  /// Supprime physiquement le fichier du disque (best-effort : si la
  /// suppression physique echoue, on ne bloque pas la suppression en
  /// base, deja effectuee par l'appelant).
  Future<void> supprimerFichier(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<int> tailleFichierOctets(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Formate une taille en octets en texte lisible (ex: "1,2 Mo").
  static String formaterTaille(int octets) {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) {
      return '${(octets / 1024).toStringAsFixed(0)} Ko';
    }
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
