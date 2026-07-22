import 'package:flutter/material.dart';

import 'export_odp_button.dart';
import 'compression_settings_dialog.dart';
import '../models/trek.dart';

/// Barre d'outils pour l'export ODP et les paramètres
/// À utiliser dans l'AppBar des écrans de trek
class ExportButtonBar extends StatelessWidget {
  final Trek trek;
  final VoidCallback? onExportComplete;

  const ExportButtonBar({
    super.key,
    required this.trek,
    this.onExportComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bouton d'export ODP
        ExportOdpButton(
          trek: trek,
          onExportComplete: onExportComplete,
        ),
        const SizedBox(width: 8),
        // Bouton de paramètres de compression
        const CompressionSettingsButton(),
      ],
    );
  }
}
