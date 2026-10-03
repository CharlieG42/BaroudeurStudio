import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/jour_trek.dart';
import '../models/media.dart';
import '../models/trek.dart';

/// Import/export d'un carnet de trek au format .bwzt : une archive ZIP
/// (structure JSON + medias + traces GPX) permettant de transferer un
/// trek complet d'un appareil a un autre sans dependre d'un service
/// en ligne. Techniquement, c'est une archive ZIP standard, comme pour
/// les voyages du Trip Planner.
///
/// Contenu de l'archive :
///   trek.json     - metadonnees du trek, des jours et des medias
///   medias/...    - copie des fichiers medias des jours
///   gpx/...       - copie des traces GPX des jours
///
/// Dans trek.json, chaque jour est repere par un index local
/// (0, 1, 2...) plutot que par son id de base de donnees (qui n'a de
/// sens que sur l'appareil d'origine) : les medias y font reference
/// par cet index. A l'import, de nouveaux id sont attribues par la
/// base de donnees locale.
class TrekExportService {
  static const String formatIdentifiant = 'baroudeurstudio.trek.export';
  static const int formatVersion = 1;

  static const _uuid = Uuid();

  /// Genere le fichier .bwzt pour le trek donne, dans le dossier
  /// temporaire de l'app, et retourne ce fichier (a partager/enregistrer
  /// par l'appelant).
  Future<File> exporterTrek(Trek trek) async {
    if (trek.id == null) {
      throw StateError('Le trek doit etre enregistre avant export.');
    }
    final db = DatabaseHelper.instance;
    final jours = await db.getJoursForTrek(trek.id!);

    final archive = Archive();
    final joursJson = <Map<String, dynamic>>[];

    for (var i = 0; i < jours.length; i++) {
      final jour = jours[i];
      final medias =
          jour.id != null ? await db.getMediasForJour(jour.id!) : <Media>[];
      final mediasJson = <Map<String, dynamic>>[];

      for (var m = 0; m < medias.length; m++) {
        final media = medias[m];
        final fichier = File(media.cheminFichier);
        if (!await fichier.exists()) {
          continue; // fichier local manquant : on saute plutot que d'echouer tout l'export.
        }
        final bytes = await fichier.readAsBytes();
        final nomArchive = 'medias/j${i}_m$m'
            '_${_nettoyerNomFichier(media.nomOriginal)}';
        archive.addFile(ArchiveFile(nomArchive, bytes.length, bytes));
        mediasJson.add({
          'type': media.type.value,
          'nomOriginal': media.nomOriginal,
          'legende': media.legende,
          'dateAjout': media.dateAjout,
          'estCouverture': media.estCouverture,
          'cheminArchive': nomArchive,
        });
      }

      String? gpxNomArchive;
      if (jour.cheminGpx != null) {
        final gpxFichier = File(jour.cheminGpx!);
        if (await gpxFichier.exists()) {
          final bytes = await gpxFichier.readAsBytes();
          gpxNomArchive = 'gpx/j${i}.gpx';
          archive.addFile(ArchiveFile(gpxNomArchive, bytes.length, bytes));
        }
      }

      joursJson.add({
        'index': i,
        'numeroJour': jour.numeroJour,
        'date': jour.date,
        'lieuDepart': jour.lieuDepart,
        'lieuArrivee': jour.lieuArrivee,
        'distanceKm': jour.distanceKm,
        'denivelePositifM': jour.denivelePositifM,
        'deniveleNegatifM': jour.deniveleNegatifM,
        'meteo': jour.meteo,
        'resume': jour.resume,
        'emotions': jour.emotions,
        'difficultes': jour.difficultes,
        'decouvertes': jour.decouvertes,
        'notesVocalesTranscription': jour.notesVocalesTranscription,
        'texteGenereIA': jour.texteGenereIA,
        'gpxCheminArchive': gpxNomArchive,
        'medias': mediasJson,
      });
    }

    final contenu = {
      'format': formatIdentifiant,
      'version': formatVersion,
      'exporteLe': DateTime.now().toIso8601String(),
      'trek': {
        'titre': trek.titre,
        'dateDebut': trek.dateDebut,
        'dateFin': trek.dateFin,
        'region': trek.region,
        'pays': trek.pays,
        'distanceKm': trek.distanceKm,
        'denivelePositifM': trek.denivelePositifM,
        'modeVoyage': trek.modeVoyage,
        'compagnons': trek.compagnons,
        'preambule': trek.preambule,
      },
      'jours': joursJson,
    };

    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(contenu),
    );
    archive.addFile(ArchiveFile('trek.json', jsonBytes.length, jsonBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError("Echec de la creation de l'archive .bwzt.");
    }

    final tempDir = await getTemporaryDirectory();
    final nomFichier = '${_nettoyerNomFichier(trek.titre)}.bwzt';
    final fichierExport = File(p.join(tempDir.path, nomFichier));
    await fichierExport.writeAsBytes(zipBytes);
    return fichierExport;
  }

  /// Importe un fichier .bwzt : cree un nouveau trek (avec ses jours,
  /// medias et traces GPX) dans la base de donnees locale, et retourne
  /// l'id de ce nouveau trek. Leve une [FormatException] si le fichier
  /// n'est pas un export .bwzt valide.
  Future<int> importerTrek(String cheminFichier) async {
    final bytes = await File(cheminFichier).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        "Ce fichier ne semble pas etre une archive .bwzt valide.",
      );
    }

    final trekJsonFile = archive.files.firstWhere(
      (f) => f.isFile && f.name == 'trek.json',
      orElse: () => throw const FormatException(
        "Fichier invalide : trek.json introuvable dans l'archive.",
      ),
    );
    final contenu =
        jsonDecode(utf8.decode(trekJsonFile.content as List<int>))
            as Map<String, dynamic>;

    if (contenu['format'] != formatIdentifiant) {
      throw const FormatException(
        'Ce fichier ne semble pas etre un export de trek BaroudeurStudio.',
      );
    }

    final db = DatabaseHelper.instance;
    final trekData = contenu['trek'] as Map<String, dynamic>;
    final trekId = await db.insertTrek(Trek(
      titre: trekData['titre'] as String,
      dateDebut: trekData['dateDebut'] as String,
      dateFin: trekData['dateFin'] as String,
      region: trekData['region'] as String? ?? '',
      pays: trekData['pays'] as String? ?? '',
      distanceKm: (trekData['distanceKm'] as num?)?.toDouble(),
      denivelePositifM: trekData['denivelePositifM'] as int?,
      modeVoyage: trekData['modeVoyage'] as String? ?? '',
      compagnons: trekData['compagnons'] as String? ?? '',
      preambule: trekData['preambule'] as String? ?? '',
    ));

    final joursData =
        (contenu['jours'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    joursData.sort(
      (a, b) => (a['index'] as int).compareTo(b['index'] as int),
    );

    for (final jourData in joursData) {
      final jour = JourTrek(
        trekId: trekId,
        numeroJour: jourData['numeroJour'] as int? ?? 1,
        date: jourData['date'] as String,
        lieuDepart: jourData['lieuDepart'] as String? ?? '',
        lieuArrivee: jourData['lieuArrivee'] as String? ?? '',
        distanceKm: (jourData['distanceKm'] as num?)?.toDouble(),
        denivelePositifM: jourData['denivelePositifM'] as int?,
        deniveleNegatifM: jourData['deniveleNegatifM'] as int?,
        meteo: jourData['meteo'] as String? ?? '',
        resume: jourData['resume'] as String? ?? '',
        emotions: jourData['emotions'] as String? ?? '',
        difficultes: jourData['difficultes'] as String? ?? '',
        decouvertes: jourData['decouvertes'] as String? ?? '',
        notesVocalesTranscription:
            jourData['notesVocalesTranscription'] as String? ?? '',
        texteGenereIA: jourData['texteGenereIA'] as String?,
      ));
      final jourId = await db.insertJour(jour);

      // Le chemin GPX local depend de l'id du jour : on ne peut le
      // definir qu'apres l'insertion du jour en base.
      final gpxArchive = jourData['gpxCheminArchive'] as String?;
      if (gpxArchive != null) {
        final correspondants =
            archive.files.where((f) => f.isFile && f.name == gpxArchive);
        if (correspondants.isNotEmpty) {
          final cheminGpx = await _enregistrerFichierPourJour(
            jourId: jourId,
            nomFichier: 'trace.gpx',
            bytes: correspondants.first.content as List<int>,
          );
          await db.updateJour(jour.copyWith(id: jourId, cheminGpx: cheminGpx));
        }
      }

      final mediasData =
          (jourData['medias'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final mediaData in mediasData) {
        final cheminArchive = mediaData['cheminArchive'] as String;
        final correspondants =
            archive.files.where((f) => f.isFile && f.name == cheminArchive);
        if (correspondants.isEmpty) {
          continue; // media manquant dans l'archive : on ne bloque pas le reste de l'import.
        }
        final bytes = correspondants.first.content as List<int>;
        final nomOriginal = mediaData['nomOriginal'] as String;
        final cheminLocal = await _enregistrerFichierPourJour(
          jourId: jourId,
          nomFichier: nomOriginal,
          bytes: bytes,
        );
        await db.insertMedia(Media(
          jourId: jourId,
          type: MediaTypeExtension.fromValue(
            mediaData['type'] as String? ?? 'photo',
          ),
          cheminFichier: cheminLocal,
          nomOriginal: nomOriginal,
          legende: mediaData['legende'] as String?,
          dateAjout: mediaData['dateAjout'] as String? ??
              DateTime.now().toIso8601String(),
          estCouverture: mediaData['estCouverture'] as bool? ?? false,
        ));
      }
    }

    return trekId;
  }

  /// Ecrit des octets dans le dossier media/jour_[jourId]/ gere par l'app
  /// (meme convention que MediaStorageService), et retourne le chemin
  /// absolu du fichier cree.
  Future<String> _enregistrerFichierPourJour({
    required int jourId,
    required String nomFichier,
    required List<int> bytes,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final jourDir = Directory(p.join(docsDir.path, 'media', 'jour_$jourId'));
    if (!await jourDir.exists()) {
      await jourDir.create(recursive: true);
    }
    final ext = p.extension(nomFichier);
    final destPath = p.join(jourDir.path, '${_uuid.v4()}$ext');
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  String _nettoyerNomFichier(String nom) {
    final sanitized = nom.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]+'), '_');
    return sanitized.isEmpty ? 'trek' : sanitized;
  }
}
