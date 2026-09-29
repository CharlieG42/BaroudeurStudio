import 'dart:io';

import 'package:flutter/material.dart';

import '../db/trek_preparation_database.dart';
import '../models/materiel_models.dart';
import '../services/materiel_photo_storage_service.dart';
import 'materiel_form_screen.dart';
import 'familles_marques_management_screen.dart';

/// Catalogue du materiel. En mode normal, permet de gerer le materiel.
/// En mode selection (depuis le detail d'une liste), un appui sur un
/// materiel l'ajoute a la liste concernee.
class MaterielListScreen extends StatefulWidget {
  final bool selectionMode;
  final int? listeId;

  const MaterielListScreen({super.key, this.selectionMode = false, this.listeId});

  @override
  State<MaterielListScreen> createState() => _MaterielListScreenState();
}

class _MaterielListScreenState extends State<MaterielListScreen> {
  List<Materiel> _materiels = [];
  Map<int, String> _nomsFamilles = {};
  Map<int, String> _nomsMarques = {};
  bool _loading = true;
  final _photoStorage = MaterielPhotoStorageService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = TrekPreparationDatabase.instance;
    final materiels = await db.getMateriels();
    final familles = await db.getFamilles();
    final marques = await db.getMarques();
    setState(() {
      _materiels = materiels;
      _nomsFamilles = {for (final f in familles) f.id!: f.nom};
      _nomsMarques = {for (final m in marques) m.id!: m.nom};
      _loading = false;
    });
  }

  Future<void> _openNewMateriel() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MaterielFormScreen()),
    );
    if (created == true) {
      _load();
    }
  }

  Future<void> _openEditMateriel(Materiel materiel) async {
    if (widget.selectionMode) return;
    final modified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MaterielFormScreen(materiel: materiel)),
    );
    if (modified == true) {
      _load();
    }
  }

  Future<void> _ajouterAListe(Materiel materiel) async {
    final db = TrekPreparationDatabase.instance;
    final existe = await db.materielDansListe(widget.listeId!, materiel.id!);
    if (!mounted) return;
    if (existe) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${materiel.nom} est déjà dans la liste.'),
        ),
      );
      return;
    }
    await db.insertLigne(
      LigneListe(listeId: widget.listeId!, materielId: materiel.id!),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${materiel.nom} ajouté à la liste.')),
    );
    Navigator.pop(context, true);
  }

  Future<void> _supprimerMateriel(Materiel materiel) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce matériel ?'),
        content: Text(
          '"${materiel.nom}" sera definitivement supprime du catalogue '
          'et retire de toutes les listes. Cette action est irreversible.',
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
    if (confirme != true) return;
    await TrekPreparationDatabase.instance.deleteMateriel(materiel.id!);
    if (materiel.photoPath.isNotEmpty) {
      await _photoStorage.supprimerPhoto(materiel.photoPath);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectionMode
            ? 'Choisir un matériel'
            : 'Catalogue du matériel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Familles, sous-familles et marques',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FamillesMarquesManagementScreen(),
                ),
              );
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _materiels.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _materiels.length,
                    itemBuilder: (context, index) {
                      final materiel = _materiels[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: _buildPhoto(materiel),
                          title: Text(
                            materiel.nom,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${_nomsMarques[materiel.marqueId] ?? '?'} \u2022 '
                            '${_nomsFamilles[materiel.familleId] ?? '?'} \u2022 '
                            '${_formatPoids(materiel.poidsGrammes)}',
                          ),
                          trailing: widget.selectionMode
                              ? const Icon(Icons.add_circle_outline)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Modifier',
                                      onPressed: () =>
                                          _openEditMateriel(materiel),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: 'Supprimer',
                                      onPressed: () =>
                                          _supprimerMateriel(materiel),
                                    ),
                                  ],
                                ),
                          onTap: () {
                            if (widget.selectionMode) {
                              _ajouterAListe(materiel);
                            } else {
                              _openEditMateriel(materiel);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: widget.selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _openNewMateriel,
              icon: const Icon(Icons.add),
              label: const Text('Nouveau matériel'),
            ),
    );
  }

  Widget? _buildPhoto(Materiel materiel) {
    if (materiel.photoPath.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.hiking));
    }
    final file = File(materiel.photoPath);
    if (!file.existsSync()) {
      return const CircleAvatar(child: Icon(Icons.hiking));
    }
    return CircleAvatar(
      backgroundImage: FileImage(file),
      onBackgroundImageError: (_, __) {},
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Aucun matériel au catalogue',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoute ton matériel (nom, marque, description, poids, '
              'famille, sous-famille, photo) pour le réutiliser dans '
              'toutes tes listes.',
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
