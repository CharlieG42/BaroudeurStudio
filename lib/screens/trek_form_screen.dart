import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/trek.dart';

class TrekFormScreen extends StatefulWidget {
  final Trek? trek; // si non-null, on est en mode édition

  const TrekFormScreen({super.key, this.trek});

  @override
  State<TrekFormScreen> createState() => _TrekFormScreenState();
}

class _TrekFormScreenState extends State<TrekFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titreCtrl;
  late TextEditingController _regionCtrl;
  late TextEditingController _paysCtrl;
  late TextEditingController _distanceCtrl;
  late TextEditingController _deniveleCtrl;
  late TextEditingController _modeVoyageCtrl;
  late TextEditingController _compagnonsCtrl;

  DateTime? _dateDebut;
  DateTime? _dateFin;

  bool get _isEditing => widget.trek != null;

  @override
  void initState() {
    super.initState();
    final trek = widget.trek;
    _titreCtrl = TextEditingController(text: trek?.titre ?? '');
    _regionCtrl = TextEditingController(text: trek?.region ?? '');
    _paysCtrl = TextEditingController(text: trek?.pays ?? 'France');
    _distanceCtrl = TextEditingController(
      text: trek?.distanceKm != null ? trek!.distanceKm.toString() : '',
    );
    _deniveleCtrl = TextEditingController(
      text: trek?.denivelePositifM != null
          ? trek!.denivelePositifM.toString()
          : '',
    );
    _modeVoyageCtrl = TextEditingController(text: trek?.modeVoyage ?? '');
    _compagnonsCtrl = TextEditingController(text: trek?.compagnons ?? '');

    if (trek != null) {
      _dateDebut = DateTime.tryParse(trek.dateDebut);
      _dateFin = DateTime.tryParse(trek.dateFin);
    }
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _regionCtrl.dispose();
    _paysCtrl.dispose();
    _distanceCtrl.dispose();
    _deniveleCtrl.dispose();
    _modeVoyageCtrl.dispose();
    _compagnonsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isDebut}) async {
    final initial = isDebut
        ? (_dateDebut ?? DateTime.now())
        : (_dateFin ?? _dateDebut ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isDebut) {
          _dateDebut = picked;
          // Si la date de fin est avant la date de début, on l'ajuste
          if (_dateFin != null && _dateFin!.isBefore(picked)) {
            _dateFin = picked;
          }
        } else {
          _dateFin = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_dateDebut == null || _dateFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de renseigner les dates de début et de fin.')),
      );
      return;
    }

    final trek = Trek(
      id: widget.trek?.id,
      titre: _titreCtrl.text.trim(),
      dateDebut: _dateDebut!,
      dateFin: _dateFin!,
      region: _regionCtrl.text.trim(),
      pays: _paysCtrl.text.trim(),
      distanceKm: _distanceCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_distanceCtrl.text.trim().replaceAll(',', '.')),
      denivelePositifM: _deniveleCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(_deniveleCtrl.text.trim()),
      modeVoyage: _modeVoyageCtrl.text.trim(),
      compagnons: _compagnonsCtrl.text.trim(),
    );

    if (_isEditing) {
      await DatabaseHelper.instance.updateTrek(trek);
    } else {
      await DatabaseHelper.instance.insertTrek(trek);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  String _displayDate(DateTime? date) {
    if (date == null) return 'Sélectionner une date';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier le trek' : 'Nouveau trek'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titreCtrl,
              decoration: const InputDecoration(
                labelText: 'Titre du trek *',
                hintText: 'ex: Le Queyras en solo',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Le titre est requis' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Debut: ${_displayDate(_dateDebut)}'),
                    onPressed: () => _pickDate(isDebut: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Fin: ${_displayDate(_dateFin)}'),
                    onPressed: () => _pickDate(isDebut: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _regionCtrl,
              decoration: const InputDecoration(
                labelText: 'Région *',
                hintText: 'ex: Queyras',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'La région est requise' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _paysCtrl,
              decoration: const InputDecoration(
                labelText: 'Pays *',
                hintText: 'ex: France',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Le pays est requis' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _distanceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Distance totale (km)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _deniveleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dénivelé + (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _modeVoyageCtrl,
              decoration: const InputDecoration(
                labelText: 'Mode de voyage',
                hintText: 'ex: À pied, Vélo, Mixte...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _compagnonsCtrl,
              decoration: const InputDecoration(
                labelText: 'Compagnons de voyage',
                hintText: 'ex: Solo, ou noms séparés par des virgules',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
