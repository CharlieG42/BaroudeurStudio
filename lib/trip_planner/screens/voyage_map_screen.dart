import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../models/voyage.dart';
import '../models/waypoint.dart';
import '../services/nominatim_service.dart';
import '../services/trip_calculation_service.dart';
import '../services/geolocalisation_service.dart';
import '../services/tuiles_hors_ligne_service.dart';
import '../services/waypoint_suggestion_service.dart';
import 'etape_form_screen.dart';
import '../widgets/profil_altitude_chart.dart';
import 'transfert_form_screen.dart';
import 'parametres_planification_screen.dart';
import 'voyage_form_screen.dart';

/// Disposition de l'ecran : carte seule en plein ecran, liste des
/// etapes seule en plein ecran, ou les deux partagees (comportement
/// par defaut).
enum ModeAffichage { carte, liste, partage }

/// Fond de carte affiche. L'IGN ne couvre que le territoire francais
/// (metropole + outre-mer) : hors de cette zone, les tuiles IGN seront
/// vides, OpenStreetMap reste alors le bon choix.
enum FondCarte { osm, ignPlan, ignPhoto }

/// Ecran principal du module de planification : carte OpenStreetMap
/// avec les etapes et les trajets routiers, plus la liste chronologique
/// des etapes juste en dessous (timeline jour par jour).
class VoyageMapScreen extends StatefulWidget {
  final Voyage voyage;

  const VoyageMapScreen({super.key, required this.voyage});

  @override
  State<VoyageMapScreen> createState() => _VoyageMapScreenState();
}

class _VoyageMapScreenState extends State<VoyageMapScreen> {
  final MapController _mapController = MapController();
  final TripCalculationService _calcService = TripCalculationService();

  List<Etape> _etapes = [];
  List<Trajet> _trajets = [];
  List<Waypoint> _waypoints = [];
  bool _loading = true;
  bool _recalcul = false;
  ModeAffichage _modeAffichage = ModeAffichage.partage;
  FondCarte _fondCarte = FondCarte.osm;
  bool _afficherSentiers = false;
  bool _afficherWaypoints = true;
  bool _chargementSuggestions = false;

  // Mode "ajout de waypoint personnel" : actif, un simple tap sur la
  // carte cree un waypoint personnel (epingle libre) au lieu d'ouvrir
  // la fiche d'ajout d'etape (qui reste accessible via appui long).
  bool _modeAjoutWaypoint = false;
  // Telechargement de zone hors ligne : progression affichee dans un
  // dialogue, annulable a tout moment.
  bool _chargementTuiles = false;
  int _tuilesTelechargees = 0;
  int _tuilesTotal = 0;
  bool _annulerTuiles = false;

  final WaypointSuggestionService _suggestionService =
      WaypointSuggestionService();
  final GeolocalisationService _geolocalisationService =
      GeolocalisationService();

  // Position de l'utilisateur sur la carte (null si non demandee ou
  // indisponible). Demandee uniquement sur action explicite.
  PositionUtilisateur? _positionUtilisateur;
  bool _recuperationPosition = false;

  // Recherche d'adresse/lieu directement depuis la vue carte.
  final TextEditingController _rechercheCarteController =
      TextEditingController();
  final NominatimService _nominatimServiceCarte = NominatimService();
  List<LieuTrouve> _resultatsRechercheCarte = [];
  bool _recherchingCarte = false;
  String? _erreurRechercheCarte;
  Timer? _debounceCarte;
  int _rechercheCarteEnCours = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _debounceCarte?.cancel();
    _rechercheCarteController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _loading = true);
    final db = TripPlannerDatabase.instance;
    final etapes = await db.getEtapesForVoyage(widget.voyage.id!);
    final trajets = await db.getTrajetsForVoyage(widget.voyage.id!);
    final waypoints = await db.getWaypointsForVoyage(widget.voyage.id!);
    setState(() {
      _etapes = etapes;
      _trajets = trajets;
      _waypoints = waypoints;
      _loading = false;
    });
    _centrerCarte();
  }

  void _centrerCarte() {
    if (_etapes.isEmpty) return;
    if (_etapes.length == 1) {
      _mapController.move(
        LatLng(_etapes.first.latitude, _etapes.first.longitude),
        9,
      );
      return;
    }
    final bounds = LatLngBounds.fromPoints(
      _etapes.map((e) => LatLng(e.latitude, e.longitude)).toList(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    });
  }

  Future<void> _recalculerTrajets() async {
    if (widget.voyage.id == null) return;
    setState(() => _recalcul = true);
    final echecs = await _calcService.recalculerTrajets(widget.voyage.id!);
    await _charger();
    if (!mounted) return;
    setState(() => _recalcul = false);
    if (echecs > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$echecs trajet(s) n\'ont pas pu etre calcules (verifie ta '
            'connexion) : reessaie plus tard.',
          ),
        ),
      );
    }
  }

  Future<void> _ajouterEtape({double? lat, double? lon, String? nom}) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EtapeFormScreen(
          voyageId: widget.voyage.id!,
          ordre: _etapes.length,
          latitudeInitiale: lat,
          longitudeInitiale: lon,
          nomInitial: nom,
        ),
      ),
    );
    if (created == true) {
      await _recalculerTrajets();
    }
  }

  Future<void> _modifierEtape(Etape etape) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EtapeFormScreen(
          voyageId: widget.voyage.id!,
          ordre: etape.ordre,
          etape: etape,
        ),
      ),
    );
    if (updated == true) {
      await _recalculerTrajets();
    }
  }

  Future<void> _supprimerEtape(Etape etape) async {
    if (etape.id == null) return;
    await TripPlannerDatabase.instance.deleteEtape(etape.id!);
    await _renumeroterEtapes();
    await _recalculerTrajets();
  }

  // WAYPOINTS

  /// Demande des suggestions de waypoints autour du trace du voyage
  /// (API Overpass, sur requete explicite de l'utilisateur). Les
  /// suggestions deja en base sont remplacees ; les waypoints
  /// personnels ne sont jamais touches. Sans trace routier (trajets
  /// non calcules ou mode manuel), on retombe sur une ligne brisee
  /// entre etapes consecutives.
  /// Pre-telecharge les tuiles de la zone visible pour un usage
  /// hors ligne : l'utilisateur choisit la plage de zooms (la zone est
  /// la vue actuelle de la carte), puis les tuiles sont enregistrees
  /// localement et servies par TuilesHorsLigneTileProvider. Le GPS
  /// fonctionne deja sans reseau ; seuls les fonds de carte
  /// necessitaient ce pre-chargement.
  Future<void> _afficherDialogueZoneHorsLigne() async {
    if (_chargementTuiles) return;
    final bounds = _mapController.camera.visibleBounds;
    final zone = ZoneTuiles(
      sud: bounds.south,
      ouest: bounds.west,
      nord: bounds.north,
      est: bounds.east,
    );
    var zoomMin = (_mapController.camera.zoom.floor() - 2).clamp(8, 16).toInt();
    var zoomMax = (_mapController.camera.zoom.floor() + 2).clamp(10, 17).toInt();

    final lancer = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Zone hors ligne'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enregistre sur ton appareil les fonds de carte de la '
                'zone actuellement visible, pour les consulter sans '
                'reseau. Le GPS continue de fonctionner hors ligne.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: zoomMin,
                decoration: const InputDecoration(
                  labelText: 'Zoom minimum',
                ),
                items: [
                  for (var z = 8; z <= 15; z++)
                    DropdownMenuItem(value: z, child: Text('Zoom $z')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() {
                      zoomMin = v;
                      if (zoomMax < zoomMin) zoomMax = zoomMin;
                    });
                  }
                },
              ),
              DropdownButtonFormField<int>(
                value: zoomMax,
                decoration: const InputDecoration(
                  labelText: 'Zoom maximum',
                ),
                items: [
                  for (var z = 10; z <= 17; z++)
                    DropdownMenuItem(value: z, child: Text('Zoom $z')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() {
                      zoomMax = v;
                      if (zoomMin > zoomMax) zoomMin = zoomMax;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              FutureBuilder<int>(
                future: tailleStockageTuiles(),
                builder: (context, snapshot) {
                  final octets = snapshot.data ?? 0;
                  return Text(
                    'Stockage hors ligne actuel : '
                    '${(octets / 1024 / 1024).toStringAsFixed(1)} Mo',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await viderStockageTuiles();
                if (context.mounted) {
                  Navigator.pop(context, false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Stockage hors ligne vide.'),
                    ),
                  );
                }
              },
              child: const Text('Vider le stockage'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Telecharger'),
            ),
          ],
        ),
      ),
    );
    if (lancer != true) return;
    await _telechargerZone(zone, zoomMin, zoomMax);
  }

  Future<void> _telechargerZone(
    ZoneTuiles zone,
    int zoomMin,
    int zoomMax,
  ) async {
    setState(() {
      _chargementTuiles = true;
      _annulerTuiles = false;
      _tuilesTelechargees = 0;
      _tuilesTotal = TuilesHorsLigneService.compterTuiles(
        zone,
        zoomMin,
        zoomMax,
      );
    });
    final resultat = await TuilesHorsLigneService.telecharger(
      zone: zone,
      zoomMin: zoomMin,
      zoomMax: zoomMax,
      urlTemplate: _urlTuilesPour(_fondCarte),
      nomFond: _fondCarte.name,
      onProgression: (fait, total) {
        if (mounted) {
          setState(() {
            _tuilesTelechargees = fait;
            _tuilesTotal = total;
          });
        }
      },
      doitAnnuler: () => _annulerTuiles,
    );
    if (!mounted) return;
    setState(() => _chargementTuiles = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _annulerTuiles
              ? 'Telechargement annule '
                  '(${resultat.reussies}/${resultat.total} tuiles).'
              : 'Zone hors ligne prete : ${resultat.reussies} tuiles '
                  'enregistrees'
                  '${resultat.echecs > 0 ? ', ${resultat.echecs} echecs' : ''}.',
        ),
      ),
    );
  }

  /// Ouvre un dialogue de selection des groupes de categories de POI
  /// (sites, randonnee, ravitaillement, pratique) avant de lancer la
  /// recherche Overpass. Plusieurs groupes peuvent etre cumules.
  Future<void> _choisirCategoriesEtCharger() async {
    final groupes = WaypointSuggestionService.categoriesParGroupe;
    final selectionnes = <String>{...groupes.keys};
    final lancer = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Categories de POI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: groupes.keys
                .map(
                  (groupe) => CheckboxListTile(
                    value: selectionnes.contains(groupe),
                    onChanged: (coche) {
                      setDialogState(() {
                        if (coche == true) {
                          selectionnes.add(groupe);
                        } else {
                          selectionnes.remove(groupe);
                        }
                      });
                    },
                    title: Text(groupe),
                    dense: true,
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: selectionnes.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Rechercher'),
            ),
          ],
        ),
      ),
    );
    if (lancer != true) return;
    final categories = <String, String>{};
    for (final groupe in selectionnes) {
      categories.addAll(groupes[groupe]!);
    }
    await _chargerSuggestionsWaypoints(categoriesParCle: categories);
  }

  Future<void> _chargerSuggestionsWaypoints({
    Map<String, String>? categoriesParCle,
  }) async {
    if (widget.voyage.id == null || _chargementSuggestions) return;
    final trace = <List<double>>[];
    for (final trajet in _trajets) {
      final points = trajet.points.isNotEmpty
          ? trajet.points
          : _pointsEtapesPour(trajet)
              .map((p) => [p.latitude, p.longitude])
              .toList();
      trace.addAll(points);
    }
    if (trace.isEmpty && _etapes.isNotEmpty) {
      for (final etape in _etapes) {
        trace.add([etape.latitude, etape.longitude]);
      }
    }

    setState(() => _chargementSuggestions = true);
    try {
      final suggestions = await _suggestionService.suggererWaypoints(
        trace: trace,
        rayonMetres: 3000,
        categoriesParCle: categoriesParCle,
      );
      final db = TripPlannerDatabase.instance;
      // Seule une nouvelle recherche remplace les recommandations
      // existantes ; les waypoints personnels ne sont jamais touches
      // (deleteWaypointsRecommandesForVoyage ne cible que la source
      // 'recommande').
      await db.deleteWaypointsRecommandesForVoyage(widget.voyage.id!);
      for (final suggestion in suggestions) {
        await db.insertWaypoint(suggestion.toWaypoint(widget.voyage.id!));
      }
      final waypoints = await db.getWaypointsForVoyage(widget.voyage.id!);
      if (!mounted) return;
      setState(() {
        _waypoints = waypoints;
        _afficherWaypoints = true;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            suggestions.isEmpty
                ? 'Aucun waypoint recommande trouve pres du trace.'
                : '${suggestions.length} waypoint(s) recommande(s) ajoute(s).',
          ),
        ),
      );
    } on SuggestionWaypointException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _chargementSuggestions = false);
    }
  }

  /// Recupere la position de l'utilisateur et centre la carte dessus.
  /// Sur erreur (permission refusee, service desactive...), affiche un
  /// message explicite plutot que d'echouer silencieusement.
  Future<void> _localiserUtilisateur() async {
    if (_recuperationPosition) return;
    setState(() => _recuperationPosition = true);
    try {
      final position = await _geolocalisationService.positionActuelle();
      if (!mounted) return;
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Position indisponible pour le moment.'),
          ),
        );
        return;
      }
      setState(() => _positionUtilisateur = position);
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        14,
      );
    } on GeolocalisationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _recuperationPosition = false);
    }
  }

  /// Cree un waypoint personnel a l'endroit tape sur la carte.
  Future<void> _ajouterWaypointPersonnel(double lat, double lon) async {
    if (widget.voyage.id == null) return;
    final waypoint = Waypoint(
      voyageId: widget.voyage.id!,
      nom: 'Waypoint personnel',
      latitude: lat,
      longitude: lon,
      source: SourceWaypoint.personnel,
      categorie: 'personnel',
    );
    await TripPlannerDatabase.instance.insertWaypoint(waypoint);
    final waypoints =
        await TripPlannerDatabase.instance.getWaypointsForVoyage(widget.voyage.id!);
    if (!mounted) return;
    setState(() {
      _waypoints = waypoints;
      _afficherWaypoints = true;
      _modeAjoutWaypoint = false;
    });
  }

  /// Convertit un waypoint en etape de type passage : reutilise la
  /// fiche d'edition d'etape existante (dates, notes...), puis le
  /// recalcul standard des trajets s'occupe de l'insertion dans
  /// l'itineraire. Le waypoint est supprime seulement si l'utilisateur
  /// valide la creation de l'etape.
  Future<void> _convertirWaypointEnEtape(Waypoint waypoint) async {
    if (widget.voyage.id == null) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EtapeFormScreen(
          voyageId: widget.voyage.id!,
          ordre: _etapes.length,
          latitudeInitiale: waypoint.latitude,
          longitudeInitiale: waypoint.longitude,
          nomInitial: waypoint.nom,
        ),
      ),
    );
    if (created == true) {
      if (waypoint.id != null) {
        await TripPlannerDatabase.instance.deleteWaypoint(waypoint.id!);
      }
      await _recalculerTrajets();
    }
  }

  Future<void> _supprimerWaypoint(Waypoint waypoint) async {
    if (waypoint.id == null) return;
    await TripPlannerDatabase.instance.deleteWaypoint(waypoint.id!);
    final waypoints = await TripPlannerDatabase.instance
        .getWaypointsForVoyage(widget.voyage.id!);
    if (!mounted) return;
    setState(() => _waypoints = waypoints);
  }

  /// Reordonne les etapes suite a un glisser-deposer dans la liste, ou
  /// suite a une suppression, puis persiste le nouvel ordre.
  Future<void> _renumeroterEtapes() async {
    final db = TripPlannerDatabase.instance;
    final etapes = await db.getEtapesForVoyage(widget.voyage.id!);
    for (var i = 0; i < etapes.length; i++) {
      if (etapes[i].ordre != i) {
        await db.updateEtape(etapes[i].copyWith(ordre: i));
      }
    }
  }

  Future<void> _modifierVoyage() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VoyageFormScreen(voyage: widget.voyage),
      ),
    );
    if (updated == true && mounted) {
      Navigator.pop(context);
    }
  }

  Trajet? _trajetDepuis(Etape etape) {
    if (etape.id == null) return null;
    for (final t in _trajets) {
      if (t.etapeDepartId == etape.id) return t;
    }
    return null;
  }

  /// Ligne droite de secours entre deux etapes, utilisee pour les
  /// trajets manuels (avion/train/bus) qui n'ont pas de trace routier.
  List<LatLng> _pointsEtapesPour(Trajet trajet) {
    Etape? depart;
    Etape? arrivee;
    for (final e in _etapes) {
      if (e.id == trajet.etapeDepartId) depart = e;
      if (e.id == trajet.etapeArriveeId) arrivee = e;
    }
    if (depart == null || arrivee == null) return [];
    return [
      LatLng(depart.latitude, depart.longitude),
      LatLng(arrivee.latitude, arrivee.longitude),
    ];
  }

  Color _couleurEtape(TypeEtape type) {
    return type == TypeEtape.visite ? Colors.green.shade700 : Colors.orange;
  }

  Color _couleurMode(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return Theme.of(context).colorScheme.primary;
      case ModeTransport.velo:
        return Colors.teal;
      case ModeTransport.vtt:
        return Colors.deepOrange;
      case ModeTransport.marche:
        return Colors.green;
      case ModeTransport.avion:
        return Colors.blue;
      case ModeTransport.train:
        return Colors.purple;
      case ModeTransport.bus:
        return Colors.brown;
      case ModeTransport.autre:
        return Colors.grey.shade700;
    }
  }

  IconData _iconeMode(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return Icons.directions_car_outlined;
      case ModeTransport.velo:
        return Icons.directions_bike_outlined;
      case ModeTransport.vtt:
        return Icons.terrain_outlined;
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

  Future<void> _modifierTransfert(Etape depart, Etape arrivee) async {
    final trajet = _trajetDepuis(depart);
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransfertFormScreen(
          voyageId: widget.voyage.id!,
          etapeDepart: depart,
          etapeArrivee: arrivee,
          trajetExistant: trajet,
        ),
      ),
    );
    if (updated == true) {
      await _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.voyage.titre),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Parametres de planification',
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const ParametresPlanificationScreen(),
                ),
              );
              if (changed == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Parametres enregistres. Relance "Recalculer les '
                      'trajets" pour les appliquer.',
                    ),
                  ),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Fond de carte et sentiers',
            icon: Icon(_iconeFond(_fondCarte)),
            onSelected: (valeur) {
              if (valeur == 'sentiers') {
                setState(() => _afficherSentiers = !_afficherSentiers);
              } else if (valeur == 'waypoints') {
                setState(() => _afficherWaypoints = !_afficherWaypoints);
              } else {
                setState(() => _fondCarte = FondCarte.values.byName(valeur));
              }
            },
            itemBuilder: (context) => [
              _itemFondCarte(FondCarte.osm, 'OpenStreetMap'),
              _itemFondCarte(FondCarte.ignPlan, 'IGN - Plan'),
              _itemFondCarte(FondCarte.ignPhoto, 'IGN - Photos aeriennes'),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<String>(
                value: 'sentiers',
                checked: _afficherSentiers,
                child: const Text('Sentiers de randonnee (GR/GRP/PR)'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'waypoints',
                checked: _afficherWaypoints,
                child: const Text('Waypoints (recommandes et personnels)'),
              ),
            ],
          ),
          IconButton(
            icon: _chargementSuggestions
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.recommend_outlined),
            tooltip: 'Suggerer des waypoints autour du trace',
            onPressed: _chargementSuggestions
                ? null
                : _choisirCategoriesEtCharger,
          ),
          IconButton(
            icon: Icon(
              Icons.list_alt,
              color: _waypoints.isEmpty ? null : Colors.amber.shade800,
            ),
            tooltip: 'Liste des waypoints',
            onPressed: _waypoints.isEmpty ? null : _afficherListeWaypoints,
          ),
          IconButton(
            icon: Icon(
              Icons.push_pin,
              color: _modeAjoutWaypoint ? Colors.amber : null,
            ),
            tooltip: _modeAjoutWaypoint
                ? 'Mode waypoint actif : tape la carte'
                : 'Ajouter un waypoint personnel',
            onPressed: () {
              setState(() => _modeAjoutWaypoint = !_modeAjoutWaypoint);
              if (_modeAjoutWaypoint) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Mode waypoint : tape la carte pour poser une epingle. '
                      'Reappuie sur l\'icone pour desactiver.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: _chargementTuiles
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                      value: _tuilesTotal > 0
                          ? _tuilesTelechargees / _tuilesTotal
                          : null,
                    ),
                  )
                : const Icon(Icons.download_for_offline_outlined),
            tooltip: _chargementTuiles
                ? 'Telechargement : $_tuilesTelechargees/$_tuilesTotal tuiles'
                : 'Enregistrer la zone pour un usage hors ligne',
            onPressed: _chargementTuiles
                ? () => setState(() => _annulerTuiles = true)
                : _afficherDialogueZoneHorsLigne,
          ),
          PopupMenuButton<ModeAffichage>(
            tooltip: 'Disposition de l\'ecran',
            icon: Icon(_iconeModeAffichage(_modeAffichage)),
            onSelected: (mode) => setState(() => _modeAffichage = mode),
            itemBuilder: (context) => [
              _itemModeAffichage(
                ModeAffichage.partage,
                Icons.vertical_split_outlined,
                'Carte + liste (partage)',
              ),
              _itemModeAffichage(
                ModeAffichage.carte,
                Icons.map_outlined,
                'Carte plein ecran',
              ),
              _itemModeAffichage(
                ModeAffichage.liste,
                Icons.view_list_outlined,
                'Liste plein ecran',
              ),
            ],
          ),
          IconButton(
            icon: _recalcul
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.alt_route),
            tooltip: 'Recalculer les trajets',
            onPressed: _recalcul ? null : _recalculerTrajets,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier le voyage',
            onPressed: _modifierVoyage,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ajouterEtape(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Ajouter une etape'),
      ),
    );
  }

  IconData _iconeModeAffichage(ModeAffichage mode) {
    switch (mode) {
      case ModeAffichage.carte:
        return Icons.map_outlined;
      case ModeAffichage.liste:
        return Icons.view_list_outlined;
      case ModeAffichage.partage:
        return Icons.vertical_split_outlined;
    }
  }

  PopupMenuItem<ModeAffichage> _itemModeAffichage(
    ModeAffichage mode,
    IconData icone,
    String libelle,
  ) {
    final selectionne = _modeAffichage == mode;
    return PopupMenuItem<ModeAffichage>(
      value: mode,
      child: Row(
        children: [
          Icon(
            icone,
            size: 20,
            color: selectionne ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              libelle,
              style: TextStyle(
                fontWeight: selectionne ? FontWeight.bold : null,
                color:
                    selectionne ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
          if (selectionne)
            Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }

  IconData _iconeFond(FondCarte fond) {
    switch (fond) {
      case FondCarte.osm:
        return Icons.layers_outlined;
      case FondCarte.ignPlan:
        return Icons.terrain_outlined;
      case FondCarte.ignPhoto:
        return Icons.satellite_alt_outlined;
    }
  }

  PopupMenuItem<String> _itemFondCarte(FondCarte fond, String libelle) {
    final selectionne = _fondCarte == fond;
    return PopupMenuItem<String>(
      value: fond.name,
      child: Row(
        children: [
          Icon(
            _iconeFond(fond),
            size: 20,
            color: selectionne ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              libelle,
              style: TextStyle(
                fontWeight: selectionne ? FontWeight.bold : null,
                color:
                    selectionne ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
          if (selectionne)
            Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }

  /// URL des tuiles pour le fond de carte choisi. Les fonds IGN
  /// utilisent le service WMTS gratuit et sans cle de la Geoplateforme
  /// (data.geopf.fr) ; ils ne couvrent que le territoire francais.
  String _urlTuilesPour(FondCarte fond) {
    switch (fond) {
      case FondCarte.osm:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case FondCarte.ignPlan:
        return 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile'
            '&VERSION=1.0.0&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2'
            '&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/png'
            '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';
      case FondCarte.ignPhoto:
        return 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile'
            '&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS'
            '&STYLE=normal&TILEMATRIXSET=PM&FORMAT=image/jpeg'
            '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';
    }
  }

  String _attributionPour(FondCarte fond) {
    switch (fond) {
      case FondCarte.osm:
        return 'OpenStreetMap contributors';
      case FondCarte.ignPlan:
      case FondCarte.ignPhoto:
        return 'IGN-F/Geoportail';
    }
  }

  Widget _buildBody() {
    switch (_modeAffichage) {
      case ModeAffichage.carte:
        return _buildCarte();
      case ModeAffichage.liste:
        return _etapes.isEmpty ? _buildEmptyState() : _buildListeEtapes();
      case ModeAffichage.partage:
        return Column(
          children: [
            Expanded(
              flex: 5,
              child: _buildCarte(),
            ),
            const Divider(height: 1),
            Expanded(
              flex: 4,
              child: _etapes.isEmpty
                  ? _buildEmptyState()
                  : _buildListeEtapes(),
            ),
          ],
        );
    }
  }

  Widget _buildCarte() {
    final centre = _etapes.isNotEmpty
        ? LatLng(_etapes.first.latitude, _etapes.first.longitude)
        : const LatLng(46.6, 2.4); // centre approximatif de la France

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centre,
              initialZoom: _etapes.isEmpty ? 5 : 6,
              onTap: _modeAjoutWaypoint
                  ? (tapPosition, point) =>
                      _ajouterWaypointPersonnel(point.latitude, point.longitude)
                  : null,
              onLongPress: (tapPosition, point) =>
                  _ajouterEtape(lat: point.latitude, lon: point.longitude),
            ),
            children: [
              TileLayer(
                urlTemplate: _urlTuilesPour(_fondCarte),
                userAgentPackageName: 'com.baroudeurs.studio',
                maxZoom: 19,
                tileProvider: TuilesHorsLigneTileProvider(
                  nomFond: _fondCarte.name,
                ),
              ),
              if (_afficherSentiers)
                TileLayer(
                  urlTemplate:
                      'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.baroudeurs.studio',
                  maxZoom: 18,
                ),
              if (_trajets.isNotEmpty)
                PolylineLayer(
                  polylines: _trajets.map((t) {
                    final points = t.points.isNotEmpty
                        ? t.points.map((p) => LatLng(p[0], p[1])).toList()
                        : _pointsEtapesPour(t);
                    return Polyline(
                      points: points,
                      strokeWidth: t.mode.estAutoCalcule ? 4 : 3,
                      color: _couleurMode(t.mode),
                    );
                  }).toList(),
                ),
              if (_afficherWaypoints)
                MarkerLayer(
                  markers: _waypoints
                      .map((waypoint) => Marker(
                            point: LatLng(waypoint.latitude, waypoint.longitude),
                            width: 32,
                            height: 32,
                            child: GestureDetector(
                              onTap: () => _afficherDetailWaypoint(waypoint),
                              child: Icon(
                                waypoint.estPersonnel
                                    ? Icons.push_pin
                                    : Icons.star,
                                size: 28,
                                color: waypoint.estPersonnel
                                    ? Colors.red.shade700
                                    : Colors.amber.shade800,
                                shadows: const [
                                  Shadow(color: Colors.black54, blurRadius: 2),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              if (_positionUtilisateur != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _positionUtilisateur!.latitude,
                        _positionUtilisateur!.longitude,
                      ),
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: _etapes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final etape = entry.value;
                  return Marker(
                    point: LatLng(etape.latitude, etape.longitude),
                    width: 36,
                    height: 36,
                    child: GestureDetector(
                      onTap: () => _afficherDetailEtape(etape),
                      child: CircleAvatar(
                        backgroundColor: _couleurEtape(etape.type),
                        foregroundColor: Colors.white,
                        child: Text('${index + 1}'),
                      ),
                    ),
                  );
                }).toList(),
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(_attributionPour(_fondCarte)),
                  if (_afficherSentiers)
                    const TextSourceAttribution(
                      'Sentiers : Waymarked Trails (OpenStreetMap, CC-BY-SA)',
                    ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: SafeArea(
            bottom: false,
            child: _buildRechercheCarte(),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 12,
          child: FloatingActionButton(
            heroTag: 'btnLocalisation',
            onPressed:
                _recuperationPosition ? null : _localiserUtilisateur,
            tooltip: 'Ma position',
            child: _recuperationPosition
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  void _effacerRechercheCarte() {
    setState(() {
      _rechercheCarteController.clear();
      _resultatsRechercheCarte = [];
      _erreurRechercheCarte = null;
    });
  }

  void _onRechercheCarteChanged(String value) {
    _debounceCarte?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _resultatsRechercheCarte = [];
        _erreurRechercheCarte = null;
        _recherchingCarte = false;
      });
      return;
    }
    _debounceCarte = Timer(const Duration(milliseconds: 1000), () {
      _lancerRechercheCarte(value);
    });
  }

  Future<void> _lancerRechercheCarte(String value) async {
    final numero = ++_rechercheCarteEnCours;
    setState(() {
      _recherchingCarte = true;
      _erreurRechercheCarte = null;
    });

    try {
      final resultats = await _nominatimServiceCarte.rechercherLieu(value);
      if (!mounted || numero != _rechercheCarteEnCours) return;
      setState(() {
        _resultatsRechercheCarte = resultats;
        _recherchingCarte = false;
      });
    } on RechercheLieuException catch (e) {
      if (!mounted || numero != _rechercheCarteEnCours) return;
      setState(() {
        _resultatsRechercheCarte = [];
        _recherchingCarte = false;
        _erreurRechercheCarte = e.message;
      });
    }
  }

  void _selectionnerLieuCarte(LieuTrouve lieu) {
    _mapController.move(LatLng(lieu.latitude, lieu.longitude), 12);
    final nom = lieu.nomAffiche.split(',').first;
    setState(() {
      _resultatsRechercheCarte = [];
      _erreurRechercheCarte = null;
      _rechercheCarteController.clear();
    });
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lieu.nomAffiche,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: 'Ajouter ici',
          onPressed: () => _ajouterEtape(
            lat: lieu.latitude,
            lon: lieu.longitude,
            nom: nom,
          ),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Widget _buildRechercheCarte() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(10),
          child: TextField(
            controller: _rechercheCarteController,
            decoration: InputDecoration(
              hintText: 'Rechercher une adresse ou un lieu...',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _recherchingCarte
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_rechercheCarteController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _effacerRechercheCarte,
                        )
                      : null),
            ),
            onChanged: _onRechercheCarteChanged,
          ),
        ),
        if (_erreurRechercheCarte != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _erreurRechercheCarte!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (_resultatsRechercheCarte.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
              ],
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: _resultatsRechercheCarte
                  .map((lieu) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          lieu.nomAffiche,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectionnerLieuCarte(lieu),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  /// Liste de tous les waypoints du voyage, tries par distance au
  /// trace : resout le cas des POI hors du champ de la caméra, et
  /// donne un acces rapide au detail, au recentrage et a la
  /// conversion en etape.
  void _afficherListeWaypoints() {
    final trace = <List<double>>[];
    for (final trajet in _trajets) {
      final points = trajet.points.isNotEmpty
          ? trajet.points
          : _pointsEtapesPour(trajet)
              .map((p) => [p.latitude, p.longitude])
              .toList();
      trace.addAll(points);
    }
    if (trace.isEmpty) {
      for (final etape in _etapes) {
        trace.add([etape.latitude, etape.longitude]);
      }
    }
    final tries = _waypoints.toList()
      ..sort((a, b) {
        final da = _distanceAuTrace(a.latitude, a.longitude, trace);
        final db = _distanceAuTrace(b.latitude, b.longitude, trace);
        return da.compareTo(db);
      });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          itemCount: tries.length,
          itemBuilder: (context, index) {
            final waypoint = tries[index];
            final distance =
                _distanceAuTrace(waypoint.latitude, waypoint.longitude, trace);
            return ListTile(
              leading: Icon(
                waypoint.estPersonnel
                    ? Icons.push_pin
                    : Icons.thumb_up,
                size: 20,
                color: waypoint.estPersonnel
                    ? Colors.red.shade700
                    : Colors.amber.shade800,
              ),
              title: Text(waypoint.nom),
              subtitle: Text(
                '${_libelleCategorieWaypoint(waypoint.categorie)}'
                '${distance >= 0 ? ' · ${_formatDistance(distance)} du trace' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _mapController.move(
                  LatLng(waypoint.latitude, waypoint.longitude),
                  14,
                );
                _afficherDetailWaypoint(waypoint);
              },
            );
          },
        ),
      ),
    );
  }

  /// Distance approchee (metres) d'un point au trace, -1 si aucun
  /// trace disponible.
  double _distanceAuTrace(
    double lat,
    double lon,
    List<List<double>> trace,
  ) {
    if (trace.isEmpty) return -1;
    var min = double.infinity;
    for (final p in trace) {
      final d = _distanceMetres(lat, lon, p[0], p[1]);
      if (d < min) min = d;
    }
    return min;
  }

  /// Distance en metres entre deux points lat/lon (haversine),
  /// suffisante pour un tri de proximite.
  double _distanceMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const rayonTerreM = 6371000.0;
    final dLat = _degVersRad(lat2 - lat1);
    final dLon = _degVersRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degVersRad(lat1)) *
            math.cos(_degVersRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return rayonTerreM * c;
  }

  double _degVersRad(double deg) => deg * (math.pi / 180.0);

  String _formatDistance(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  void _afficherDetailWaypoint(Waypoint waypoint) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    waypoint.estPersonnel
                        ? Icons.push_pin
                        : Icons.star,
                    size: 20,
                    color: waypoint.estPersonnel
                        ? Colors.red.shade700
                        : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      waypoint.nom,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                waypoint.estPersonnel
                    ? 'Waypoint personnel'
                    : 'Recommande${waypoint.categorie.isNotEmpty ? ' · ${_libelleCategorieWaypoint(waypoint.categorie)}' : ''}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                '${waypoint.latitude.toStringAsFixed(5)}, '
                '${waypoint.longitude.toStringAsFixed(5)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _convertirWaypointEnEtape(waypoint);
                    },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Convertir en etape'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _supprimerWaypoint(waypoint);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Supprimer',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _libelleCategorieWaypoint(String categorie) {
    switch (categorie) {
      case 'tourism=attraction':
        return 'attraction';
      case 'tourism=viewpoint':
        return 'point de vue';
      case 'tourism=artwork':
        return 'oeuvre d\'art';
      case 'natural=peak':
        return 'sommet';
      case 'natural=waterfall':
        return 'cascade';
      case 'natural=beach':
        return 'plage';
      case 'historic=monument':
        return 'monument';
      case 'historic=castle':
        return 'chateau';
      case 'historic=ruins':
        return 'ruines';
      case 'tourism=alpine_hut':
        return 'refuge';
      case 'tourism=wilderness_hut':
        return 'cabane';
      case 'amenity=shelter':
        return 'abri';
      case 'leisure=picnic_site':
        return 'aire de pique-nique';
      case 'leisure=camp_site':
        return 'camping';
      case 'amenity=drinking_water':
      case 'amenity=water_point':
        return 'point d\'eau';
      case 'natural=spring':
        return 'source';
      case 'shop=bakery':
        return 'boulangerie';
      case 'shop=supermarket':
        return 'supermarche';
      case 'shop=convenience':
        return 'epicerie';
      case 'amenity=fuel':
        return 'station-service';
      case 'amenity=pharmacy':
        return 'pharmacie';
      case 'amenity=hospital':
        return 'hopital';
      case 'amenity=toilets':
        return 'toilettes';
      case 'amenity=parking':
        return 'parking';
      case 'tourism=guest_house':
        return 'chambre d\'hote';
      case 'tourism=hostel':
        return 'auberge';
      case 'tourism=hotel':
        return 'hotel';
      case 'tourism=motel':
        return 'motel';
      case 'personnel':
        return 'personnel';
      default:
        return categorie;
    }
  }

  void _afficherDetailEtape(Etape etape) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etape.nom,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(_formatPeriode(etape)),
              if (etape.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(etape.notes),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _modifierEtape(etape);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _supprimerEtape(etape);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Supprimer',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('EEEE d MMMM', 'fr').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  /// Formate la periode d'une etape en tenant compte des heures et
  /// d'un eventuel depart a une date differente de l'arrivee (sejour
  /// de plusieurs jours au meme endroit).
  String _formatPeriode(Etape etape) {
    final dateArrivee = _formatDate(etape.date);
    if (etape.type != TypeEtape.visite) {
      return dateArrivee;
    }

    final heureArrivee = etape.heureArrivee;
    final dateDepartDifferente =
        etape.dateDepart != null && etape.dateDepart != etape.date;
    final heureDepart = etape.heureDepart;

    final buffer = StringBuffer(dateArrivee);
    if (heureArrivee != null) {
      buffer.write(' $heureArrivee');
    }

    if (dateDepartDifferente) {
      buffer.write(' → ${_formatDate(etape.dateDepart!)}');
      if (heureDepart != null) buffer.write(' $heureDepart');
    } else if (heureDepart != null) {
      buffer.write(' → $heureDepart');
    }

    return buffer.toString();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.route_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Aucune etape pour le moment.\nAjoute-en une, ou fais un '
              'appui long sur la carte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListeEtapes() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _etapes.length,
      onReorderItem: (oldItemIndex, newItemIndex) async {
        setState(() {
          if (newItemIndex > oldItemIndex) newItemIndex -= 1;
          final etape = _etapes.removeAt(oldItemIndex);
          _etapes.insert(newItemIndex, etape);
        });
        for (var i = 0; i < _etapes.length; i++) {
          await TripPlannerDatabase.instance
              .updateEtape(_etapes[i].copyWith(ordre: i));
        }
        await _recalculerTrajets();
      },
      itemBuilder: (context, index) {
        final etape = _etapes[index];
        final trajet = _trajetDepuis(etape);
        final etapeSuivante =
            index < _etapes.length - 1 ? _etapes[index + 1] : null;
        return Column(
          key: ValueKey(etape.id ?? etape.hashCode),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _couleurEtape(etape.type),
                foregroundColor: Colors.white,
                child: Text('${index + 1}'),
              ),
              title: Text(etape.nom),
              subtitle: Text(_formatPeriode(etape)),
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _afficherDetailEtape(etape),
              ),
              onTap: () => _modifierEtape(etape),
            ),
            if (etapeSuivante != null)
              InkWell(
                onTap: () {
                  final t = _trajetDepuis(etape);
                  if (t != null && t.mode.estAutoCalcule) {
                    _afficherProfilTrajet(t, etape, etapeSuivante);
                  } else {
                    _modifierTransfert(etape, etapeSuivante);
                  }
                },
                onLongPress: () => _modifierTransfert(etape, etapeSuivante),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 72,
                    bottom: 8,
                    top: 2,
                    right: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        trajet != null
                            ? _iconeMode(trajet.mode)
                            : Icons.directions_car_outlined,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _libelleTrajet(trajet),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit, size: 14, color: Colors.grey),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Fiche detail d'un trajet auto-calcule : resume complet (distance,
  /// duree, denivele) et graphique altitude/distance du trace.
  void _afficherProfilTrajet(Trajet trajet, Etape depart, Etape arrivee) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconeMode(trajet.mode), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${depart.nom} → ${arrivee.nom}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _modifierTransfert(depart, arrivee);
                  },
                  child: const Text('Modifier'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_libelleModeCourt(trajet.mode)} · '
              '${trajet.distanceKm.toStringAsFixed(1)} km · '
              '${_formatDuree(trajet.dureeMinutes)}'
              '${trajet.denivelePositifM > 0 ? ' · +${trajet.denivelePositifM} m D+' : ''}'
              '${trajet.deniveleNegatifM > 0 ? ' · -${trajet.deniveleNegatifM} m D-' : ''}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ProfilAltitudeChart(profil: trajet.profilAltitude),
          ],
        ),
      ),
    );
  }

  String _libelleTrajet(Trajet? trajet) {
    if (trajet == null) return 'Trajet non calcule · appuyer pour definir';
    if (trajet.mode.estAutoCalcule) {
      final denivele = trajet.denivelePositifM > 0
          ? ' · +${trajet.denivelePositifM} m'
          : '';
      return '${trajet.distanceKm.toStringAsFixed(0)} km · '
          '${_formatDuree(trajet.dureeMinutes)}'
          '${trajet.mode == ModeTransport.voiture ? ' de route' : ''}'
          '$denivele';
    }
    final heures =
        (trajet.heureDepart != null && trajet.heureArrivee != null)
            ? '${trajet.heureDepart} → ${trajet.heureArrivee}'
            : null;
    final transporteur = trajet.transporteur;
    final parts = [
      if (transporteur != null && transporteur.isNotEmpty) transporteur,
      if (heures != null) heures,
    ];
    return parts.isEmpty
        ? '${_libelleModeCourt(trajet.mode)} · details a completer'
        : parts.join(' · ');
  }

  String _libelleModeCourt(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return 'Voiture';
      case ModeTransport.velo:
        return 'Velo';
      case ModeTransport.vtt:
        return 'VTT';
      case ModeTransport.marche:
        return 'Marche';
      case ModeTransport.avion:
        return 'Vol';
      case ModeTransport.train:
        return 'Train';
      case ModeTransport.bus:
        return 'Bus';
      case ModeTransport.autre:
        return 'Transfert';
    }
  }

  String _formatDuree(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
}
