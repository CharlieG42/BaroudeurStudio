import 'package:flutter/material.dart';

import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../services/osrm_service.dart';

/// Formulaire d'edition du trajet entre deux etapes consecutives.
/// - Modes "voiture"/"velo"/"marche" : recalcules automatiquement via
///   OSRM (rien a saisir), chacun avec son propre profil de routage.
/// - Modes "avion"/"train"/"bus"/"autre" : saisie manuelle
///   (transporteur, lieux, heures), jamais ecrases par le recalcul
///   automatique.
class TransfertFormScreen extends StatefulWidget {
  final int voyageId;
  final Etape etapeDepart;
  final Etape etapeArrivee;
  final Trajet? trajetExistant;

  const TransfertFormScreen({
    super.key,
    required this.voyageId,
    required this.etapeDepart,
    required this.etapeArrivee,
    this.trajetExistant,
  });

  @override
  State<TransfertFormScreen> createState() => _TransfertFormScreenState();
}

class _TransfertFormScreenState extends State<TransfertFormScreen> {
  late ModeTransport _mode;
  final _transporteurController = TextEditingController();
  final _lieuDepartController = TextEditingController();
  final _lieuArriveeController = TextEditingController();
  final _notesController = TextEditingController();
  final _osrmService = OsrmService();
  TimeOfDay? _heureDepart;
  TimeOfDay? _heureArrivee;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    final t = widget.trajetExistant;
    _mode = t?.mode ?? ModeTransport.voiture;
    _transporteurController.text = t?.transporteur ?? '';
    _lieuDepartController.text = t?.lieuDepart ?? widget.etapeDepart.nom;
    _lieuArriveeController.text = t?.lieuArrivee ?? widget.etapeArrivee.nom;
    _heureDepart = _parseHeure(t?.heureDepart);
    _heureArrivee = _parseHeure(t?.heureArrivee);
    _notesController.text = t?.notes ?? '';
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
    _transporteurController.dispose();
    _lieuDepartController.dispose();
    _lieuArriveeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _choisirHeureDepart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _heureDepart ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _heureDepart = picked);
  }

  Future<void> _choisirHeureArrivee() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _heureArrivee ?? const TimeOfDay(hour: 11, minute: 0),
    );
    if (picked != null) setState(() => _heureArrivee = picked);
  }

  /// Duree en minutes entre les deux heures si les deux sont
  /// renseignees (suppose un transfert dans la meme journee ou le
  /// lendemain si l'heure d'arrivee est plus tot que celle de depart).
  int _dureeEstimee() {
    if (_heureDepart == null || _heureArrivee == null) return 0;
    final depart = _heureDepart!.hour * 60 + _heureDepart!.minute;
    var arrivee = _heureArrivee!.hour * 60 + _heureArrivee!.minute;
    if (arrivee < depart) arrivee += 24 * 60;
    return arrivee - depart;
  }

  Future<void> _enregistrer() async {
    if (widget.etapeDepart.id == null || widget.etapeArrivee.id == null) {
      return;
    }
    setState(() => _enregistrement = true);
    final db = TripPlannerDatabase.instance;

    if (_mode.estAutoCalcule) {
      // Calcule immediatement via OSRM avec le profil du mode choisi,
      // pour un retour visuel des l'enregistrement plutot que d'attendre
      // le prochain "Recalculer les trajets".
      final resultat = await _osrmService.calculerItineraire(
        mode: _mode,
        latDepart: widget.etapeDepart.latitude,
        lonDepart: widget.etapeDepart.longitude,
        latArrivee: widget.etapeArrivee.latitude,
        lonArrivee: widget.etapeArrivee.longitude,
      );

      if (resultat != null) {
        await db.upsertTrajet(Trajet(
          voyageId: widget.voyageId,
          etapeDepartId: widget.etapeDepart.id!,
          etapeArriveeId: widget.etapeArrivee.id!,
          mode: _mode,
          distanceKm: resultat.distanceKm,
          dureeMinutes: resultat.dureeMinutes,
          geometrieJson: Trajet.encodePoints(resultat.points),
        ));
      } else if (widget.trajetExistant?.id != null) {
        // Echec du calcul (reseau...) : on retire l'ancien trajet plutot
        // que de laisser une valeur perimee ; la timeline affichera
        // "trajet non calcule" et l'icone "Recalculer" permettra de
        // reessayer plus tard.
        await db.deleteTrajet(widget.trajetExistant!.id!);
      }
    } else {
      await db.upsertTrajet(Trajet(
        voyageId: widget.voyageId,
        etapeDepartId: widget.etapeDepart.id!,
        etapeArriveeId: widget.etapeArrivee.id!,
        mode: _mode,
        distanceKm: 0,
        dureeMinutes: _dureeEstimee(),
        geometrieJson: '[]',
        transporteur: _transporteurController.text.trim().isEmpty
            ? null
            : _transporteurController.text.trim(),
        lieuDepart: _lieuDepartController.text.trim(),
        lieuArrivee: _lieuArriveeController.text.trim(),
        heureDepart: _formatHeure(_heureDepart),
        heureArrivee: _formatHeure(_heureArrivee),
        notes: _notesController.text.trim(),
      ));
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _libelleMode(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return 'Voiture';
      case ModeTransport.velo:
        return 'Velo';
      case ModeTransport.marche:
        return 'Marche';
      case ModeTransport.avion:
        return 'Avion';
      case ModeTransport.train:
        return 'Train';
      case ModeTransport.bus:
        return 'Bus';
      case ModeTransport.autre:
        return 'Autre';
    }
  }

  IconData _iconeMode(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return Icons.directions_car_outlined;
      case ModeTransport.velo:
        return Icons.directions_bike_outlined;
      case ModeTransport.marche:
        return Icons.directions_walk_outlined;
      case ModeTransport.avion:
        return Icons.flight_outlined;
      case ModeTransport.train:
        return Icons.train_outlined;
      case ModeTransport.bus:
        return Icons.directions_bus_outlined;
      case ModeTransport.autre:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.etapeDepart.nom} → ${widget.etapeArrivee.nom}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Moyen de transport',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ModeTransport.values.map((mode) {
              return ChoiceChip(
                label: Text(_libelleMode(mode)),
                avatar: Icon(_iconeMode(mode), size: 18),
                selected: _mode == mode,
                onSelected: (_) => setState(() => _mode = mode),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_mode.estAutoCalcule)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Le trajet sera calcule automatiquement '
                  '(${_libelleMode(_mode).toLowerCase()}) : distance, '
                  'duree et trace, des l\'enregistrement.',
                ),
              ),
            )
          else ...[
            TextFormField(
              controller: _transporteurController,
              decoration: InputDecoration(
                labelText: _mode == ModeTransport.avion
                    ? 'Compagnie / numero de vol (optionnel)'
                    : 'Transporteur / numero (optionnel)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lieuDepartController,
              decoration: const InputDecoration(
                labelText: 'Lieu de depart (ex: aeroport, gare)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lieuArriveeController,
              decoration: const InputDecoration(
                labelText: 'Lieu d\'arrivee',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _choisirHeureDepart,
                    icon: const Icon(Icons.access_time, size: 18),
                    label:
                        Text(_formatHeure(_heureDepart) ?? 'Heure de depart'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _choisirHeureArrivee,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(
                        _formatHeure(_heureArrivee) ?? 'Heure d\'arrivee'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (reference reservation, terminal...)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _enregistrement ? null : _enregistrer,
            icon: _enregistrement
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
    );
  }
}
