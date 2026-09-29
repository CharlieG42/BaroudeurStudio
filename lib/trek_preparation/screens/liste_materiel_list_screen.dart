import 'package:flutter/material.dart';

import '../db/trek_preparation_database.dart';
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
