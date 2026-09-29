import 'package:flutter/material.dart';
import 'dart:io';
import '../../db/trek_prep_database.dart';
import '../../models/materiel.dart';
import 'materiel_catalog_screen.dart';

/// Module de preparation de trek : listes de materiel avec total des
/// poids par famille et poids total.
class TrekPrepScreen extends StatefulWidget {
  const TrekPrepScreen({super.key});

  @override
  State<TrekPrepScreen> createState() => _TrekPrepScreenState();
}

class _TrekPrepScreenState extends State<TrekPrepScreen> {
  final _db = TrekPrepDatabase.instance;
  List<Map<String, dynamic>> _listes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final listes = await _db.getListes();
    if (!mounted) return;
    setState(() {
      _listes = listes;
      _loading = false;
    });
  }

  Future<void> _creerListe() async {
    final controller = TextEditingController();
    final nom = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle liste de matériel'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom de la liste'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (nom == null || nom.isEmpty) return;
    await _db.insertListe(nom);
    _load();
  }

  Future<void> _renommerListe(Map<String, dynamic> liste) async {
    final controller = TextEditingController(text: liste['nom'] as String);
    final nom = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer la liste'),
        content: TextField(
          controller: controller,
          autofocus: true,
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
    if (nom == null || nom.isEmpty) return;
    await _db.renameListe(liste['id'] as int, nom);
    _load();
  }

  Future<void> _supprimerListe(Map<String, dynamic> liste) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette liste ?'),
        content: Text(
          'La liste \"${liste['nom']}\" et son contenu seront supprimes. '
          'Le materiel du catalogue est conserve.',
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
    await _db.deleteListe(liste['id'] as int);
    _load();
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const MaterielCatalogScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _listes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.checklist,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Aucune liste pour le moment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Crée une liste de matériel pour préparer ton '
                          'prochain trek, ajoute tes équipements depuis le '
                          'catalogue et suis le poids total de ton sac.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MaterielCatalogScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Gérer le matériel'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _listes.length,
                  itemBuilder: (context, index) {
                    final liste = _listes[index];
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
                          liste['nom'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'rename') {
                                  _renommerListe(liste);
                                } else if (action == 'delete') {
                                  _supprimerListe(liste);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Renommer'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Supprimer'),
                                ),
                              ],
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ListeMaterielScreen(
                              listeId: liste['id'] as int,
                              listeNom: liste['nom'] as String,
                            ),
                          ),
                        ).then((_) => _load()),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creerListe,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle liste'),
      ),
    );
  }
}

/// Une liste de materiel : items cocheables, total des poids par
/// famille et poids total du sac.
class ListeMaterielScreen extends StatefulWidget {
  final int listeId;
  final String listeNom;

  const ListeMaterielScreen({
    super.key,
    required this.listeId,
    required this.listeNom,
  });

  @override
  State<ListeMaterielScreen> createState() => _ListeMaterielScreenState();
}

class _ListeMaterielScreenState extends State<ListeMaterielScreen> {
  final _db = TrekPrepDatabase.instance;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _db.getItemsListe(widget.listeId);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _formatPoids(double g) {
    if (g >= 1000) {
      final kg = g / 1000;
      return '${kg % 1 == 0 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(2)} kg';
    }
    return '${g % 1 == 0 ? g.toStringAsFixed(0) : g.toStringAsFixed(1)} g';
  }

  /// Poids total (somme poids x quantite, tous items).
  double get _poidsTotal {
    double total = 0;
    for (final item in _items) {
      total +=
          (item['poids_grammes'] as double) * (item['quantite'] as int);
    }
    return total;
  }

  /// Poids par famille (items regroupes par nom de famille).
  Map<String, double> get _poidsParFamille {
    final poids = <String, double>{};
    for (final item in _items) {
      final famille = (item['famille_nom'] as String?) ?? 'Sans famille';
      poids[famille] = (poids[famille] ?? 0) +
          (item['poids_grammes'] as double) * (item['quantite'] as int);
    }
    final entries = poids.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Map.fromEntries(entries);
  }

  Future<void> _ajouterMateriel() async {
    final materiels = await _db.getMateriels();
    final familles = await _db.getFamilles();
    final marques = await _db.getMarques();
    if (!mounted) return;
    final dejaIds = _items
        .map((i) => i['materiel_id'] as int)
        .toSet();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Ajouter du matériel',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            if (materiels.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Le catalogue est vide. Ajoute du matériel depuis '
                  'l\'écran Matériel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            for (final m in materiels)
              ListTile(
                leading: dejaIds.contains(m.id)
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                title: Text(m.nom),
                subtitle: Text(
                  [
                    for (final f in familles)
                      if (f.id == m.familleId) f.nom,
                    for (final ma in marques)
                      if (ma.id == m.marqueId) ma.nom,
                    _formatPoids(m.poidsGrammes),
                  ].join(' · '),
                ),
                onTap: () async {
                  await _db.addItemToListe(
                    listeId: widget.listeId,
                    materielId: m.id!,
                  );
                  Navigator.pop(sheetContext);
                  _load();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changerQuantite(Map<String, dynamic> item) async {
    final q = item['quantite'] as int;
    final newValue = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quantité : ${item['materiel_nom']}'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context, q - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '$q',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context, q + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
    if (newValue == null) return;
    if (newValue < 1) {
      await _db.removeItemFromListe(item['item_id'] as int);
    } else {
      await _db.setItemQuantite(item['item_id'] as int, newValue);
    }
    _load();
  }

  Future<void> _retirerItem(Map<String, dynamic> item) async {
    await _db.removeItemFromListe(item['item_id'] as int);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final poidsParFamille = _poidsParFamille;
    final total = _poidsTotal;

    return Scaffold(
      appBar: AppBar(title: Text(widget.listeNom)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _items.isEmpty
                      ? const Center(
                          child: Text(
                            'Liste vide. Ajoute du matériel avec le bouton +.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final entry in poidsParFamille.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.key.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatPoids(entry.value),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              for (final item in _items.where(
                                (i) =>
                                    ((i['famille_nom'] as String?) ??
                                        'Sans famille') ==
                                    entry.key,
                              ))
                                _buildItemTile(item),
                            ],
                          ],
                        ),
                ),
                _buildResume(poidsParFamille, total),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ajouterMateriel,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter du matériel'),
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    final pris = (item['pris'] as int) == 1;
    final quantite = item['quantite'] as int;
    final cheminPhoto = item['chemin_photo'] as String?;
    final sousFamille = item['sous_famille_nom'] as String?;
    final marque = item['marque_nom'] as String?;

    return Dismissible(
      key: ValueKey('item_${item['item_id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _retirerItem(item),
      child: ListTile(
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: pris,
              onChanged: (v) async {
                await _db.setItemPris(item['item_id'] as int, v ?? false);
                _load();
              },
            ),
            if (cheminPhoto != null && File(cheminPhoto).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(cheminPhoto),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
        title: Text(
          item['materiel_nom'] as String,
          style: TextStyle(
            decoration: pris ? TextDecoration.lineThrough : null,
            color: pris ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          [
            if (marque != null) marque,
            if (sousFamille != null) sousFamille,
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quantite > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('x$quantite'),
              ),
            Text(
              _formatPoids(
                (item['poids_grammes'] as double) * quantite,
              ),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        onTap: () => _changerQuantite(item),
      ),
    );
  }

  /// Resume : poids par famille + poids total du sac.
  Widget _buildResume(Map<String, double> poidsParFamille, double total) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bilan des poids',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final entry in poidsParFamille.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text(_formatPoids(entry.value)),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Poids total',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  _formatPoids(total),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
