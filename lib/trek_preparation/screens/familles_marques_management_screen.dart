import 'package:flutter/material.dart';

import '../db/trek_preparation_database.dart';
import '../models/materiel_models.dart';

/// Ecran de gestion des listes personnalisables : familles,
/// sous-familles (par famille) et marques.
class FamillesMarquesManagementScreen extends StatefulWidget {
  const FamillesMarquesManagementScreen({super.key});

  @override
  State<FamillesMarquesManagementScreen> createState() =>
      _FamillesMarquesManagementScreenState();
}

class _FamillesMarquesManagementScreenState
    extends State<FamillesMarquesManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Famille> _familles = [];
  Map<int, List<SousFamille>> _sousFamillesByFamille = {};
  List<Marque> _marques = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = TrekPreparationDatabase.instance;
    final familles = await db.getFamilles();
    final sousFamilles = await db.getAllSousFamilles();
    final marques = await db.getMarques();
    setState(() {
      _familles = familles;
      _sousFamillesByFamille = {};
      for (final sf in sousFamilles) {
        _sousFamillesByFamille.putIfAbsent(sf.familleId, () => []).add(sf);
      }
      _marques = marques;
    });
  }

  Future<String?> _saisirNom(String titre, {String? valeurInitiale}) async {
    final controller = TextEditingController(text: valeurInitiale ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  // FAMILLES

  Future<void> _ajouterFamille() async {
    final nom = await _saisirNom('Nouvelle famille');
    if (nom == null || nom.isEmpty) return;
    try {
      await TrekPreparationDatabase.instance.insertFamille(Famille(nom: nom));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette famille existe déjà.')),
      );
      return;
    }
    _load();
  }

  Future<void> _renommerFamille(Famille famille) async {
    final nom = await _saisirNom('Renommer la famille',
        valeurInitiale: famille.nom);
    if (nom == null || nom.isEmpty) return;
    await TrekPreparationDatabase.instance
        .updateFamille(Famille(id: famille.id, nom: nom));
    _load();
  }

  Future<void> _supprimerFamille(Famille famille) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette famille ?'),
        content: Text(
          'La famille "${famille.nom}", ses sous-familles et le materiel '
          'associe seront supprimes definitivement.',
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
    await TrekPreparationDatabase.instance.deleteFamille(famille.id!);
    _load();
  }

  // SOUS-FAMILLES

  Future<void> _ajouterSousFamille(Famille famille) async {
    final nom = await _saisirNom(
      'Nouvelle sous-famille pour "${famille.nom}"',
    );
    if (nom == null || nom.isEmpty) return;
    await TrekPreparationDatabase.instance
        .insertSousFamille(SousFamille(familleId: famille.id!, nom: nom));
    _load();
  }

  Future<void> _renommerSousFamille(SousFamille sousFamille) async {
    final nom =
        await _saisirNom('Renommer la sous-famille', valeurInitiale: sousFamille.nom);
    if (nom == null || nom.isEmpty) return;
    await TrekPreparationDatabase.instance
        .updateSousFamille(SousFamille(id: sousFamille.id, familleId: sousFamille.familleId, nom: nom));
    _load();
  }

  Future<void> _supprimerSousFamille(SousFamille sousFamille) async {
    await TrekPreparationDatabase.instance.deleteSousFamille(sousFamille.id!);
    _load();
  }

  // MARQUES

  Future<void> _ajouterMarque() async {
    final nom = await _saisirNom('Nouvelle marque');
    if (nom == null || nom.isEmpty) return;
    try {
      await TrekPreparationDatabase.instance.insertMarque(Marque(nom: nom));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette marque existe déjà.')),
      );
      return;
    }
    _load();
  }

  Future<void> _renommerMarque(Marque marque) async {
    final nom = await _saisirNom('Renommer la marque', valeurInitiale: marque.nom);
    if (nom == null || nom.isEmpty) return;
    await TrekPreparationDatabase.instance
        .updateMarque(Marque(id: marque.id, nom: nom));
    _load();
  }

  Future<void> _supprimerMarque(Marque marque) async {
    await TrekPreparationDatabase.instance.deleteMarque(marque.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Familles, sous-familles et marques'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.category_outlined), text: 'Familles'),
            Tab(icon: Icon(Icons.subdirectory_arrow_right), text: 'Sous-familles'),
            Tab(icon: Icon(Icons.sell_outlined), text: 'Marques'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFamillesTab(),
          _buildSousFamillesTab(),
          _buildMarquesTab(),
        ],
      ),
      floatingActionButton: (_tabController.index == 0 || _tabController.index == 2)
          ? FloatingActionButton(
              onPressed: () {
                if (_tabController.index == 0) {
                  _ajouterFamille();
                } else {
                  _ajouterMarque();
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildFamillesTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _familles
          .map(
            (famille) => Card(
              child: ListTile(
                title: Text(famille.nom),
                subtitle: Text(
                  '${_sousFamillesByFamille[famille.id]?.length ?? 0} '
                  'sous-famille(s)',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Renommer',
                      onPressed: () => _renommerFamille(famille),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerFamille(famille),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSousFamillesTab() {
    if (_familles.isEmpty) {
      return const Center(
        child: Text('Crée d\'abord une famille.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _familles
          .map(
            (famille) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          famille.nom,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Ajouter une sous-famille',
                        onPressed: () => _ajouterSousFamille(famille),
                      ),
                    ],
                  ),
                ),
                ...?_sousFamillesByFamille[famille.id]?.map(
                      (sf) => ListTile(
                        dense: true,
                        title: Text(sf.nom),
                        leading: const Icon(Icons.subdirectory_arrow_right),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Renommer',
                              onPressed: () => _renommerSousFamille(sf),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'Supprimer',
                              onPressed: () => _supprimerSousFamille(sf),
                            ),
                          ],
                        ),
                      ),
                    ),
                const Divider(),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _buildMarquesTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _marques
          .map(
            (marque) => Card(
              child: ListTile(
                title: Text(marque.nom),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Renommer',
                      onPressed: () => _renommerMarque(marque),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Supprimer',
                      onPressed: () => _supprimerMarque(marque),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
