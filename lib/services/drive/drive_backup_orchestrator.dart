import 'dart:io';

import 'package:flutter/foundation.dart';

import '../trek_export_service.dart';
import '../../db/database_helper.dart';
import '../../models/trek.dart';
import '../../trip_planner/db/trip_planner_database.dart';
import '../../trip_planner/models/voyage.dart';
import '../../trip_planner/services/trip_export_service.dart';
import '../../trek_preparation/services/preparation_export_service.dart';
import 'drive_backup_service.dart';
import 'drive_backup_state_store.dart';
import 'drive_connection_service.dart';

/// Orchestrateur de la sauvegarde Drive.
///
/// Fait le lien entre les services d'export existants (.bwzt) et le
/// DriveBackupService. Deux modes :
///  - [declencherSiStale] : trigger opportuniste, appelle apres une
///    sauvegarde en base ; ne fait rien si pas connecte ou si la
///    derniere sauvegarde date de moins de 24 h ;
///  - [sauvegarderToutMaintenant] : bouton manuel, force la sauvegarde
///    de tous les objets.
class DriveBackupOrchestrator {
  static final DriveBackupOrchestrator _instance =
      DriveBackupOrchestrator._internal();
  factory DriveBackupOrchestrator() => _instance;
  DriveBackupOrchestrator._internal();

  static const Duration _delaiAntiSpam = Duration(hours: 24);

  final DriveConnectionService _connexion = DriveConnectionService();
  final DriveBackupService _backup = DriveBackupService();
  final TrekExportService _trekExport = TrekExportService();
  final TripExportService _voyageExport = TripExportService();
  final PreparationExportService _prepaExport = PreparationExportService();

  /// Trigger opportuniste : sauvegarde l'objet [cle] si sa derniere
  /// sauvegarde date de plus de 24 h. Silencieux : toute erreur est
  /// avalee, le trigger sera rejoue au prochain appel.
  Future<void> declencherSiStale({
    required String cle,
    required Future<File?> Function() genererBwzt,
    required CategorieBackup categorie,
  }) async {
    try {
      if (_backup.enCours || !_connexion.estConnecte) {
        return;
      }
      final derniere = await DriveBackupStateStore.derniereSauvegarde(cle);
      final stale = derniere == null ||
          DateTime.now().difference(derniere) > _delaiAntiSpam;
      if (!stale) {
        return;
      }
      final bwzt = await genererBwzt();
      if (bwzt == null) {
        return;
      }
      final resultat = await _backup.sauvegarder(
        bwzt,
        categorie: categorie,
        id: cle,
      );
      if (resultat.ok) {
        await DriveBackupStateStore.enregistrerSucces(cle);
      }
    } catch (e) {
      debugPrint('Trigger backup Drive ignore pour $cle : $e');
    }
  }

  /// Sauvegarde de tous les treks, voyages et du catalogue de
  /// preparation. Renvoie le nombre de sauvegardes reussies et la liste
  /// des erreurs pour affichage dans les reglages.
  Future<({int reussis, List<String> erreurs})>
      sauvegarderToutMaintenant() async {
    var reussis = 0;
    final erreurs = <String>[];

    // Carnets de trek.
    final treks = await DatabaseHelper.instance.getTreks();
    for (final Trek trek in treks) {
      if (trek.id == null) continue;
      final cle = 'trek_${trek.id}';
      try {
        final bwzt = await _trekExport.exporterTrek(trek);
        final r = await _backup.sauvegarder(
          bwzt,
          categorie: CategorieBackup.treks,
          id: cle,
        );
        if (r.ok) {
          await DriveBackupStateStore.enregistrerSucces(cle);
          reussis++;
        } else {
          erreurs.add('${trek.titre} : ${r.erreur}');
        }
      } catch (e) {
        erreurs.add('${trek.titre} : $e');
      }
    }

    // Voyages du module de planification.
    try {
      final voyages = await TripPlannerDatabase.instance.getVoyages();
      for (final Voyage voyage in voyages) {
        if (voyage.id == null) continue;
        final cle = 'voyage_${voyage.id}';
        try {
          final bwzt = await _voyageExport.exporterVoyage(voyage);
          final r = await _backup.sauvegarder(
            bwzt,
            categorie: CategorieBackup.voyages,
            id: cle,
          );
          if (r.ok) {
            await DriveBackupStateStore.enregistrerSucces(cle);
            reussis++;
          } else {
            erreurs.add('${voyage.titre} : ${r.erreur}');
          }
        } catch (e) {
          erreurs.add('${voyage.titre} : $e');
        }
      }
    } catch (e) {
      debugPrint('Backup voyages ignore : $e');
    }

    // Catalogue de preparation de trek.
    try {
      final bwzt = await _prepaExport.exporterPreparation();
      final r = await _backup.sauvegarder(
        bwzt,
        categorie: CategorieBackup.preparation,
        id: 'preparation',
      );
      if (r.ok) {
        await DriveBackupStateStore.enregistrerSucces('preparation');
        reussis++;
      } else {
        erreurs.add('Preparation : ${r.erreur}');
      }
    } catch (e) {
      debugPrint('Backup preparation ignore : $e');
    }

    return (reussis: reussis, erreurs: erreurs);
  }
}
