import 'dart:async';

import 'package:flutter/material.dart';

import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../services/nominatim_service.dart';
import '../widgets/documents_etape_section.dart';

/// Formulaire d'ajout ou d'edition d'une etape. Le lieu peut etre
/// retrouve par recherche textuelle (via Nominatim/OpenStreetMap) ou
/// saisi manuellement (latitude/longitude), par exemple pour un point
/// choisi directement sur la carte.
///
/// Pour les etapes de type "visite", on peut preciser une heure
/// d'arrivee et une date/heure de depart (utile pour un sejour de
/// plusieurs jours au meme endroit).
class EtapeFormScreen extends StatefulWidget {
  final int voyageId;
  final int ordre;
  final Etape? etape;
  final double? latitudeInitiale;
  final double? longitudeInitiale;
  final String? nomInitial;

  const EtapeFormScreen({
    super.key,
    required this.voyageId,
    required this.ordre,
    this.etape,
    this.latitudeInitiale,
    this.longitudeInitiale,
    this.nomInitial,
  });

  @override
  State<EtapeFormScreen> createState() => _EtapeFormScreenState();
}

class _EtapeFormScreenState extends State<EtapeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _rechercheController = TextEditingController();
  final _notesController = TextEditingController();
  final _nominatimService = NominatimService();

  double? _latitude;
  double? _longitude;
  DateTime? _date; // date d'arrivee
  TimeOfDay? _heureArrivee;
  DateTime? _dateDepart; // null = meme jour que l'arrivee
  TimeOfDay? _heureDepart;
  TypeEtape _type = TypeEtape.visite;

  List<LieuTrouve> _resultatsRecherche = [];
  bool _recherching = false;
  String? _erreurRecherche;
  Timer? _debounce;
  // Compte les recherches lancees pour ignorer une reponse perimee
  // qui arriverait apres une recherche plus recente (evite d'ecraser
  // des resultats frais avec une reponse en retard).
  int _rechercheEnCours = 0;

  bool get _isEdition => widget.etape != null;

  @override
  void initState() {
    super.initState();
    final etape = widget.etape;
    if (etape != null) {
      _nomController.text = etape.nom;
      _notesController.text = etape.notes;
      _latitude = etape.latitude;
      _longitude = etape.longitude;
      _date = DateTime.tryParse(etape.date);
      _type = etape.type;
      _heureArrivee = _parseHeure(etape.heureArrivee);
      _heureDepart = _parseHeure(etape.heureDepart);
      if (etape.dateDepart != null) {
        _dateDepart = DateTime.tryParse(etape.dateDepart!);
      }
    } else {
      _latitude = widget.latitudeInitiale;
      _longitude = widget.longitudeInitiale;
      if (widget.nomInitial != null) {
        _nomController.text = widget.nomInitial!;
      }
    }
  }

  TimeOfDay? _parseHeure(String? valeur) {
    if (valeur == null || !valeur.contains(':')) return null;
    final parts = valeur.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String? _formatHeure(TimeOfDay? heure) {
    if (heure == null) return null;
    return '${heure.hour.toString().padLeft(2, '0')}:'
        '${heure.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nomController.dispose();
    _rechercheController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onRechercheChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _resultatsRecherche = [];
        _erreurRecherche = null;
        _recherching = false;
      });
      return;
    }
    // Respecte la politique d'usage de Nominatim (max ~1 requete/s).
    _debounce = Timer(const Duration(milliseconds: 1000), () {
      _lancerRecherche(value);
    });
  }

  Future<void> _lancerRecherche(String value) async {
    final numeroRecherche = ++_rechercheEnCours;
    setState(() {
      _recherching = true;
      _erreurRecherche = null;
    });

    try {
      final resultats = await _nominatimService.rechercherLieu(value);
      // Si une recherche plus recente a ete lancee entre-temps, on
      // ignore cette reponse pour ne pas afficher un resultat perime.
      if (!mounted || numeroRecherche != _rechercheEnCours) return;
      setState(() {
        _resultatsRecherche = resultats;
        _recherching = false;
        _erreurRecherche = resultats.isEmpty ? null : null;
      });
    } on RechercheLieuException catch (e) {
      if (!mounted || numeroRecherche != _rechercheEnCours) return;
      setState(() {
        _resultatsRecherche = [];
        _recherching = false;
        _erreurRecherche = e.message;
      });
    }
  }

  void _selectionnerLieu(LieuTrouve lieu) {
    setState(() {
      _latitude = lieu.latitude;
      _longitude = lieu.longitude;
      if (_nomController.text.trim().isEmpty) {
        _nomController.text = lieu.nomAffiche.split(',').first;
      }
      _resultatsRecherche = [];
      _erreurRecherche = null;
      _rechercheController.clear();
    });
  }

  Future<void> _choisirDateArrivee() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        // Si le depart etait avant la nouvelle date d'arrivee, on
        // l'aligne pour rester coherent.
        if (_dateDepart != null && _dateDepart!.isBefore(picked)) {
          _dateDepart = picked;
        }
      });
    }
  }

  Future<void> _choisirHeureArrivee() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _heureArrivee ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _heureArrivee = picked);
  }

  Future<void> _choisirDateDepart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateDepart ?? _date ?? DateTime.now(),
      firstDate: _date ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dateDepart = picked);
  }

  Future<void> _choisirHeureDepart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _heureDepart ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) setState(() => _heureDepart = picked);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Choisir une date';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recherche un lieu ou choisis un point sur la carte pour '
            'definir sa position.',
          ),
        ),
      );
      return;
    }
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de choisir une date d\'arrivee.')),
      );
      return;
    }

    final estVisite = _type == TypeEtape.visite;
    final dateDepartTexte = (estVisite && _dateDepart != null)
        ? _dateDepart!.toIso8601String().substring(0, 10)
        : null;

    final etape = Etape(
      id: widget.etape?.id,
      voyageId: widget.voyageId,
      ordre: widget.etape?.ordre ?? widget.ordre,
      nom: _nomController.text.trim(),
      latitude: _latitude!,
      longitude: _longitude!,
      date: _date!.toIso8601String().substring(0, 10),
      type: _type,
      notes: _notesController.text.trim(),
      heureArrivee: estVisite ? _formatHeure(_heureArrivee) : null,
      dateDepart: dateDepartTexte,
      heureDepart: estVisite ? _formatHeure(_heureDepart) : null,
    );

    if (_isEdition) {
      await TripPlannerDatabase.instance.updateEtape(etape);
    } else {
      await TripPlannerDatabase.instance.insertEtape(etape);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdition ? 'Modifier l\'etape' : 'Nouvelle etape'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _rechercheController,
              decoration: InputDecoration(
                labelText: 'Rechercher un lieu (OpenStreetMap)',
                border: const OutlineInputBorder(),
                suffixIcon: _recherching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
              ),
              onChanged: _onRechercheChanged,
            ),
            if (_erreurRecherche != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _erreurRecherche!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_recherching &&
                _erreurRecherche == null &&
                _resultatsRecherche.isEmpty &&
                _rechercheController.text.trim().length >= 3)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Aucun lieu trouve pour cette recherche.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            if (_resultatsRecherche.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 4),
                child: Column(
                  children: _resultatsRecherche
                      .map((lieu) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              lieu.nomAffiche,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectionnerLieu(lieu),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nomController,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'etape',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 8),
            if (_latitude != null && _longitude != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Position : ${_latitude!.toStringAsFixed(4)}, '
                  '${_longitude!.toStringAsFixed(4)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            SegmentedButton<TypeEtape>(
              segments: const [
                ButtonSegment(
                  value: TypeEtape.visite,
                  label: Text('Visite'),
                  icon: Icon(Icons.photo_camera_outlined),
                ),
                ButtonSegment(
                  value: TypeEtape.passage,
                  label: Text('Passage'),
                  icon: Icon(Icons.local_gas_station_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() => _type = selection.first);
              },
            ),
            const SizedBox(height: 16),
            Text('Arrivee', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _choisirDateArrivee,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formatDate(_date)),
                  ),
                ),
                if (_type == TypeEtape.visite) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _choisirHeureArrivee,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(_formatHeure(_heureArrivee) ?? 'Heure'),
                    ),
                  ),
                ],
              ],
            ),
            if (_type == TypeEtape.visite) ...[
              const SizedBox(height: 16),
              Text('Depart', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Laisse vide si le depart a lieu le meme jour.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _choisirDateDepart,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _dateDepart == null
                            ? 'Meme jour'
                            : _formatDate(_dateDepart),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _choisirHeureDepart,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(_formatHeure(_heureDepart) ?? 'Heure'),
                    ),
                  ),
                  if (_dateDepart != null)
                    IconButton(
                      tooltip: 'Revenir a "meme jour"',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _dateDepart = null),
                    ),
                ],
              ),
            ],
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
            if (_isEdition && widget.etape?.id != null) ...[
              DocumentsEtapeSection(etapeId: widget.etape!.id!),
              const SizedBox(height: 24),
            ] else ...[
              Text(
                'Tu pourras attacher des documents (billets, reservations...) '
                'une fois l\'etape enregistree.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _enregistrer,
              icon: const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
