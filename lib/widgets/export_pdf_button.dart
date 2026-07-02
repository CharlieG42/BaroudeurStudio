import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trek.dart';
import '../services/export_service.dart';

/// Bouton pour exporter un trek dans différents formats
/// Offre 3 options : PDF texte seulement, PDF avec images, PPTX (PowerPoint)
class ExportPdfButton extends StatelessWidget {
  final Trek trek;
  final VoidCallback? onExportComplete;

  const ExportPdfButton({
    super.key,
    required this.trek,
    this.onExportComplete,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.picture_as_pdf),
      tooltip: 'Exporter le trek',
      onPressed: () => _showExportOptions(context),
    );
  }

  Future<void> _showExportOptions(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exporter le trek',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choisissez un format :',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              // Option 1: PDF texte seulement
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.blue),
                title: const Text('PDF - Texte seulement'),
                subtitle: const Text('Rapide, sans images, pas de risque de mémoire'),
                onTap: () => Navigator.pop(context, 'pdf_text'),
              ),
              // Option 2: PDF avec images
              ListTile(
                leading: const Icon(Icons.image, color: Colors.green),
                title: const Text('PDF - Avec images'),
                subtitle: const Text('Complet avec photos, génération en arrière-plan'),
                onTap: () => Navigator.pop(context, 'pdf_images'),
              ),
              // Option 3: PPTX (PowerPoint)
              ListTile(
                leading: const Icon(Icons.slideshow, color: Colors.purple),
                title: const Text('PowerPoint (PPTX)'),
                subtitle: const Text('Format modifiable, idéal pour les ajustements manuels'),
                onTap: () => Navigator.pop(context, 'pptx'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      final exportService = ExportService();
      File? exportFile;
      
      if (result == 'pdf_text') {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Génération du PDF (texte seulement)...')),
        );
        exportFile = await exportService.exportTrekToPdfTextOnly(trek);
      } 
      else if (result == 'pdf_images') {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Génération du PDF (avec images) en arrière-plan...')),
        );
        exportFile = await exportService.exportTrekToPdfWithImages(trek);
      } 
      else if (result == 'pptx') {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Génération du PowerPoint...')),
        );
        exportFile = await exportService.exportTrekToPptx(trek);
      }
      
      if (exportFile != null) {
        scaffoldMessenger.hideCurrentSnackBar();
        await _showExportResultDialog(context, exportFile);
      }
      
      onExportComplete?.call();
      
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la génération: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showExportResultDialog(BuildContext context, File exportFile) async {
    final fileName = exportFile.path.split('/').last;
    final fileType = fileName.endsWith('.pdf') ? 'PDF' : 'PowerPoint';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$fileType généré !'),
        content: Text('Fichier: $fileName'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fermer'),
          ),
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
