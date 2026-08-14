import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/odp/odp_content_filler.dart';

/// Gestion de la persistance des paramètres d'export ODP.
///
/// Les paramètres sont stockés dans un fichier JSON
/// (`odp_export_settings.json`) dans le dossier Documents de l'application.
/// Cela évite d'ajouter une dépendance (shared_preferences, hive, etc.).
class OdpExportSettingsStore {
  static const String _fileName = 'odp_export_settings.json';

  /// Charge les paramètres sauvegardés, ou les valeurs par défaut si aucun
  /// fichier n'existe ou en cas d'erreur.
  static Future<OdpImageSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return OdpImageSettings.defaults;
      }
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return OdpImageSettings(
        minHeightCm: (json['minHeightCm'] as num?)?.toDouble() ??
            OdpImageSettings.defaults.minHeightCm,
        minWidthCm: (json['minWidthCm'] as num?)?.toDouble() ??
            OdpImageSettings.defaults.minWidthCm,
        maxWidthCm: (json['maxWidthCm'] as num?)?.toDouble() ??
            OdpImageSettings.defaults.maxWidthCm,
        maxHeightCm: (json['maxHeightCm'] as num?)?.toDouble() ??
            OdpImageSettings.defaults.maxHeightCm,
      );
    } catch (e) {
      debugPrint('Erreur lors du chargement des paramètres ODP: $e');
      return OdpImageSettings.defaults;
    }
  }

  /// Sauvegarde les paramètres dans le fichier JSON.
  static Future<void> save(OdpImageSettings settings) async {
    try {
      final file = await _settingsFile();
      final json = jsonEncode({
        'minHeightCm': settings.minHeightCm,
        'minWidthCm': settings.minWidthCm,
        'maxWidthCm': settings.maxWidthCm,
        'maxHeightCm': settings.maxHeightCm,
      });
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('Erreur lors de la sauvegarde des paramètres ODP: $e');
    }
  }

  /// Réinitialise les paramètres aux valeurs par défaut.
  static Future<void> reset() async {
    await save(OdpImageSettings.defaults);
  }

  static Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
