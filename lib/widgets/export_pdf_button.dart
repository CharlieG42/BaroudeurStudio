import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trek.dart';
import '../services/pdf_export_service.dart';

/// Bouton pour exporter un trek en PDF
/// Utilisation : ExportPdfButton(trek: trek)
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
    return ElevatedButton.icon(
      onPressed: () => _exportPdf(context),
      icon: const Icon(Icons.picture_as_pdf),
      label: const Text('Exporter en PDF'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFf5a665), // Orange chaud
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    try {
      // Afficher un indicateur de chargement
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      
      // Générer le PDF
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Génération du PDF en cours...')),
      );

      final pdfService = PdfExportService();
      final pdfFile = await pdfService.exportTrekToPdf(trek);

      // Masquer le snackbar précédent
      scaffoldMessenger.hideCurrentSnackBar();

      // Proposer de partager ou d'ouvrir le fichier
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

      // Partager le fichier si l'utilisateur a cliqué sur Partager
      if (result == true) {
        await Share.shareXFiles([XFile(pdfFile.path)]);
      }

      // Callback optionnel
      onExportComplete?.call();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la génération: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
