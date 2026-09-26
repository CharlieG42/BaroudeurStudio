import 'package:flutter/material.dart';

import '../db/trip_planner_database.dart';
import '../models/voyage.dart';

/// Formulaire de creation ou d'edition d'un voyage.
class VoyageFormScreen extends StatefulWidget {
  final Voyage? voyage;

  const VoyageFormScreen({super.key, this.voyage});

  @override
  State<VoyageFormScreen> createState() => _VoyageFormScreenState();
}

class _VoyageFormScreenState extends State<VoyageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titreController;
  late TextEditingController _notesController;
  DateTime? _dateDebut;
  DateTime? _dateFin;
  bool _saving = false;

  bool get _isEdition => widget.voyage != null;

  @override
  void initState() {
    super.initState();
    _titreController = TextEditingController(text: widget.voyage?.titre ?? '');
    _notesController = TextEditingController(text: widget.voyage?.notes ?? '');
    if (widget.voyage != null) {
      _dateDebut = DateTime.tryParse(widget.voyage!.dateDebut);
      _dateFin = DateTime.tryParse(widget.voyage!.dateFin);
    }
  }

  @override
  void dispose() {
    _titreController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _choisirDate({required bool debut}) async {
    final initial = debut
        ? (_dateDebut ?? DateTime.now())
        : (_dateFin ?? _dateDebut ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (debut) {
          _dateDebut = picked;
        } else {
          _dateFin = picked;
        }
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Choisir une date';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateDebut == null || _dateFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de renseigner les deux dates.')),
      );
      return;
    }

    setState(() => _saving = true);

    final voyage = Voyage(
      id: widget.voyage?.id,
      titre: _titreController.text.trim(),
      dateDebut: _dateDebut!.toIso8601String().substring(0, 10),
      dateFin: _dateFin!.toIso8601String().substring(0, 10),
      notes: _notesController.text.trim(),
    );

    if (_isEdition) {
      await TripPlannerDatabase.instance.updateVoyage(voyage);
    } else {
      await TripPlannerDatabase.instance.insertVoyage(voyage);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _supprimer() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce voyage ?'),
        content: Text(
          'Toutes les etapes, trajets et documents attaches a '
          '"${widget.voyage!.titre}" seront definitivement supprimes. '
          'Cette action est irreversible.',
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

    await TripPlannerDatabase.instance.deleteVoyage(widget.voyage!.id!);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdition ? 'Modifier le voyage' : 'Nouveau voyage'),
        actions: [
          if (_isEdition)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer ce voyage',
              onPressed: _supprimer,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titreController,
              decoration: const InputDecoration(
                labelText: 'Titre du voyage',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _choisirDate(debut: true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_formatDate(_dateDebut)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _choisirDate(debut: false),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_formatDate(_dateFin)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optionnel)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
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
