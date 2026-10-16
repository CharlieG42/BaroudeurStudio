import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/drive/drive_backup_orchestrator.dart';
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Tout sauvegarder sur Drive'),
              onPressed: () => _toutSauvegarderDrive(ctx),
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

  Future<void> _toutSauvegarderDrive(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Sauvegarde Drive en cours…')),
    );

    final resultat =
        await DriveBackupOrchestrator().sauvegarderToutMaintenant();
    if (!context.mounted) return;

    if (resultat.erreurs.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
              '${resultat.reussis} sauvegarde(s) envoyée(s) sur Drive.'),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sauvegarde terminée avec erreurs'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${resultat.reussis} réussie(s), '
                  '${resultat.erreurs.length} échec(s) :'),
              const SizedBox(height: 8),
              ...resultat.erreurs.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ),
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
    }
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
