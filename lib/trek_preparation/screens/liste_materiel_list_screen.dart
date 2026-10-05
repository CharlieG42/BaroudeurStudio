import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../db/trek_preparation_database.dart';
import '../services/preparation_export_service.dart';
import '../models/materiel_models.dart';
import 'liste_materiel_form_screen.dart';
import 'liste_materiel_detail_screen.dart';
import 'materiel_list_screen.dart';

/// Ecran d'accueil du module de preparation de trek : liste des
/// listes de materiel et acces au catalogue du materiel.
class ListeMaterielListScreen extends StatefulWidget {
  const ListeMaterielListScreen({super.key});

  @override
  State<ListeMaterielListScreen> createState() =>
      _ListeMaterielListScreenState();
}

class _ListeMaterielListScreenState extends State<ListeMaterielListScreen> {
  List<ListeMaterielData> _listes = [];
  bool _loading = true;
  bool _importEnCours = false;
  final PreparationExportService _exportService = PreparationExportService();

  @override
  void initState() {
    super.initState();
    _loadListes();
  }

  Future<void> _loadListes() async {
    setState(() => _loading = true);
    final db = TrekPreparationDatabase.instance;
    final listes = await db.getListes();
    final data = <ListeMaterielData>[];
    for (final liste in listes) {
      final poidsTotal = await db.getPoidsTotal(liste.id!);
      final poidsParFamille = await db.getPoidsParFamille(liste.id!);
      data.add(ListeMaterielData(
        liste: liste,
        poidsTotalGrammes: poidsTotal,
        poidsParFamille: poidsParFamille,
      ));
    }
    setState(() {
      _listes = data;
      _loading = false;
    });
  }

  /// Exporte tout le module (catalogue + listes) en .bwzt puis propose
  /// de le partager (mobile) ou de choisir l'emplacement
  /// d'enregistrement (Windows).
  Future<void> _exporterPreparation() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text("Préparation de l'export...")),
    );
    try {
      final fichier = await _exportService.exporterPreparation();
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Enregistrer la préparation',
          fileName: fichier.path.split(Platform.pathSeparator).last,
          bytes: await fichier.readAsBytes(),
          allowedExtensions: ['bwzt'],
        );
        if (savePath != null) {
          await File(savePath).writeAsBytes(await fichier.readAsBytes());
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Préparation exportée.')),
          );
        }
      } else {
        await Share.shareXFiles(
          [XFile(fichier.path)],
          subject: 'Préparation de trek',
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Échec de l'export : $e")),
      );
    }
  }

  /// Importe un fichier .bwzt : integre le catalogue et cree les
  /// listes de preparation contenues dans l'archive.
  Future<void> _importerPreparation() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bwzt'],
    );
    final chemin = result?.files.single.path;
    if (chemin == null) return;
    setState(() => _importEnCours = true);
    try {
      final nbListes = await _exportService.importerPreparation(chemin);
      await _loadListes();
      if (!mounted) return;
      setState(() => _importEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import réussi : $nbListes liste(s) et le catalogue de matériel.',
          ),
        ),
      );
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
        SnackBar(content: Text("Échec de l'import : $e")),
      );
    }
  }

  Future<void> _openNewListe() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ListeMaterielFormScreen()),
    );
    if (created == true) {
      _loadListes();
    }
  }

  Future<void> _openDetail(ListeMaterielData data) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListeMaterielDetailScreen(liste: data.liste),
      ),
    );
    _loadListes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Préparation de trek'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Catalogue du matériel',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaterielListScreen()),
              );
              _loadListes();
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Importer la préparation (.bwzt)',
            onPressed: _importEnCours ? null : _importerPreparation,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exporter la préparation (.bwzt)',
            onPressed: _exporterPreparation,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _listes.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadListes,
                  child: ListView.builder(
                    itemCount: _listes.length,
                    itemBuilder: (context, index) {
                      final data = _listes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.checklist),
                          ),
                          title: Text(
                            data.liste.nom,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Poids total : ${_formatPoids(data.poidsTotalGrammes)}\n'
                            '${data.poidsParFamille.length} catégorie(s)',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openDetail(data),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewListe,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle liste'),
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
            const Icon(Icons.backpack_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Aucune liste de matériel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crée une liste de matériel à emporter pour ton prochain trek, '
              'puis ajoute le matériel du catalogue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPoids(double grammes) {
  if (grammes >= 1000) {
    return '${(grammes / 1000).toStringAsFixed(2)} kg';
  }
  return '${grammes.toStringAsFixed(0)} g';
}

/// Donnees affichees pour une liste : la liste + ses totaux de poids.
class ListeMaterielData {
  final ListeMateriel liste;
  final double poidsTotalGrammes;
  final List<PoidsParFamille> poidsParFamille;

  ListeMaterielData({
    required this.liste,
    required this.poidsTotalGrammes,
    required this.poidsParFamille,
  });
}
