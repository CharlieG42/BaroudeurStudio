import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db/trek_preparation_database.dart';
import '../models/materiel_models.dart';
import '../services/materiel_photo_storage_service.dart';

/// Formulaire de creation ou d'edition d'un materiel du catalogue :
/// nom, marque, description, poids, famille, sous-famille et photo.
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
  List<Famille> _familles = [];
  List<SousFamille> _sousFamilles = [];
  List<Marque> _marques = [];
  Famille? _famille;
  SousFamille? _sousFamille;
  Marque? _marque;
  String _photoPath = '';
  bool _saving = false;
  final _photoStorage = MaterielPhotoStorageService();

  bool get _isEdition => widget.materiel != null;

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.materiel?.nom ?? '');
    _descriptionController =
        TextEditingController(text: widget.materiel?.description ?? '');
    _poidsController = TextEditingController(
      text: widget.materiel == null
          ? ''
          : (widget.materiel!.poidsGrammes % 1 == 0
              ? widget.materiel!.poidsGrammes.toInt().toString()
              : widget.materiel!.poidsGrammes.toString()),
    );
    _photoPath = widget.materiel?.photoPath ?? '';
    _loadReferences();
  }

  Future<void> _loadReferences() async {
    final db = TrekPreparationDatabase.instance;
    final familles = await db.getFamilles();
    final sousFamilles = await db.getAllSousFamilles();
    final marques = await db.getMarques();
    if (!mounted) return;
    setState(() {
      _familles = familles;
      _sousFamilles = sousFamilles;
      _marques = marques;
      if (_isEdition) {
        _famille = familles.where((f) => f.id == widget.materiel!.familleId).firstOrNull;
        _sousFamille = sousFamilles
            .where((sf) => sf.id == widget.materiel!.sousFamilleId)
            .firstOrNull;
        _marque = marques.where((m) => m.id == widget.materiel!.marqueId).firstOrNull;
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
    if (result == null || result.files.single.path == null) return;
    final newPath = await _photoStorage.copierPhoto(result.files.single.path!);
    if (_photoPath.isNotEmpty) {
      await _photoStorage.supprimerPhoto(_photoPath);
    }
    setState(() => _photoPath = newPath);
  }

  Future<Marque?> _choisirOuCreerMarque() async {
    final db = TrekPreparationDatabase.instance;
    final marques = await db.getMarques();
    final marqueExistante = await showDialog<Marque>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marque'),
        content: SizedBox(
          width: double.maxFinite,
          child: marques.isEmpty
              ? const Text('Aucune marque. Crée-en une nouvelle.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    ...marques.map(
                      (m) => ListTile(
                        title: Text(m.nom),
                        onTap: () => Navigator.pop(context, m),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, Marque(id: -1)),
            child: const Text('Nouvelle marque'),
          ),
        ],
      ),
    );
    if (marqueExistante == null) return null;
    if (marqueExistante.id != -1) return marqueExistante;
    return _saisirNouvelleMarque();
  }

  Future<Marque?> _saisirNouvelleMarque() async {
    final controller = TextEditingController();
    final nom = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle marque'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom de la marque',
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
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (nom == null || nom.isEmpty) return null;
    final db = TrekPreparationDatabase.instance;
    final id = await db.insertMarque(Marque(nom: nom));
    final marque = Marque(id: id, nom: nom);
    setState(() {
      _marques = [..._marques, marque]..sort((a, b) => a.nom.compareTo(b.nom));
    });
    return marque;
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_famille == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de choisir une famille.')),
      );
      return;
    }
    if (_marque == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de choisir ou créer une marque.')),
      );
      return;
    }
    setState(() => _saving = true);
    final materiel = Materiel(
      id: widget.materiel?.id,
      nom: _nomController.text.trim(),
      marqueId: _marque!.id!,
      description: _descriptionController.text.trim(),
      poidsGrammes: double.tryParse(_poidsController.text.trim()) ?? 0,
      familleId: _famille!.id!,
      sousFamilleId: _sousFamille?.id,
      photoPath: _photoPath,
    );
    if (_isEdition) {
      await TrekPreparationDatabase.instance.updateMateriel(materiel);
    } else {
      await TrekPreparationDatabase.instance.insertMateriel(materiel);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final sousFamillesFamille = _famille == null
        ? <SousFamille>[]
        : _sousFamilles.where((sf) => sf.familleId == _famille!.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdition ? 'Modifier le matériel' : 'Nouveau matériel'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomController,
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Famille>(
              value: _famille,
              decoration: const InputDecoration(
                labelText: 'Famille',
                border: OutlineInputBorder(),
              ),
              items: _familles
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.nom)))
                  .toList(),
              onChanged: (f) => setState(() {
                _famille = f;
                _sousFamille = null;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SousFamille>(
              value: _sousFamille,
              decoration: const InputDecoration(
                labelText: 'Sous-famille (optionnel)',
                border: OutlineInputBorder(),
              ),
              items: [
                ...sousFamillesFamille.map(
                  (sf) => DropdownMenuItem(value: sf, child: Text(sf.nom)),
                ),
              ],
              onChanged: (sf) => setState(() => _sousFamille = sf),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final marque = await _choisirOuCreerMarque();
                if (marque != null) {
                  setState(() => _marque = marque);
                }
              },
              icon: const Icon(Icons.sell_outlined),
              label: Text(_marque?.nom ?? 'Choisir ou créer une marque'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _poidsController,
              decoration: const InputDecoration(
                labelText: 'Poids (en grammes)',
                border: OutlineInputBorder(),
                suffixText: 'g',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (double.tryParse(v.trim()) == null) {
                  return 'Poids invalide';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_photoPath.isNotEmpty)
                  CircleAvatar(
                    radius: 32,
                    backgroundImage: FileImage(File(_photoPath)),
                    onBackgroundImageError: (_, __) {},
                  )
                else
                  const CircleAvatar(
                    radius: 32,
                    child: Icon(Icons.photo_camera_outlined),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _choisirPhoto,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _photoPath.isEmpty
                          ? 'Choisir une photo'
                          : 'Changer la photo',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _enregistrer,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
