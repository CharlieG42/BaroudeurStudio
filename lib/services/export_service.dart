import 'dart:typed_data';
import 'dart:io';

import '../models/trek.dart';
import 'odp/odp_export_service.dart';
import 'utils/filename_utils.dart';
import 'utils/image_optimizer.dart';

/// Service unifié pour exporter les treks au format ODP
/// 
/// Ce service agit comme une façade pour le service d'export ODP.
class ExportService {
  static final ExportService _instance = ExportService._internal();
  
  factory ExportService() => _instance;
  
  ExportService._internal();

  // Service ODP
  final OdpExportService _odpExportService = OdpExportService();

  // ===========================================================================
  // EXPORT ODP (OpenDocument Presentation)
  // ===========================================================================

  /// Génère un ODP (OpenDocument Presentation) modifiable
  /// Format idéal pour les ajustements manuels, compatible avec LibreOffice
  /// Le document est systématiquement en orientation portrait (21cm x 28cm)
  Future<File> exportTrekToOdp(Trek trek) async {
    return _odpExportService.exportTrekToOdp(trek);
  }

  // ===========================================================================
  // MÉTHODES UTILITAIRES
  // ===========================================================================

  /// Nettoie une chaîne de caractères pour être utilisée comme nom de fichier
  static String sanitizeFilename(String input) {
    return FilenameUtils.sanitizeFilename(input);
  }

  /// Optimise une image avec la qualité de compression spécifiée
  static Uint8List optimizeImage(Uint8List imageBytes, {int? quality}) {
    return ImageOptimizer.optimizeImage(imageBytes, quality: quality);
  }
}
