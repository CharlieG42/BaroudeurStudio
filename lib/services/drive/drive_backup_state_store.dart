import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persistance de l'etat de sauvegarde Drive : pour chaque objet
/// (trek, voyage, catalogue), la date de la derniere sauvegarde reussie.
///
/// Meme pattern que OdpExportSettingsStore : un fichier JSON dans le
/// dossier Documents, sans dependance supplementaire.
class DriveBackupStateStore {
  static const String _fileName = 'drive_backup_state.json';

  static Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Date de la derniere sauvegarde reussie pour [cle], null si jamais
  /// sauvegarde.
  static Future<DateTime?> derniereSauvegarde(String cle) async {
    try {
      final etat = await _charger();
      final valeur = etat[cle] as String?;
      return valeur != null ? DateTime.tryParse(valeur) : null;
    } catch (e) {
      debugPrint('Erreur lecture etat backup Drive: $e');
      return null;
    }
  }

  /// Enregistre la date de derniere sauvegarde reussie pour [cle].
  static Future<void> enregistrerSucces(String cle) async {
    try {
      final etat = await _charger();
      etat[cle] = DateTime.now().toIso8601String();
      final file = await _stateFile();
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(etat));
    } catch (e) {
      debugPrint('Erreur ecriture etat backup Drive: $e');
    }
  }

  static Future<Map<String, dynamic>> _charger() async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }
}
