import 'package:flutter/material.dart';
import '../../db/trek_prep_database.dart';
import '../../models/materiel.dart';

/// Gestion des listes personnalisables : familles, sous-familles
/// rattachees a une famille, et marques.
class FamillesManagerScreen extends StatefulWidget {
  const FamillesManagerScreen({super.key});

  @override
  State<FamillesManagerScreen> createState() => _FamillesManagerScreenState();
}

class _FamillesManagerScreenState extends State<FamillesManagerScreen> {
  final _db = TrekPrepDatabase.instance;
  List<FamilleMateriel> _familles = [];
  List<SousFamilleMateriel> _sousFamilles = [];
  List<MarqueMateriel> _marques = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final familles = await _db.getFamilles();
    final sousFamilles = await _db.getSousFamilles();
    final marques = await _db.getMarques();
    if (!mounted) return;
    setState(() {
      _familles = familles;
      _sousFamilles = sousFamilles;
      _marques = marques;
      _loading = false;
    });
  }

  Future<String?> _prompt(String titre, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _ajouterFamille() async {
    final nom = await _prompt('Nouvelle famille');
    if (nom == null || nom.isEmpty) return;
    try {
      await _db.insertFamille(FamilleMateriel(nom: nom));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette famille existe déjà.')),
      );
    }
    _load();
  }

  Future<void> _renommerFamille(FamilleMateriel f) async {
    final nom = await _prompt('Renommer la famille', initial: f.nom);
    if (nom == null || nom.isEmpty || nom == f.nom) return;
    await _db.updateFamille(FamilleMateriel(id: f.id, nom: nom));
    _load();
  }

  Future<void> _supprimerFamille(FamilleMateriel f) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette famille ?'),
        content: Text(
          'La famille \"${f.nom}\" et ses sous-familles seront supprimees. '
          'Le materiel concerne sera conserve (sans famille).',
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
    await _db.deleteFamille(f.id!);
    _load();
  }

  Future<void> _ajouterSousFamille(FamilleMateriel f) async {
    final nom = await _prompt('Nouvelle sous-famille (${f.nom})');
    if (nom == null || nom.isEmpty) return;
    await _db
        .insertSousFamille(SousFamilleMateriel(familleId: f.id!, nom: nom));
    _load();
  }

  Future<void> _renommerSousFamille(SousFamilleMateriel sf) async {
    final nom = await _prompt('Renommer la sous-famille', initial: sf.nom);
    if (nom == null || nom.isEmpty || nom == sf.nom) return;
    await _db.updateSousFamille(
      SousFamilleMateriel(id: sf.id, familleId: sf.familleId, nom: nom),
    );
    _load();
  }

  Future<void> _supprimerSousFamille(SousFamilleMateriel sf) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette sous-famille ?'),
        content: Text(
          'La sous-famille \"${sf.nom}\" sera supprimee. Le materiel '
          'concerne sera conserve (sans sous-famille).',
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
    await _db.deleteSousFamille(sf.id!);
    _load();
  }

  Future<void> _ajouterMarque() async {
    final nom = await _prompt('Nouvelle marque');
    if (nom == null || nom.isEmpty) return;
    try {
      await _db.insertMarque(MarqueMateriel(nom: nom));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette marque existe déjà.')),
      );
    }
    _load();
  }

  Future<void> _renommerMarque(MarqueMateriel m) async {
    final nom = await _prompt('Renommer la marque', initial: m.nom);
    if (nom == null || nom.isEmpty || nom == m.nom) return;
    await _db.updateMarque(MarqueMateriel(id: m.id, nom: nom));
    _load();
  }

  Future<void> _supprimerMarque(MarqueMateriel m) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette marque ?'),
        content: Text(
          'La marque \"${m.nom}\" sera supprimee. Le materiel concerne '
          'sera conserve (sans marque).',
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
    await _db.deleteMarque(m.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (scaffoldContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Familles / sous-familles / marques'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Familles'),
                Tab(text: 'Marques'),
              ],
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    _buildFamillesTab(),
                    _buildMarquesTab(),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              final index = DefaultTabController.of(scaffoldContext).index;
              if (index == 0) {
                _ajouterFamille();
              } else {
                _ajouterMarque();
              }
            },
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  Widget _buildFamillesTab() {
    return ListView(
      children: [
        for (final f in _familles) ...[
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(
              f.nom,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'add') {
                  _ajouterSousFamille(f);
                } else if (action == 'rename') {
                  _renommerFamille(f);
                } else if (action == 'delete') {
                  _supprimerFamille(f);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Ajouter une sous-famille')),
                PopupMenuItem(value: 'rename', child: Text('Renommer')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ),
          for (final sf in _sousFamilles
              .where((sf) => sf.familleId == f.id)) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: Text(sf.nom),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'rename') {
                      _renommerSousFamille(sf);
                    } else if (action == 'delete') {
                      _supprimerSousFamille(sf);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renommer')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildMarquesTab() {
    if (_marques.isEmpty) {
      return const Center(
        child: Text(
          'Aucune marque. Ajoute-en avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      itemCount: _marques.length,
      itemBuilder: (context, index) {
        final m = _marques[index];
        return ListTile(
          leading: const Icon(Icons.label_outline),
          title: Text(m.nom),
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'rename') {
                _renommerMarque(m);
              } else if (action == 'delete') {
                _supprimerMarque(m);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        );
      },
    );
  }
}
