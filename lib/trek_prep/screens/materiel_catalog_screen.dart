import 'package:flutter/material.dart';
import 'dart:io';
import '../../db/trek_prep_database.dart';
import '../../models/materiel.dart';
import '../../services/materiel_photo_storage.dart';
import 'materiel_form_screen.dart';
import 'familles_manager_screen.dart';

/// Catalogue du materiel : liste complete, regroupement par famille,
/// acces a la gestion des familles/sous-familles et des marques.
class MaterielCatalogScreen extends StatefulWidget {
  final void Function(bool)? onChanged;

  const MaterielCatalogScreen({super.key, this.onChanged});

  @override
  State<MaterielCatalogScreen> createState() => _MaterielCatalogScreenState();
}

class _MaterielCatalogScreenState extends State<MaterielCatalogScreen> {
  final _db = TrekPrepDatabase.instance;
  final _photoStorage = MaterielPhotoStorage();
  List<Materiel> _materiels = [];
  List<FamilleMateriel> _familles = [];
  List<MarqueMateriel> _marques = [];
  List<SousFamilleMateriel> _sousFamilles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final materiels = await _db.getMateriels();
    final familles = await _db.getFamilles();
    final sousFamilles = await _db.getSousFamilles();
    final marques = await _db.getMarques();
    if (!mounted) return;
    setState(() {
      _materiels = materiels;
      _familles = familles;
      _sousFamilles = sousFamilles;
      _marques = marques;
      _loading = false;
    });
  }

  String? _nomFamille(int? id) {
    if (id == null) return null;
    for (final f in _familles) {
      if (f.id == id) return f.nom;
    }
    return null;
  }

  String? _nomSousFamille(int? id) {
    if (id == null) return null;
    for (final sf in _sousFamilles) {
      if (sf.id == id) return sf.nom;
    }
    return null;
  }

  String? _nomMarque(int? id) {
    if (id == null) return null;
    for (final m in _marques) {
      if (m.id == id) return m.nom;
    }
    return null;
  }

  String _formatPoids(double g) {
    if (g >= 1000) {
      final kg = g / 1000;
      return '${kg % 1 == 0 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(2)} kg';
    }
    return '${g % 1 == 0 ? g.toStringAsFixed(0) : g.toStringAsFixed(1)} g';
  }

  Future<void> _openForm({Materiel? materiel}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MaterielFormScreen(materiel: materiel),
      ),
    );
    if (changed == true) {
      await _load();
      widget.onChanged?.call(true);
    }
  }

  Future<void> _supprimer(Materiel materiel) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce matériel ?'),
        content: Text(
          '\"${materiel.nom}\" sera definitivement supprime '
          '(il sera aussi retire des listes qui l\'utilisent).',
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
    await _photoStorage.deletePhoto(materiel.cheminPhoto);
    await _db.deleteMateriel(materiel.id!);
    await _load();
    widget.onChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    // Regroupement par famille, sans famille a la fin.
    final parFamille = <int?, List<Materiel>>{};
    for (final m in _materiels) {
      parFamille.putIfAbsent(m.familleId, () => []).add(m);
    }
    final ids = parFamille.keys.toList()
      ..sort((a, b) {
        final na = _nomFamille(a) ?? 'zzz';
        final nb = _nomFamille(b) ?? 'zzz';
        return na.toLowerCase().compareTo(nb.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matériel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Familles / sous-familles / marques',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FamillesManagerScreen(),
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.backpack_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Aucun matériel pour le moment',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ajoute tes premiers équipements pour préparer '
                        'tes treks.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      for (final id in ids)
                        _buildFamilleSection(
                          _nomFamille(id) ?? 'Sans famille',
                          parFamille[id]!,
                        ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau matériel'),
      ),
    );
  }

  Widget _buildFamilleSection(String titre, List<Materiel> materiels) {
    final total = materiels.fold<double>(
      0,
      (sum, m) => sum + m.poidsGrammes,
    );
    return Column(
      children: [
        ListTile(
          dense: true,
          title: Text(
            titre.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13,
            ),
          ),
          trailing: Text(
            '${materiels.length} · ${_formatPoids(total)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final m in materiels)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: m.cheminPhoto != null &&
                      File(m.cheminPhoto!).existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(m.cheminPhoto!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
              title: Text(
                m.nom,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                [
                  _nomMarque(m.marqueId),
                  _nomSousFamille(m.sousFamilleId),
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatPoids(m.poidsGrammes),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') {
                        _openForm(materiel: m);
                      } else if (action == 'delete') {
                        _supprimer(m);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifier')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                ],
              ),
              onTap: () => _openForm(materiel: m),
            ),
          ),
      ],
    );
  }
}
