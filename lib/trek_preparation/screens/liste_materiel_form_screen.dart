import 'package:flutter/material.dart';

import '../db/trek_preparation_database.dart';
import '../models/materiel_models.dart';

/// Formulaire de creation ou d'edition d'une liste de materiel.
class ListeMaterielFormScreen extends StatefulWidget {
  final ListeMateriel? liste;

  const ListeMaterielFormScreen({super.key, this.liste});

  @override
  State<ListeMaterielFormScreen> createState() =>
      _ListeMaterielFormScreenState();
}

class _ListeMaterielFormScreenState extends State<ListeMaterielFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomController;
  late TextEditingController _notesController;
  DateTime? _dateTrek;
  bool _saving = false;

  bool get _isEdition => widget.liste != null;

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.liste?.nom ?? '');
    _notesController = TextEditingController(text: widget.liste?.notes ?? '');
    if (widget.liste != null && widget.liste!.dateTrek.isNotEmpty) {
      _dateTrek = DateTime.tryParse(widget.liste!.dateTrek);
    }
  }

  @override
  void dispose() {
    _nomController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTrek ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dateTrek = picked);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Choisir une date (optionnel)';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final liste = ListeMateriel(
      id: widget.liste?.id,
      nom: _nomController.text.trim(),
      dateTrek: _dateTrek?.toIso8601String().substring(0, 10) ?? '',
      notes: _notesController.text.trim(),
    );
    if (_isEdition) {
      await TrekPreparationDatabase.instance.updateListe(liste);
    } else {
      await TrekPreparationDatabase.instance.insertListe(liste);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdition ? 'Modifier la liste' : 'Nouvelle liste'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomController,
              decoration: const InputDecoration(
                labelText: 'Nom de la liste (ex: Trek Tour du Mont-Blanc)',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _choisirDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(_formatDate(_dateTrek)),
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
