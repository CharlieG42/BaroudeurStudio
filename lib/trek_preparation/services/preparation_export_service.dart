import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/trek_preparation_database.dart';
import '../models/materiel_models.dart';

/// Import/export du module de preparation de trek au format .bwzt :
/// une archive ZIP (structure JSON + photos du materiel) permettant de
/// transferer le catalogue de materiel (familles, sous-familles, marques,
/// materiels) et les listes de preparation d'un appareil a un autre,
/// sur le meme modele que l'import/export des treks.
///
/// Contenu de l'archive :
///   preparation.json - catalogue complet + listes avec leurs lignes
///   photos/...      - copie des photos du materiel
///
/// Dans preparation.json, les entites sont reperees par des index locaux
/// (0, 1, 2...) plutot que par leurs id de base de donnees : materiels,
/// lignes de listes et sous-familles y font reference par ces index.
///
/// A l'import :
///   - familles, sous-familles et marques sont dedupliquees par nom
///     (une entite de meme nom deja presente localement est reutilisee) ;
///   - les materiels reconnus (meme nom ET meme marque localement) sont
///     reutilises, les autres sont crees ;
///   - les listes sont toujours creees en nouvelles.
class PreparationExportService {
  static const String formatIdentifiant =
      'baroudeurstudio.preparation.export';
  static const int formatVersion = 1;

  static const _uuid = Uuid();

  /// Genere le fichier .bwzt pour l'ensemble du module, dans le dossier
  /// temporaire de l'app, et retourne ce fichier.
  Future<File> exporterPreparation() async {
    final db = TrekPreparationDatabase.instance;

    final familles = await db.getFamilles();
    final sousFamilles = await db.getAllSousFamilles();
    final marques = await db.getMarques();
    final materiels = await db.getMateriels();
    final listes = await db.getListes();

    final archive = Archive();

    final famillesJson = <Map<String, dynamic>>[];
    final indexParFamilleId = <int, int>{};
    for (var i = 0; i < familles.length; i++) {
      indexParFamilleId[familles[i].id!] = i;
      famillesJson.add({'index': i, 'nom': familles[i].nom});
    }

    final sousFamillesJson = <Map<String, dynamic>>[];
    final indexParSousFamilleId = <int, int>{};
    for (var i = 0; i < sousFamilles.length; i++) {
      indexParSousFamilleId[sousFamilles[i].id!] = i;
      sousFamillesJson.add({
        'index': i,
        'familleIndex': indexParFamilleId[sousFamilles[i].familleId],
        'nom': sousFamilles[i].nom,
      });
    }

    final marquesJson = <Map<String, dynamic>>[];
    final indexParMarqueId = <int, int>{};
    for (var i = 0; i < marques.length; i++) {
      indexParMarqueId[marques[i].id!] = i;
      marquesJson.add({'index': i, 'nom': marques[i].nom});
    }

    final materielsJson = <Map<String, dynamic>>[];
    final indexParMaterielId = <int, int>{};
    for (var i = 0; i < materiels.length; i++) {
      final materiel = materiels[i];
      indexParMaterielId[materiel.id!] = i;

      String? photoCheminArchive;
      if (materiel.photoPath.isNotEmpty) {
        final photoFile = File(materiel.photoPath);
        if (await photoFile.exists()) {
          final bytes = await photoFile.readAsBytes();
          photoCheminArchive = 'photos/m$i'
              '_${_nettoyerNomFichier(materiel.photoPath)}'
              '${p.extension(materiel.photoPath)}';
          archive.addFile(
            ArchiveFile(photoCheminArchive, bytes.length, bytes),
          );
        }
      }

      materielsJson.add({
        'index': i,
        'nom': materiel.nom,
        'marqueIndex': indexParMarqueId[materiel.marqueId],
        'description': materiel.description,
        'poidsGrammes': materiel.poidsGrammes,
        'familleIndex': indexParFamilleId[materiel.familleId],
        'sousFamilleIndex': indexParSousFamilleId[materiel.sousFamilleId],
        'photoCheminArchive': photoCheminArchive,
      });
    }

    final listesJson = <Map<String, dynamic>>[];
    for (final liste in listes) {
      if (liste.id == null) continue;
      final lignes = await db.getLignesDetaillees(liste.id!);
      final lignesJson = <Map<String, dynamic>>[];
      for (final ligne in lignes) {
        final index = indexParMaterielId[ligne.materiel.id];
        if (index == null) continue;
        lignesJson.add({
          'materielIndex': index,
          'quantite': ligne.ligne.quantite,
          'pris': ligne.ligne.pris,
        });
      }
      listesJson.add({
        'nom': liste.nom,
        'dateTrek': liste.dateTrek,
        'notes': liste.notes,
        'lignes': lignesJson,
      });
    }

    final contenu = {
      'format': formatIdentifiant,
      'version': formatVersion,
      'exporteLe': DateTime.now().toIso8601String(),
      'familles': famillesJson,
      'sousFamilles': sousFamillesJson,
      'marques': marquesJson,
      'materiels': materielsJson,
      'listes': listesJson,
    };

    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(contenu),
    );
    archive.addFile(ArchiveFile('preparation.json', jsonBytes.length, jsonBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError("Echec de la creation de l'archive .bwzt.");
    }

    final tempDir = await getTemporaryDirectory();
    final fichierExport = File(p.join(tempDir.path, 'preparation_trek.bwzt'));
    await fichierExport.writeAsBytes(zipBytes);
    return fichierExport;
  }

  /// Importe un fichier .bwzt : integre le catalogue (familles,
  /// sous-familles, marques, materiels, photos) et cree les listes de
  /// preparation contenues dans l'archive. Retourne le nombre de listes
  /// importees. Leve une [FormatException] si le fichier n'est pas un
  /// export valide.
  Future<int> importerPreparation(String cheminFichier) async {
    final bytes = await File(cheminFichier).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        "Ce fichier ne semble pas etre une archive .bwzt valide.",
      );
    }

    final jsonFile = archive.files.firstWhere(
      (f) => f.isFile && f.name == 'preparation.json',
      orElse: () => throw const FormatException(
        "Fichier invalide : preparation.json introuvable dans l'archive.",
      ),
    );
    final contenu =
        jsonDecode(utf8.decode(jsonFile.content as List<int>))
            as Map<String, dynamic>;

    if (contenu['format'] != formatIdentifiant) {
      throw const FormatException(
        'Ce fichier ne semble pas etre un export de preparation '
        'BaroudeurStudio.',
      );
    }

    final db = TrekPreparationDatabase.instance;

    // Familles : dedupliquees par nom.
    final famillesData =
        (contenu['familles'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final idParFamilleIndex = <int, int>{};
    final famillesLocales = await db.getFamilles();
    for (final familleData in famillesData) {
      final index = familleData['index'] as int;
      final nom = familleData['nom'] as String;
      final existante = famillesLocales.where((f) => f.nom == nom).firstOrNull;
      if (existante != null) {
        idParFamilleIndex[index] = existante.id!;
      } else {
        idParFamilleIndex[index] =
            await db.insertFamille(Famille(nom: nom));
      }
    }

    // Marques : dedupliquees par nom.
    final marquesData =
        (contenu['marques'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final idParMarqueIndex = <int, int>{};
    final marquesLocales = await db.getMarques();
    for (final marqueData in marquesData) {
      final index = marqueData['index'] as int;
      final nom = marqueData['nom'] as String;
      final existante = marquesLocales.where((m) => m.nom == nom).firstOrNull;
      if (existante != null) {
        idParMarqueIndex[index] = existante.id!;
      } else {
        idParMarqueIndex[index] = await db.insertMarque(Marque(nom: nom));
      }
    }

    // Sous-familles : dedupliquees par (nom, famille locale).
    final sousFamillesData =
        (contenu['sousFamilles'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    final idParSousFamilleIndex = <int, int>{};
    for (final sfData in sousFamillesData) {
      final index = sfData['index'] as int;
      final nom = sfData['nom'] as String;
      final familleId = idParFamilleIndex[sfData['familleIndex'] as int];
      if (familleId == null) continue;
      final locales = await db.getSousFamillesForFamille(familleId);
      final existante = locales.where((sf) => sf.nom == nom).firstOrNull;
      if (existante != null) {
        idParSousFamilleIndex[index] = existante.id!;
      } else {
        idParSousFamilleIndex[index] = await db.insertSousFamille(
          SousFamille(familleId: familleId, nom: nom),
        );
      }
    }

    // Materiels : reutilises si un materiel local a le meme nom et la
    // meme marque, crees sinon. Les photos sont recopiees dans le
    // dossier gere par l'app.
    final materielsData =
        (contenu['materiels'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    final idParMaterielIndex = <int, int>{};
    final materielsLocaux = await db.getMateriels();
    for (final mData in materielsData) {
      final index = mData['index'] as int;
      final nom = mData['nom'] as String;
      final marqueId = idParMarqueIndex[mData['marqueIndex'] as int];
      if (marqueId == null) continue;
      final familleId = idParFamilleIndex[mData['familleIndex'] as int];
      if (familleId == null) continue;
      final sousFamilleId =
          idParSousFamilleIndex[mData['sousFamilleIndex'] as int? ?? -1];

      String? photoPath;
      final photoCheminArchive = mData['photoCheminArchive'] as String?;
      if (photoCheminArchive != null) {
        final correspondants = archive.files
            .where((f) => f.isFile && f.name == photoCheminArchive);
        if (correspondants.isNotEmpty) {
          photoPath = await _enregistrerPhoto(
            bytes: correspondants.first.content as List<int>,
            extension: p.extension(photoCheminArchive),
          );
        }
      }

      final existant = materielsLocaux
          .where((m) => m.nom == nom && m.marqueId == marqueId)
          .firstOrNull;
      if (existant != null) {
        idParMaterielIndex[index] = existant.id!;
      } else {
        idParMaterielIndex[index] = await db.insertMateriel(Materiel(
          nom: nom,
          marqueId: marqueId,
          description: mData['description'] as String? ?? '',
          poidsGrammes: (mData['poidsGrammes'] as num?)?.toDouble() ?? 0,
          familleId: familleId,
          sousFamilleId: sousFamilleId,
          photoPath: photoPath ?? '',
        ));
      }
    }

    // Listes : toujours creees en nouvelles, lignes referencees par
    // l'index du materiel.
    final listesData =
        (contenu['listes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    var nbListesImportees = 0;
    for (final lData in listesData) {
      final listeId = await db.insertListe(ListeMateriel(
        nom: lData['nom'] as String,
        dateTrek: lData['dateTrek'] as String? ?? '',
        notes: lData['notes'] as String? ?? '',
      ));
      nbListesImportees++;
      final lignesData =
          (lData['lignes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final ligneData in lignesData) {
        final materielId =
            idParMaterielIndex[ligneData['materielIndex'] as int];
        if (materielId == null) continue;
        await db.insertLigne(LigneListe(
          listeId: listeId,
          materielId: materielId,
          quantite: ligneData['quantite'] as int? ?? 1,
          pris: ligneData['pris'] as bool? ?? false,
        ));
      }
    }

    return nbListesImportees;
  }

  /// Ecrit des octets dans le dossier trek_preparation_photos gere par
  /// l'app (meme convention que MaterielPhotoStorageService) et
  /// retourne le chemin absolu du fichier cree.
  Future<String> _enregistrerPhoto({
    required List<int> bytes,
    required String extension,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'trek_preparation_photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final destPath = p.join(dir.path, '${_uuid.v4()}$extension');
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  String _nettoyerNomFichier(String chemin) {
    final nom = p.extension(chemin).isNotEmpty
        ? p.basenameWithoutExtension(chemin)
        : p.basename(chemin);
    final sanitized =
        nom.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]+'), '_');
    return sanitized.isEmpty ? 'photo' : sanitized;
  }
}
