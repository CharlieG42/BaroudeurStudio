import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Boîte de dialogue « À propos de » affichant la version de l'application.
class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline),
      tooltip: 'À propos de',
      onPressed: () => _showAboutDialog(context),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.terrain, size: 48, color: Colors.brown),
        title: const Text('BaroudeurStudio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${AppConfig.appVersion}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Carnet de trek vers livre illustré.\n\n'
              'Génère un document ODP (LibreOffice) structuré en chapitres '
              'à partir de vos treks, jours et photos.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
