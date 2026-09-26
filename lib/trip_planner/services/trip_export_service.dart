import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/trip_planner_database.dart';
import '../models/document_etape.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../models/voyage.dart';
import 'document_storage_service.dart';

/// Import/export d'un voyage planifie au format .bwzt : une archive ZIP
/// (structure JSON + documents attaches) permettant de transferer un
/// voyage planifie d'un appareil a un autre sans dependre d'un service
/// en ligne. Le nom "bwzt" fait reference a BaroudeurStudio / Wildzimut ;
/// techniquement, c'est une archive ZIP standard (renommer en .zip et
/// l'ouvrir avec n'importe quel outil le confirme).
///
/// Contenu de l'archive :
///   voyage.json     - metadonnees du voyage, des etapes et des trajets
///   documents/...   - copie des fichiers attaches aux etapes
///
/// Dans voyage.json, chaque etape est reperee par un index local
/// (0, 1, 2...) plutot que par son id de base de donnees (qui n'a de
/// sens que sur l'appareil d'origine) : trajets et documents y font
/// reference par cet index. A l'import, de nouveaux id sont attribues
/// par la base de donnees locale.
class TripExportService {
  static const String formatIdentifiant =
      'baroudeurstudio.tripplanner.export';
  static const int formatVersion = 1;

  final DocumentStorageService _documentStorage = DocumentStorageService();

  /// Genere le fichier .bwzt pour le voyage donne, dans le dossier
  /// temporaire de l'app, et retourne ce fichier (a partager/enregistrer
  /// par l'appelant).
  Future<File> exporterVoyage(Voyage voyage) async {
    if (voyage.id == null) {
      throw StateError('Le voyage doit etre enregistre avant export.');
    }

    final db = TripPlannerDatabase.instance;
    final etapes = await db.getEtapesForVoyage(voyage.id!);
    final trajets = await db.getTrajetsForVoyage(voyage.id!);

    // Index local par id d'etape, pour construire des references
    // portables (independantes des id de la base de donnees).
    final indexParEtapeId = <int, int>{};
    for (var i = 0; i < etapes.length; i++) {
      if (etapes[i].id != null) indexParEtapeId[etapes[i].id!] = i;
    }

    final archive = Archive();
    final etapesJson = <Map<String, dynamic>>[];

    for (var i = 0; i < etapes.length; i++) {
      final etape = etapes[i];
      final documents = etape.id != null
          ? await db.getDocumentsForEtape(etape.id!)
          : <DocumentEtape>[];

      final documentsJson = <Map<String, dynamic>>[];
      for (var d = 0; d < documents.length; d++) {
        final document = documents[d];
        final fichier = File(document.cheminFichier);
        if (!await fichier.exists()) {
          continue; // fichier local manquant : on saute plutot que d'echouer tout l'export.
        }
        final bytes = await fichier.readAsBytes();
        final cheminArchive = 'documents/e${i}_d$d'
            '_${_nettoyerNomFichier(document.nomOriginal)}';
        archive.addFile(ArchiveFile(cheminArchive, bytes.length, bytes));
        documentsJson.add({
          'nomOriginal': document.nomOriginal,
          'typeMime': document.typeMime,
          'tailleOctets': document.tailleOctets,
          'dateAjout': document.dateAjout,
          'cheminArchive': cheminArchive,
        });
      }

      etapesJson.add({
        'index': i,
        'ordre': etape.ordre,
        'nom': etape.nom,
        'latitude': etape.latitude,
        'longitude': etape.longitude,
        'date': etape.date,
        'type': etape.type.name,
        'notes': etape.notes,
        'dureeVisiteMinutes': etape.dureeVisiteMinutes,
        'heureArrivee': etape.heureArrivee,
        'dateDepart': etape.dateDepart,
        'heureDepart': etape.heureDepart,
        'documents': documentsJson,
      });
    }

    final trajetsJson = <Map<String, dynamic>>[];
    for (final trajet in trajets) {
      final indexDepart = indexParEtapeId[trajet.etapeDepartId];
      final indexArrivee = indexParEtapeId[trajet.etapeArriveeId];
      if (indexDepart == null || indexArrivee == null) {
        continue; // paire orpheline (ne devrait pas arriver) : on l'ignore.
      }
      trajetsJson.add({
        'etapeIndexDepart': indexDepart,
        'etapeIndexArrivee': indexArrivee,
        'mode': trajet.mode.name,
        'distanceKm': trajet.distanceKm,
        'dureeMinutes': trajet.dureeMinutes,
        'geometrieJson': trajet.geometrieJson,
        'transporteur': trajet.transporteur,
        'lieuDepart': trajet.lieuDepart,
        'lieuArrivee': trajet.lieuArrivee,
        'heureDepart': trajet.heureDepart,
        'heureArrivee': trajet.heureArrivee,
        'notes': trajet.notes,
      });
    }

    final contenu = {
      'format': formatIdentifiant,
      'version': formatVersion,
      'exporteLe': DateTime.now().toIso8601String(),
      'voyage': {
        'titre': voyage.titre,
        'dateDebut': voyage.dateDebut,
        'dateFin': voyage.dateFin,
        'notes': voyage.notes,
      },
      'etapes': etapesJson,
      'trajets': trajetsJson,
    };

    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(contenu),
    );
    archive.addFile(ArchiveFile('voyage.json', jsonBytes.length, jsonBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('Echec de la creation de l\'archive .bwzt.');
    }

    final tempDir = await getTemporaryDirectory();
    final nomFichier = '${_nettoyerNomFichier(voyage.titre)}.bwzt';
    final fichierExport = File(p.join(tempDir.path, nomFichier));
    await fichierExport.writeAsBytes(zipBytes);

    return fichierExport;
  }

  /// Importe un fichier .bwzt : cree un nouveau voyage (avec ses
  /// etapes, trajets et documents) dans la base de donnees locale, et
  /// retourne l'id de ce nouveau voyage. Leve une [FormatException] si
  /// le fichier n'est pas un export .bwzt valide.
  Future<int> importerVoyage(String cheminFichier) async {
    final bytes = await File(cheminFichier).readAsBytes();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        'Ce fichier ne semble pas etre une archive .bwzt valide.',
      );
    }

    final voyageJsonFile = archive.files.firstWhere(
      (f) => f.isFile && f.name == 'voyage.json',
      orElse: () => throw const FormatException(
        'Fichier invalide : voyage.json introuvable dans l\'archive.',
      ),
    );
    final contenu =
        jsonDecode(utf8.decode(voyageJsonFile.content as List<int>))
            as Map<String, dynamic>;

    if (contenu['format'] != formatIdentifiant) {
      throw const FormatException(
        'Ce fichier ne semble pas etre un export de voyage BaroudeurStudio.',
      );
    }

    final db = TripPlannerDatabase.instance;
    final voyageData = contenu['voyage'] as Map<String, dynamic>;
    final voyageId = await db.insertVoyage(Voyage(
      titre: voyageData['titre'] as String,
      dateDebut: voyageData['dateDebut'] as String,
      dateFin: voyageData['dateFin'] as String,
      notes: voyageData['notes'] as String? ?? '',
    ));

    final etapesData =
        (contenu['etapes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    etapesData.sort(
      (a, b) => (a['index'] as int).compareTo(b['index'] as int),
    );

    final etapeIdParIndex = <int, int>{};

    for (final etapeData in etapesData) {
      final index = etapeData['index'] as int;
      final etapeId = await db.insertEtape(Etape(
        voyageId: voyageId,
        ordre: etapeData['ordre'] as int,
        nom: etapeData['nom'] as String,
        latitude: (etapeData['latitude'] as num).toDouble(),
        longitude: (etapeData['longitude'] as num).toDouble(),
        date: etapeData['date'] as String,
        type: typeEtapeFromString(etapeData['type'] as String? ?? 'visite'),
        notes: etapeData['notes'] as String? ?? '',
        dureeVisiteMinutes: etapeData['dureeVisiteMinutes'] as int?,
        heureArrivee: etapeData['heureArrivee'] as String?,
        dateDepart: etapeData['dateDepart'] as String?,
        heureDepart: etapeData['heureDepart'] as String?,
      ));
      etapeIdParIndex[index] = etapeId;

      final documentsData =
          (etapeData['documents'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
      for (final documentData in documentsData) {
        final cheminArchive = documentData['cheminArchive'] as String;
        final correspondants =
            archive.files.where((f) => f.isFile && f.name == cheminArchive);
        if (correspondants.isEmpty) {
          continue; // document manquant dans l'archive : on ne bloque pas le reste de l'import.
        }
        final docBytes = correspondants.first.content as List<int>;
        final nomOriginal = documentData['nomOriginal'] as String;

        final cheminLocal = await _documentStorage.enregistrerBytesPourEtape(
          etapeId: etapeId,
          nomFichier: nomOriginal,
          bytes: docBytes,
        );

        await db.insertDocument(DocumentEtape(
          etapeId: etapeId,
          nomOriginal: nomOriginal,
          cheminFichier: cheminLocal,
          typeMime: documentData['typeMime'] as String?,
          tailleOctets:
              documentData['tailleOctets'] as int? ?? docBytes.length,
          dateAjout: documentData['dateAjout'] as String? ??
              DateTime.now().toIso8601String(),
        ));
      }
    }

    final trajetsData =
        (contenu['trajets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final trajetData in trajetsData) {
      final indexDepart = trajetData['etapeIndexDepart'] as int;
      final indexArrivee = trajetData['etapeIndexArrivee'] as int;
      final etapeDepartId = etapeIdParIndex[indexDepart];
      final etapeArriveeId = etapeIdParIndex[indexArrivee];
      if (etapeDepartId == null || etapeArriveeId == null) continue;

      await db.upsertTrajet(Trajet(
        voyageId: voyageId,
        etapeDepartId: etapeDepartId,
        etapeArriveeId: etapeArriveeId,
        mode: modeTransportFromString(
            trajetData['mode'] as String? ?? 'voiture'),
        distanceKm: (trajetData['distanceKm'] as num?)?.toDouble() ?? 0,
        dureeMinutes: trajetData['dureeMinutes'] as int? ?? 0,
        geometrieJson: trajetData['geometrieJson'] as String? ?? '[]',
        transporteur: trajetData['transporteur'] as String?,
        lieuDepart: trajetData['lieuDepart'] as String?,
        lieuArrivee: trajetData['lieuArrivee'] as String?,
        heureDepart: trajetData['heureDepart'] as String?,
        heureArrivee: trajetData['heureArrivee'] as String?,
        notes: trajetData['notes'] as String? ?? '',
      ));
    }

    return voyageId;
  }

  String _nettoyerNomFichier(String nom) {
    final sanitized = nom.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]+'), '_');
    return sanitized.isEmpty ? 'voyage' : sanitized;
  }
}
