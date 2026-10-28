import 'dart:async';

import 'package:flutter/material.dart';

import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../services/insertion_etape_service.dart';
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
  final int? parentId;
  final String? dateMinAutorisee; // borne basse du calendrier (ISO)
  final String? dateMaxAutorisee; // borne haute du calendrier (ISO)

  /// Etapes du voyage. Si fournie pour une creation sans [parentId]
  /// impose (clic sur la carte, bouton "Ajouter une etape", recherche),
  /// le formulaire propose de rattacher la nouvelle etape a une etape
  /// visite existante pour en faire une sous-etape.
  final List<Etape> etapesVoyage;

  const EtapeFormScreen({
    super.key,
    required this.voyageId,
    required this.ordre,
    this.etape,
    this.latitudeInitiale,
    this.longitudeInitiale,
    this.nomInitial,
    this.parentId,
    this.dateMinAutorisee,
    this.dateMaxAutorisee,
    this.etapesVoyage = const [],
  });

  @override
  State<EtapeFormScreen> createState() => _EtapeFormScreenState();
}

class _EtapeFormScreenState extends State<EtapeFormScreen> {
  /// Etape parente choisie dans le formulaire (ou imposee par
  /// [EtapeFormScreen.parentId]). null = etape principale.
  int? _parentId;

  /// Le choix de l'etape parente n'est propose qu'a la creation, quand
  /// aucun parent n'est impose et qu'il existe au moins une visite.
  bool get _choixParentPossible =>
      !_isEdition && widget.parentId == null && _parentsPossibles.isNotEmpty;

  /// Etapes pouvant recevoir des sous-etapes : etapes principales de
  /// type visite deja enregistrees (meme regle que le bouton +).
  List<Etape> get _parentsPossibles => widget.etapesVoyage
      .where((e) =>
          e.parentId == null && e.type == TypeEtape.visite && e.id != null)
      .toList()
    ..sort((a, b) => a.ordre.compareTo(b.ordre));

  /// Parente choisie via le selecteur du formulaire, null sinon.
  Etape? get _parenteChoisie => _choixParentPossible && _parentId != null
      ? _parentsPossibles.where((e) => e.id == _parentId).firstOrNull
      : null;

  /// Bornes du calendrier : dates du voyage pour une etape racine,
  /// creneau de l'etape parente pour une sous-etape.
  DateTime get _dateMin =>
      DateTime.tryParse(_parenteChoisie?.date ?? widget.dateMinAutorisee ?? '') ??
      DateTime(2020);
  DateTime get _dateMax =>
      DateTime.tryParse(_parenteChoisie?.dateDepartEffective ??
          widget.dateMaxAutorisee ??
          '') ??
      DateTime(2100);

  /// La date d'arrivee doit rester dans le creneau autorise.
  bool _dateHorsCreneau(DateTime d) =>
      d.isBefore(_dateMin) || d.isAfter(_dateMax);

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
  int? _decalageHoraireHeures;
  bool _decalagePositif = true;

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
    _parentId = widget.etape?.parentId ?? widget.parentId;
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
      final decalage = etape.decalageHoraireMinutes;
      if (decalage != null) {
        _decalagePositif = decalage >= 0;
        _decalageHoraireHeures = (decalage.abs() / 60).round();
      }
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

  int? _decalageHoraireEnMinutes() {
    if (_decalageHoraireHeures == null) return null;
    final valeur = _decalageHoraireHeures! * 60;
    return _decalagePositif ? valeur : -valeur;
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
    final horsBornes = _date != null && _dateHorsCreneau(_date!);
    DateTime initiale;
    if (horsBornes) {
      initiale = _dateMin;
    } else if (_date != null) {
      initiale = _date!;
    } else {
      final maintenant = DateTime.now();
      initiale = maintenant.isBefore(_dateMin) || maintenant.isAfter(_dateMax)
          ? _dateMin
          : maintenant;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initiale.isAfter(_dateMax) ? _dateMin : initiale,
      firstDate: _dateMin,
      lastDate: _dateMax,
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
      initialDate: _dateDepart ?? _date ?? _dateMin,
      firstDate: _date ?? _dateMin,
      lastDate: _dateMax,
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
    if (_dateHorsCreneau(_date!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _parentId != null
                ? 'La date doit rester dans le creneau de l\'etape visite.'
                : 'La date doit rester dans les dates du voyage.',
          ),
        ),
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
      ordre: widget.etape?.ordre ?? _ordrePourCreation(),
      nom: _nomController.text.trim(),
      latitude: _latitude!,
      longitude: _longitude!,
      date: _date!.toIso8601String().substring(0, 10),
      type: _type,
      notes: _notesController.text.trim(),
      heureArrivee: estVisite ? _formatHeure(_heureArrivee) : null,
      dateDepart: dateDepartTexte,
      heureDepart: estVisite ? _formatHeure(_heureDepart) : null,
      decalageHoraireMinutes: _decalageHoraireEnMinutes(),
      parentId: _parentId,
    );

    if (_isEdition) {
      await TripPlannerDatabase.instance.updateEtape(etape);
    } else if (etape.parentId != null) {
      await TripPlannerDatabase.instance.insertEtape(etape);
    } else {
      // Insertion intelligente : l'etape se place a sa date, pas en fin
      // de liste, et les ordres sont renumerotes.
      final db = TripPlannerDatabase.instance;
      final id = await db.insertEtape(etape);
      await InsertionEtapeService.insererIntelligent(
          etape.copyWith(id: id));
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  /// Ordre d'une nouvelle etape : celui fourni par l'appelant, ou la
  /// fin de la liste des sous-etapes si une parente a ete choisie dans
  /// le formulaire.
  int _ordrePourCreation() {
    final parente = _parenteChoisie;
    if (parente == null) return widget.ordre;
    return widget.etapesVoyage.where((e) => e.parentId == parente.id).length;
  }

  void _changerParent(int? parentId) {
    setState(() {
      _parentId = parentId;
      // La date doit rester dans le creneau de la nouvelle parente
      // (ou du voyage si on revient a une etape principale).
      if (_date != null && _dateHorsCreneau(_date!)) {
        _date = _parenteChoisie != null ? _dateMin : null;
      } else if (_date == null && _parenteChoisie != null) {
        // Pre-remplit avec le jour d'arrivee de la visite.
        _date = _dateMin;
      }
      if (_dateDepart != null &&
          (_dateDepart!.isAfter(_dateMax) ||
              (_date != null && _dateDepart!.isBefore(_date!)))) {
        _dateDepart = null;
      }
    });
  }

  String _libelleParente(Etape e) {
    final arrivee = DateTime.tryParse(e.date);
    final depart = DateTime.tryParse(e.dateDepartEffective);
    String court(DateTime? d) => d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}';
    final periode = e.dateDepartEffective == e.date
        ? court(arrivee)
        : '${court(arrivee)} → ${court(depart)}';
    return periode.isEmpty ? e.nom : '${e.nom} ($periode)';
  }

  Widget _buildChoixParent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int?>(
            initialValue: _parentId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Etape parente',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Aucune (etape principale)'),
              ),
              for (final e in _parentsPossibles)
                DropdownMenuItem<int?>(
                  value: e.id,
                  child: Text(
                    _libelleParente(e),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _changerParent,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _parentId == null
                  ? 'Choisis une visite pour en faire une sous-etape.'
                  : 'Sous-etape : la date est limitee au sejour de la visite.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdition
              ? 'Modifier l\'etape'
              : (_parentId != null
                  ? 'Nouvelle sous-etape'
                  : 'Nouvelle etape'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_choixParentPossible) _buildChoixParent(),
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
            Row(
              children: [
                const Icon(Icons.public, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Decalage horaire de l\'etape par rapport a '
                    'l\'heure de reference du voyage',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: _decalageHoraireHeures,
                    hint: const Text('Aucun'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Aucun'),
                      ),
                      for (var h = 1; h <= 14; h++)
                        DropdownMenuItem<int?>(
                          value: h,
                          child: Text(
                            _decalagePositif ? 'UTC+$h' : 'UTC-$h',
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _decalageHoraireHeures = v),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('+'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('-'),
                    ),
                  ],
                  selected: {_decalagePositif},
                  onSelectionChanged: (selection) =>
                      setState(() => _decalagePositif = selection.first),
                ),
              ],
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
