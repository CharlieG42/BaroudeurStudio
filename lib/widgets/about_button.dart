import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/drive/drive_connection_service.dart';

/// Boîte de dialogue « À propos » affichant la version de l'application
/// et un test de connexion Google Drive.
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
            const Divider(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Tester la connexion Google Drive'),
              onPressed: () => _testerConnexionDrive(ctx),
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

  Future<void> _testerConnexionDrive(BuildContext context) async {
    final service = DriveConnectionService();
    final messenger = ScaffoldMessenger.maybeOf(context);

    final resultat = await service.testerConnexion();
    if (!context.mounted) return;

    if (resultat.ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_done, size: 48, color: Colors.green),
          title: const Text('Google Drive connecté'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Compte : ${resultat.compte ?? 'inconnu'}'),
              const SizedBox(height: 8),
              Text('Quota Drive : ${resultat.quota ?? 'inconnu'}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      messenger?.showSnackBar(
        SnackBar(content: Text('Drive KO : ${resultat.erreur}')),
      );
    }
  }
}
