import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trek.dart';
import '../services/pdf_export_service.dart';

/// Bouton pour exporter un trek en PDF
/// Offre 2 options : texte seulement ou avec images (en arrière-plan)
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
      tooltip: 'Exporter en PDF',
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
                'Exporter le trek en PDF',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choisissez une option :',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.blue),
                title: const Text('Texte seulement'),
                subtitle: const Text('Rapide, sans images, pas de risque de mémoire'),
                onTap: () => Navigator.pop(context, 'text'),
              ),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.green),
                title: const Text('Avec images'),
                subtitle: const Text('Complet avec photos, génération en arrière-plan'),
                onTap: () => Navigator.pop(context, 'images'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      final pdfService = PdfExportService();
      
      if (result == 'text') {
        // Export texte seulement
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Génération du PDF (texte seulement)...')),
        );
        
        final pdfFile = await pdfService.exportTrekToPdfTextOnly(trek);
        scaffoldMessenger.hideCurrentSnackBar();
        
        _showPdfResultDialog(context, pdfFile);
      } else if (result == 'images') {
        // Export avec images en arrière-plan
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Génération du PDF (avec images) en arrière-plan...')),
        );
        
        final pdfFile = await pdfService.exportTrekToPdfWithImages(trek);
        scaffoldMessenger.hideCurrentSnackBar();
        
        _showPdfResultDialog(context, pdfFile);
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

  Future<void> _showPdfResultDialog(BuildContext context, File pdfFile) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF généré !'),
        content: Text('Fichier: ${pdfFile.path.split('/').last}'),
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
      await Share.shareXFiles([XFile(pdfFile.path)]);
    }
  }
}
