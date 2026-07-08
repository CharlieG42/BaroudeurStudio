import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trek.dart';
import '../services/export_service.dart';

/// Bouton pour exporter un trek dans différents formats
/// Offre 2 options : PDF texte seulement, ODP (OpenDocument Presentation)
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
              // Option 2: ODP (OpenDocument Presentation)
              ListTile(
                leading: const Icon(Icons.slideshow, color: Colors.orange),
                title: const Text('ODP (LibreOffice)'),
                subtitle: const Text('Format modifiable, compatible avec LibreOffice/OpenOffice'),
                onTap: () => Navigator.pop(context, 'odp'),
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
      else if (result == 'odp') {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Génération du ODP (LibreOffice)...')),
        );
        exportFile = await exportService.exportTrekToOdp(trek);
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
          content: Text('Erreur lors de la génération: ' + e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showExportResultDialog(BuildContext context, File exportFile) async {
    final fileName = exportFile.path.split('/').last;
    final fileType = fileName.endsWith('.pdf') ? 'PDF' : 'ODP';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileType + ' généré !'),
        content: Text('Fichier: ' + fileName),
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