import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart';

import '../../trek_preparation/services/preparation_export_service.dart';
import '../../trip_planner/services/trip_export_service.dart';
import '../trek_export_service.dart';
import 'drive_backup_service.dart';
import 'drive_connection_service.dart';

/// Entree de sauvegarde Drive listee pour la restauration.
class EntreeBackupDrive {
  final String id;
  final String nom;
  final DateTime? modifieLe;

  const EntreeBackupDrive({
    required this.id,
    required this.nom,
    this.modifieLe,
  });
}

/// Resultat d'une restauration.
class ResultatRestauration {
  final bool ok;
  final String message;

  const ResultatRestauration({required this.ok, required this.message});
}

/// Service de restauration depuis Google Drive.
///
/// Liste les fichiers .bwzt du dossier BaroudeurStudio/<categorie>/,
/// les telecharge dans le dossier temporaire, puis route chaque archive
/// vers l'importeur correspondant grace a l'identifiant de format du
/// manifeste embarque (trek / voyage / preparation).
class DriveRestoreService {
  static final DriveRestoreService _instance =
      DriveRestoreService._internal();
  factory DriveRestoreService() => _instance;
  DriveRestoreService._internal();

  static const String _dossierRacine = 'BaroudeurStudio';

  final DriveConnectionService _connexion = DriveConnectionService();
  final TrekExportService _trekImport = TrekExportService();
  final TripExportService _voyageImport = TripExportService();
  final PreparationExportService _prepaImport = PreparationExportService();

  /// Liste les sauvegardes .bwzt d'une categorie.
  /// Renvoie une liste vide si non connecte ou dossier absent.
  Future<List<EntreeBackupDrive>> lister(CategorieBackup categorie) async {
    try {
      final api = await _connexion.clientDrive();
      final racine = await _trouverDossier(api, _dossierRacine);
      if (racine == null) return const [];
      final dossier =
          await _trouverDossier(api, categorie.nomDossier, parentId: racine.id);
      if (dossier == null) return const [];

      final liste = await api.files.list(
        q: "'${dossier.id}' in parents and trashed = false",
        $fields: 'files(id,name,modifiedTime)',
        orderBy: 'name',
      );
      return (liste.files ?? [])
          .map((f) => EntreeBackupDrive(
                id: f.id!,
                nom: f.name ?? 'sans-nom',
                modifieLe: f.modifiedTime,
              ))
          .toList();
    } catch (e) {
      debugPrint('Erreur listing backup Drive : $e');
      return const [];
    }
  }

  /// Telecharge une sauvegarde et l'importe via le bon service.
  Future<ResultatRestauration> restaurer(EntreeBackupDrive entree) async {
    try {
      final api = await _connexion.clientDrive();

      // Telechargement dans le dossier temporaire.
      final tempDir = await getTemporaryDirectory();
      final cheminLocal = '${tempDir.path}/${entree.nom}';
      final flux = await api.files
          .get(entree.id, downloadOptions: drive.DownloadOptions.media);
      if (flux is! drive.Media) {
        return const ResultatRestauration(
            ok: false, message: 'Telechargement impossible.');
      }
      final fichierLocal = File(cheminLocal);
      final sortie = fichierLocal.openWrite();
      await flux.stream.pipe(sortie);

      // Routage par l'identifiant de format du manifeste.
      final format = _lireFormat(await fichierLocal.readAsBytes());
      switch (format) {
        case TrekExportService.formatIdentifiant:
          final id = await _trekImport.importerTrek(cheminLocal);
          return ResultatRestauration(
              ok: true, message: 'Trek importe (id $id).');
        case TripExportService.formatIdentifiant:
          final id = await _voyageImport.importerVoyage(cheminLocal);
          return ResultatRestauration(
              ok: true, message: 'Voyage importe (id $id).');
        case PreparationExportService.formatIdentifiant:
          final n = await _prepaImport.importerPreparation(cheminLocal);
          return ResultatRestauration(
              ok: true, message: 'Preparation importee ($n elements).');
        default:
          return ResultatRestauration(
              ok: false,
              message: 'Format inconnu : ${format ?? 'manifeste illisible'}');
      }
    } catch (e) {
      return ResultatRestauration(
          ok: false, message: 'Echec de la restauration : $e');
    }
  }

  /// Extrait l'identifiant de format du premier fichier .json de
  /// l'archive (le manifeste), sans dezipper sur disque.
  String? _lireFormat(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final fichier in archive) {
        if (fichier.name.endsWith('.json')) {
          final contenu = utf8.decode(fichier.content as List<int>);
          final map = jsonDecode(contenu);
          if (map is Map<String, dynamic>) {
            return map['format'] as String?;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<drive.File?> _trouverDossier(drive.DriveApi api, String nom,
      {String? parentId}) async {
    final clauseParent = parentId != null ? "'$parentId' in parents and " : '';
    final liste = await api.files.list(
      q: "${clauseParent}name = '$nom' and mimeType = "
          "'application/vnd.google-apps.folder' and trashed = false",
      $fields: 'files(id,name)',
      pageSize: 1,
    );
    return liste.files?.isEmpty == true ? null : liste.files!.first;
  }
}
