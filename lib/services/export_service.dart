import 'dart:typed_data';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/trek.dart';
import 'pdf/pdf_export_service.dart';
import 'odp/odp_export_service.dart';
import 'utils/filename_utils.dart';
import 'utils/image_optimizer.dart';

/// Service unifié pour exporter les treks dans différents formats
/// Formats supportés : PDF (texte seulement), ODP (OpenDocument Presentation)
/// 
/// Ce service agit comme une façade pour les différents services d'export.
class ExportService {
  static final ExportService _instance = ExportService._internal();
  
  factory ExportService() => _instance;
  
  ExportService._internal();

  // Service PDF
  final PdfExportService _pdfExportService = PdfExportService();
  
  // Service ODP
  final OdpExportService _odpExportService = OdpExportService();

  // ===========================================================================
  // EXPORT PDF
  // ===========================================================================

  /// Génère un PDF avec le texte uniquement (pas d'images)
  /// Format rapide, sans risque de mémoire
  Future<File> exportTrekToPdfTextOnly(Trek trek) async {
    return _pdfExportService.exportTrekToPdfTextOnly(trek);
  }

  /// Imprime le PDF (texte seulement)
  Future<void> printTrekPdf(Trek trek) async {
    return _pdfExportService.printTrekPdf(trek);
  }

  // ===========================================================================
  // EXPORT ODP (OpenDocument Presentation)
  // ===========================================================================

  /// Génère un ODP (OpenDocument Presentation) modifiable
  /// Format idéal pour les ajustements manuels, compatible avec LibreOffice
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