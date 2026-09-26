import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../db/trip_planner_database.dart';
import '../models/voyage.dart';
import '../services/demo_seed_service.dart';
import '../services/trip_export_service.dart';
import 'voyage_form_screen.dart';
import 'voyage_map_screen.dart';

/// Ecran d'accueil du module de planification de voyage : liste des
/// voyages, creation d'un nouveau voyage, acces a la carte de chacun,
/// import/export au format .bwzt pour transferer un voyage d'un
/// appareil a un autre.
class VoyageListScreen extends StatefulWidget {
  const VoyageListScreen({super.key});

  @override
  State<VoyageListScreen> createState() => _VoyageListScreenState();
}

class _VoyageListScreenState extends State<VoyageListScreen> {
  List<Voyage> _voyages = [];
  bool _loading = true;
  bool _importEnCours = false;
  final _exportService = TripExportService();

  @override
  void initState() {
    super.initState();
    _loadVoyages();
  }

  Future<void> _loadVoyages() async {
    setState(() => _loading = true);
    final voyages = await TripPlannerDatabase.instance.getVoyages();
    setState(() {
      _voyages = voyages;
      _loading = false;
    });
  }

  String _formatDateRange(Voyage voyage) {
    try {
      final debut = DateTime.parse(voyage.dateDebut);
      final fin = DateTime.parse(voyage.dateFin);
      final fmt = DateFormat('dd/MM/yyyy');
      return '${fmt.format(debut)} → ${fmt.format(fin)}';
    } catch (_) {
      return '${voyage.dateDebut} → ${voyage.dateFin}';
    }
  }

  Future<void> _openNewVoyage() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const VoyageFormScreen()),
    );
    if (created == true) {
      _loadVoyages();
    }
  }

  Future<void> _openVoyageMap(Voyage voyage) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoyageMapScreen(voyage: voyage)),
    );
    _loadVoyages();
  }

  Future<bool> _confirmerSuppression(Voyage voyage) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce voyage ?'),
        content: Text(
          'Toutes les etapes, trajets et documents attaches a '
          '"${voyage.titre}" seront definitivement supprimes. Cette '
          'action est irreversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    return confirme == true;
  }

  Future<void> _supprimerVoyage(Voyage voyage) async {
    if (voyage.id == null) return;
    await TripPlannerDatabase.instance.deleteVoyage(voyage.id!);
    if (!mounted) return;
    setState(() => _voyages.removeWhere((v) => v.id == voyage.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${voyage.titre}" supprime.')),
    );
  }

  Future<void> _creerVoyageDemo() async {
    setState(() => _loading = true);
    final id = await DemoSeedService().creerVoyageDemoUsa();
    await _loadVoyages();
    if (!mounted) return;
    final voyage = await TripPlannerDatabase.instance.getVoyage(id);
    if (voyage != null) {
      _openVoyageMap(voyage);
    }
  }

  /// Exporte un voyage en .bwzt puis propose de le partager (mobile)
  /// ou de choisir l'emplacement d'enregistrement (Windows).
  Future<void> _exporterVoyage(Voyage voyage) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Preparation de l\'export...')),
    );

    try {
      final fichier = await _exportService.exporterVoyage(voyage);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer le voyage',
          fileName: fichier.path.split(Platform.pathSeparator).last,
          bytes: await fichier.readAsBytes(),
          allowedExtensions: ['bwzt'],
        );
        if (savePath != null) {
          await File(savePath).writeAsBytes(await fichier.readAsBytes());
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voyage exporte.')),
          );
        }
      } else {
        await Share.shareXFiles(
          [XFile(fichier.path)],
          subject: 'Voyage : ${voyage.titre}',
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Echec de l\'export : $e')),
      );
    }
  }

  /// Importe un fichier .bwzt choisi par l'utilisateur : cree un
  /// nouveau voyage local puis l'ouvre directement.
  Future<void> _importerVoyage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bwzt'],
    );
    final chemin = result?.files.single.path;
    if (chemin == null) return;

    setState(() => _importEnCours = true);
    try {
      final voyageId = await _exportService.importerVoyage(chemin);
      await _loadVoyages();
      if (!mounted) return;
      setState(() => _importEnCours = false);

      final voyage = await TripPlannerDatabase.instance.getVoyage(voyageId);
      if (voyage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${voyage.titre}" importe.')),
        );
        _openVoyageMap(voyage);
      }
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _importEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Echec de l\'import : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planification de voyage'),
        actions: [
          IconButton(
            icon: _importEnCours
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_upload_outlined),
            tooltip: 'Importer un voyage (.bwzt)',
            onPressed: _importEnCours ? null : _importerVoyage,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _voyages.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadVoyages,
                  child: ListView.builder(
                    itemCount: _voyages.length,
                    itemBuilder: (context, index) {
                      final voyage = _voyages[index];
                      return Dismissible(
                        key: ValueKey(voyage.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmerSuppression(voyage),
                        onDismissed: (_) => _supprimerVoyage(voyage),
                        background: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.white),
                        ),
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.map_outlined),
                            ),
                            title: Text(
                              voyage.titre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(_formatDateRange(voyage)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.ios_share, size: 20),
                                  tooltip: 'Exporter (.bwzt)',
                                  onPressed: () => _exporterVoyage(voyage),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => _openVoyageMap(voyage),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'nouveau_voyage',
            onPressed: _openNewVoyage,
            icon: const Icon(Icons.add),
            label: const Text('Nouveau voyage'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.explore_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Aucun voyage planifie pour le moment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cree un voyage pour commencer a placer tes etapes sur la '
              'carte, ou importe un fichier .bwzt recu d\'un autre appareil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _creerVoyageDemo,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Charger le voyage USA de demonstration'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _importEnCours ? null : _importerVoyage,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Importer un voyage (.bwzt)'),
            ),
          ],
        ),
      ),
    );
  }
}
