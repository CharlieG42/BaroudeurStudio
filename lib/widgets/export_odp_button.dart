import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trek.dart';
import '../services/export_service.dart';
import '../services/utils/filename_utils.dart';

/// Bouton pour exporter un trek au format ODP (OpenDocument Presentation)
/// Le document généré est systématiquement en orientation portrait
class ExportOdpButton extends StatelessWidget {
  final Trek trek;
  final VoidCallback? onExportComplete;

  const ExportOdpButton({
    super.key,
    required this.trek,
    this.onExportComplete,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.slideshow),
      tooltip: 'Exporter en ODP (LibreOffice)',
      onPressed: () => _exportToOdp(context),
    );
  }

  Future<void> _exportToOdp(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Génération du ODP (LibreOffice)...')),
      );
      
      final exportService = ExportService();
      final exportFile = await exportService.exportTrekToOdp(trek);
      
      scaffoldMessenger.hideCurrentSnackBar();
      await _saveFileWithDialog(context, exportFile);
      
      onExportComplete?.call();
      
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la génération: ' + e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Affiche une boîte de dialogue pour enregistrer le fichier avec "Enregistrer sous"
  /// Sur Windows: utilise FilePicker pour choisir l'emplacement
  /// Sur mobile: utilise le partage
  Future<void> _saveFileWithDialog(BuildContext context, File exportFile) async {
    final fileName = exportFile.path.split(Platform.pathSeparator).last;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    
    // Extraire l'extension
    final extension = fileName.split('.').last;
    
    // Nettoyer le nom de fichier pour Windows (au cas où)
    final baseName = fileName.substring(0, fileName.length - extension.length - 1);
    final sanitizedFileName = FilenameUtils.sanitizeFilename(baseName) + '.' + extension;

    if (isWindows) {
      // Sur Windows: utilise FilePicker pour "Enregistrer sous"
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le fichier ODP',
        fileName: sanitizedFileName,
        bytes: await exportFile.readAsBytes(),
        allowedExtensions: [extension],
      );

      if (savePath != null) {
        // Copier le fichier vers le nouvel emplacement
        final savedFile = File(savePath);
        await savedFile.writeAsBytes(await exportFile.readAsBytes());
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fichier ODP enregistré: ' + savePath.split(Platform.pathSeparator).last),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } else {
      // Sur mobile: utiliser le partage
      await _showExportResultDialog(context, exportFile);
    }
  }

  /// Dialogue pour mobile (partage)
  Future<void> _showExportResultDialog(BuildContext context, File exportFile) async {
    final fileName = exportFile.path.split('/').last;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ODP généré !'),
        content: Text('Fichier: ' + fileName + '\n\nLe document est en orientation portrait (21cm x 28cm).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fermer'),
          ),
          if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Partager'),
            ),
        ],
      ),
    );

    if (result == true) {
      await Share.shareXFiles([XFile(exportFile.path)]);
    }
  }
}
