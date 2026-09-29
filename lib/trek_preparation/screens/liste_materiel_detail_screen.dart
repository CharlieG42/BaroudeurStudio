import 'package:flutter/material.dart';

import '../db/trek_preparation_database.dart';
import '../models/materiel_models.dart';
import 'liste_materiel_form_screen.dart';
import 'materiel_list_screen.dart';

/// Detail d'une liste de materiel : lignes cochees, poids par famille
/// et poids total de la liste.
class ListeMaterielDetailScreen extends StatefulWidget {
  final ListeMateriel liste;

  const ListeMaterielDetailScreen({super.key, required this.liste});

  @override
  State<ListeMaterielDetailScreen> createState() =>
      _ListeMaterielDetailScreenState();
}

class _ListeMaterielDetailScreenState extends State<ListeMaterielDetailScreen> {
  List<LigneListeDetaillee> _lignes = [];
  List<PoidsParFamille> _poidsParFamille = [];
  double _poidsTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = TrekPreparationDatabase.instance;
    final lignes = await db.getLignesDetaillees(widget.liste.id!);
    final poidsFamilles = await db.getPoidsParFamille(widget.liste.id!);
    final poidsTotal = await db.getPoidsTotal(widget.liste.id!);
    setState(() {
      _lignes = lignes;
      _poidsParFamille = poidsFamilles;
      _poidsTotal = poidsTotal;
      _loading = false;
    });
  }

  Future<void> _ajouterMateriel() async {
    final ajoute = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MaterielListScreen(
          selectionMode: true,
          listeId: widget.liste.id!,
        ),
      ),
    );
    if (ajoute == true) {
      _load();
    }
  }

  Future<void> _togglePris(LigneListeDetaillee ligne) async {
    await TrekPreparationDatabase.instance.updateLigne(
      LigneListe(
        id: ligne.ligne.id,
        listeId: ligne.ligne.listeId,
        materielId: ligne.ligne.materielId,
        quantite: ligne.ligne.quantite,
        pris: !ligne.ligne.pris,
      ),
    );
    _load();
  }

  Future<void> _changerQuantite(LigneListeDetaillee ligne, int delta) async {
    final nouvelleQuantite = ligne.ligne.quantite + delta;
    if (nouvelleQuantite < 1) return;
    await TrekPreparationDatabase.instance.updateLigne(
      LigneListe(
        id: ligne.ligne.id,
        listeId: ligne.ligne.listeId,
        materielId: ligne.ligne.materielId,
        quantite: nouvelleQuantite,
        pris: ligne.ligne.pris,
      ),
    );
    _load();
  }

  Future<void> _supprimerLigne(LigneListeDetaillee ligne) async {
    await TrekPreparationDatabase.instance.deleteLigne(ligne.ligne.id!);
    _load();
  }

  Future<void> _modifierListe() async {
    final modified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ListeMaterielFormScreen(liste: widget.liste),
      ),
    );
    if (modified == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.liste.nom),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier la liste',
            onPressed: _modifierListe,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTotaux(),
                Expanded(child: _buildLignes()),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ajouterMateriel,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Ajouter du matériel'),
      ),
    );
  }

  Widget _buildTotaux() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.scale, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Poids total : ${_formatPoids(_poidsTotal)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            if (_poidsParFamille.isEmpty)
              const Text(
                'Aucun matériel dans cette liste pour le moment.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ..._poidsParFamille.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(f.nomFamille)),
                      Text(
                        _formatPoids(f.poidsGrammes),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLignes() {
    if (_lignes.isEmpty) {
      return Center(
        child: Text(
          'Appuie sur "Ajouter du matériel" pour composer ta liste.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _lignes.length,
        itemBuilder: (context, index) {
          final ligne = _lignes[index];
          final sousFamille = ligne.nomSousFamille.isEmpty
              ? ''
              : ' / ${ligne.nomSousFamille}';
          return Card(
            margin:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: Checkbox(
                value: ligne.ligne.pris,
                onChanged: (_) => _togglePris(ligne),
              ),
              title: Text(
                ligne.materiel.nom,
                style: TextStyle(
                  decoration: ligne.ligne.pris ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                '${ligne.nomFamille}$sousFamille\n'
                '${ligne.nomMarque} \u2022 ${_formatPoids(ligne.poidsTotal)} '
                '(x${ligne.ligne.quantite})',
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Réduire la quantité',
                    onPressed: () => _changerQuantite(ligne, -1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Augmenter la quantité',
                    onPressed: () => _changerQuantite(ligne, 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Retirer de la liste',
                    onPressed: () => _supprimerLigne(ligne),
                  ),
                ],
              ),
            ),
          );
        },
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
