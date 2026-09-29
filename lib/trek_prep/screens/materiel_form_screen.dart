import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../db/trek_prep_database.dart';
import '../../models/materiel.dart';
import '../../services/materiel_photo_storage.dart';

/// Formulaire de creation / edition d'un element de materiel.
class MaterielFormScreen extends StatefulWidget {
  final Materiel? materiel;

  const MaterielFormScreen({super.key, this.materiel});

  @override
  State<MaterielFormScreen> createState() => _MaterielFormScreenState();
}

class _MaterielFormScreenState extends State<MaterielFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomController;
  late TextEditingController _descriptionController;
  late TextEditingController _poidsController;

  List<FamilleMateriel> _familles = [];
  List<SousFamilleMateriel> _sousFamilles = [];
  List<MarqueMateriel> _marques = [];

  FamilleMateriel? _famille;
  SousFamilleMateriel? _sousFamille;
  MarqueMateriel? _marque;
  String? _cheminPhoto;
  bool _saving = false;

  bool get _isEdition => widget.materiel != null;
  final _photoStorage = MaterielPhotoStorage();
  final _db = TrekPrepDatabase.instance;

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.materiel?.nom ?? '');
    _descriptionController =
        TextEditingController(text: widget.materiel?.description ?? '');
    _poidsController = TextEditingController(
      text: widget.materiel == null
          ? ''
          : _formatPoids(widget.materiel!.poidsGrammes),
    );
    _cheminPhoto = widget.materiel?.cheminPhoto;
    _loadData();
  }

  String _formatPoids(double g) {
    if (g >= 1000 && g % 1000 == 0) {
      return (g / 1000).toStringAsFixed(0);
    }
    final s = g % 1 == 0 ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
    return s;
  }

  Future<void> _loadData() async {
    final familles = await _db.getFamilles();
    final sousFamilles = await _db.getSousFamilles();
    final marques = await _db.getMarques();
    if (!mounted) return;
    setState(() {
      _familles = familles;
      _sousFamilles = sousFamilles;
      _marques = marques;
      if (_isEdition) {
        _famille = familles.where((f) => f.id == widget.materiel!.familleId)
            .firstOrNull;
        _sousFamille = sousFamilles
            .where((sf) => sf.id == widget.materiel!.sousFamilleId)
            .firstOrNull;
        _marque = marques
            .where((m) => m.id == widget.materiel!.marqueId)
            .firstOrNull;
      }
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    _descriptionController.dispose();
    _poidsController.dispose();
    super.dispose();
  }

  Future<void> _choisirPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final source = result?.files.single.path;
    if (source == null) return;
    // Si on remplace la photo d'un materiel existant, on supprime
    // l'ancienne copie.
    if (_cheminPhoto != null && _cheminPhoto != widget.materiel?.cheminPhoto) {
      await _photoStorage.deletePhoto(_cheminPhoto);
    }
    final chemin = await _photoStorage.copyPhoto(source);
    if (!mounted) return;
    setState(() => _cheminPhoto = chemin);
  }

  Future<void> _retirerPhoto() async {
    if (_cheminPhoto != null &&
        _cheminPhoto != widget.materiel?.cheminPhoto) {
      await _photoStorage.deletePhoto(_cheminPhoto);
    }
    setState(() => _cheminPhoto = null);
  }

  /// Dialogue de saisie d'une nouvelle entree (marque ou famille).
  Future<String?> _promptNouvelleEntite(String titre, String libelle) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: libelle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _nouvelleMarque() async {
    final nom = await _promptNouvelleEntite('Nouvelle marque', 'Nom de la marque');
    if (nom == null || nom.isEmpty) return;
    final id = await _db.insertMarque(MarqueMateriel(nom: nom));
    final marque = MarqueMateriel(id: id, nom: nom);
    if (!mounted) return;
    setState(() {
      _marques = [..._marques, marque]..sort(
          (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
      _marque = marque;
    });
  }

  Future<void> _nouvelleFamille() async {
    final nom = await _promptNouvelleEntite(
        'Nouvelle famille', 'Nom de la famille');
    if (nom == null || nom.isEmpty) return;
    final id = await _db.insertFamille(FamilleMateriel(nom: nom));
    final famille = FamilleMateriel(id: id, nom: nom);
    if (!mounted) return;
    setState(() {
      _familles = [..._familles, famille]..sort(
          (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
      _famille = famille;
      _sousFamille = null;
    });
  }

  Future<void> _nouvelleSousFamille() async {
    if (_famille == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisis d\'abord une famille.'),
        ),
      );
      return;
    }
    final nom = await _promptNouvelleEntite(
        'Nouvelle sous-famille', 'Nom de la sous-famille');
    if (nom == null || nom.isEmpty) return;
    final id = await _db.insertSousFamille(
      SousFamilleMateriel(familleId: _famille!.id!, nom: nom),
    );
    final sousFamille = SousFamilleMateriel(id: id, familleId: _famille!.id!, nom: nom);
    if (!mounted) return;
    setState(() {
      _sousFamilles = [..._sousFamilles, sousFamille]..sort(
          (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
      _sousFamille = sousFamille;
    });
  }

  List<SousFamilleMateriel> get _sousFamillesDeFamille => _sousFamilles
      .where((sf) => sf.familleId == _famille?.id)
      .toList();

  double? _parsePoids() {
    final texte = _poidsController.text.trim().replaceAll(',', '.');
    if (texte.isEmpty) return 0;
    return double.tryParse(texte);
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    final poids = _parsePoids();
    if (poids == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poids invalide.')),
      );
      return;
    }
    setState(() => _saving = true);
    final materiel = Materiel(
      id: widget.materiel?.id,
      nom: _nomController.text.trim(),
      marqueId: _marque?.id,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      poidsGrammes: poids,
      familleId: _famille?.id,
      sousFamilleId: _sousFamille?.id,
      cheminPhoto: _cheminPhoto,
    );
    if (_isEdition) {
      await _db.updateMateriel(materiel);
    } else {
      await _db.insertMateriel(materiel);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _supprimer() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce matériel ?'),
        content: Text(
          '\"${widget.materiel!.nom}\" sera definitivement supprime '
          'de la base de materiel.',
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
    await _photoStorage.deletePhoto(widget.materiel!.cheminPhoto);
    await _db.deleteMateriel(widget.materiel!.id!);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdition ? 'Modifier le matériel' : 'Nouveau matériel'),
        actions: [
          if (_isEdition)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
              onPressed: _supprimer,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPhoto(),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _nomController,
                    decoration: const InputDecoration(
                      labelText: 'Nom *',
                      hintText: 'Ex : Tente 2 places',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nom obligatoire' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<MarqueMateriel>(
              value: _marque,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Marque',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Nouvelle marque',
                  onPressed: _nouvelleMarque,
                ),
              ),
              items: [
                for (final m in _marques)
                  DropdownMenuItem(value: m, child: Text(m.nom)),
              ],
              onChanged: (m) => setState(() => _marque = m),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _poidsController,
              decoration: const InputDecoration(
                labelText: 'Poids (grammes)',
                hintText: 'Ex : 1850',
                suffixText: 'g',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<FamilleMateriel>(
              value: _famille,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Famille',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Nouvelle famille',
                  onPressed: _nouvelleFamille,
                ),
              ),
              items: [
                for (final f in _familles)
                  DropdownMenuItem(value: f, child: Text(f.nom)),
              ],
              onChanged: (f) => setState(() {
                _famille = f;
                if (_sousFamille?.familleId != f?.id) {
                  _sousFamille = null;
                }
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SousFamilleMateriel>(
              value: _sousFamille,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Sous-famille',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Nouvelle sous-famille',
                  onPressed: _nouvelleSousFamille,
                ),
              ),
              items: [
                for (final sf in _sousFamillesDeFamille)
                  DropdownMenuItem(value: sf, child: Text(sf.nom)),
              ],
              onChanged: (sf) => setState(() => _sousFamille = sf),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _enregistrer,
              icon: const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    return Column(
      children: [
        GestureDetector(
          onTap: _choisirPhoto,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: _cheminPhoto != null && File(_cheminPhoto!).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_cheminPhoto!),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.add_a_photo_outlined, size: 32),
          ),
        ),
        if (_cheminPhoto != null)
          TextButton.icon(
            onPressed: _retirerPhoto,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Retirer', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
