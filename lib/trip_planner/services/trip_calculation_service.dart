import 'dart:convert';
import 'dart:math' as math;

import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import '../models/parametres_planification.dart';
import 'brouter_service.dart';
import 'elevation_service.dart';
import 'osrm_service.dart';

/// Orchestre le recalcul des trajets entre etapes consecutives d'un
/// voyage. A appeler apres tout ajout, suppression ou reordonnancement
/// d'etape.
///
/// Pour chaque paire d'etapes consecutives, le mode de transport deja
/// choisi est respecte : voiture/velo/marche sont recalcules via OSRM
/// (avec le profil correspondant) et le vtt via BRouter (profil mtb),
/// tandis qu'avion/train/bus/autre, saisis manuellement par
/// l'utilisateur (voir [ModeTransportInfo]),
/// ne sont jamais recalcules ni ecrases. Une paire sans trajet existant
/// est calculee par defaut en voiture.
class TripCalculationService {
  final OsrmService _osrm;
  final BrouterService _brouter;
  final ElevationService _elevation;
  final TripPlannerDatabase _db;

  TripCalculationService({
    OsrmService? osrmService,
    BrouterService? brouterService,
    ElevationService? elevationService,
    TripPlannerDatabase? database,
  })  : _osrm = osrmService ?? OsrmService(),
        _brouter = brouterService ?? BrouterService(osrmService: osrmService),
        _elevation = elevationService ?? ElevationService(),
        _db = database ?? TripPlannerDatabase.instance;

  /// Recalcule les trajets auto-calcules (voiture/velo/vtt/marche) du
  /// voyage a partir de ses etapes, dans l'ordre, en conservant le
  /// mode deja choisi pour chaque paire. Les trajets manuels
  /// (avion/train/bus/autre) sont conserves tant que leur paire
  /// d'etapes reste consecutive ; un trajet dont la paire n'est plus
  /// consecutive (suite a une suppression/un reordonnancement) est
  /// supprime.
  ///
  /// Retourne le nombre de trajets qui n'ont pas pu etre calcules
  /// (ex: pas de connexion reseau), pour que l'UI puisse avertir
  /// l'utilisateur sans bloquer le reste de la planification.
  Future<int> recalculerTrajets(int voyageId) async {
    // Seules les etapes racines participent a l'itineraire : les
    // sous-etapes (activites d'une visite) restent au meme endroit
    // que leur parent et ne creent pas de trajet.
    final toutesEtapes = await _db.getEtapesForVoyage(voyageId);
    final etapes =
        toutesEtapes.where((e) => e.parentId == null).toList();
    final trajetsExistants = await _db.getTrajetsForVoyage(voyageId);

    if (etapes.length < 2) {
      await _db.deleteTrajetsForVoyage(voyageId);
      return 0;
    }

    // Paires consecutives valides dans l'ordre actuel des etapes.
    final pairesValides = <String>{};
    for (var i = 0; i < etapes.length - 1; i++) {
      final depart = etapes[i].id;
      final arrivee = etapes[i + 1].id;
      if (depart != null && arrivee != null) {
        pairesValides.add('$depart-$arrivee');
      }
    }

    // Supprime les trajets (auto ou manuels) dont la paire n'est plus
    // consecutive : etape supprimee ou ordre change entre-temps.
    for (final trajet in trajetsExistants) {
      final cle = '${trajet.etapeDepartId}-${trajet.etapeArriveeId}';
      if (!pairesValides.contains(cle) && trajet.id != null) {
        await _db.deleteTrajet(trajet.id!);
      }
    }

    // Mode deja choisi pour chaque paire encore valide (par defaut
    // voiture si aucun trajet n'existe encore pour cette paire).
    final modeParPaire = <String, ModeTransport>{};
    for (final trajet in trajetsExistants) {
      final cle = '${trajet.etapeDepartId}-${trajet.etapeArriveeId}';
      if (pairesValides.contains(cle)) {
        modeParPaire[cle] = trajet.mode;
      }
    }

    final parametres = await _db.getParametres();
    int echecs = 0;
    // Passe a true des le premier echec reseau : les paires
    // suivantes sont ecrites en secours sans nouvelle tentative.
    var horsLigne = false;
    for (var i = 0; i < etapes.length - 1; i++) {
      final Etape depart = etapes[i];
      final Etape arrivee = etapes[i + 1];
      if (depart.id == null || arrivee.id == null) continue;

      final cle = '${depart.id}-${arrivee.id}';
      final mode = modeParPaire[cle] ?? ModeTransport.voiture;

      if (!mode.estAutoCalcule) {
        continue; // transfert manuel : on ne touche pas.
      }

      // Apres un premier echec reseau, inutile de re-atendre un
      // timeout par paire suivante : on considere le routage
      // indisponible pour le reste du passe et on ecrit directement
      // les trajets de secours (un recalcul ultereur les affinera).
      Future<ResultatItineraire?> calculer() => mode == ModeTransport.vtt
          ? _brouter.calculerItineraireVtt(
              latDepart: depart.latitude,
              lonDepart: depart.longitude,
              latArrivee: arrivee.latitude,
              lonArrivee: arrivee.longitude,
            )
          : _osrm.calculerItineraire(
              mode: mode,
              latDepart: depart.latitude,
              lonDepart: depart.longitude,
              latArrivee: arrivee.latitude,
              lonArrivee: arrivee.longitude,
              eviterAutoroutes: parametres.eviterAutoroutes,
              eviterPeages: parametres.eviterPeages,
            );
      // Une seconde tentative evite de basculer tout le voyage en
      // lignes droites sur un simple hoquet reseau.
      ResultatItineraire? resultat;
      if (!horsLigne) {
        resultat = await calculer() ?? await calculer();
      }
      if (resultat == null) {
        horsLigne = true;
      }

      // Meme sans reseau (ou si le serveur refuse la requete), on
      // enregistre un trajet de secours en ligne droite entre les
      // deux etapes : le parcours reste toujours trace sur la carte,
      // et un recalcul ultereur ecrasera cette estimation des que le
      // routage repondra a nouveau.
      final points = resultat?.points ??
          [
            [depart.latitude, depart.longitude],
            [arrivee.latitude, arrivee.longitude],
          ];
      final distanceKm = resultat?.distanceKm ??
          _distanceHaversineKm(
            depart.latitude,
            depart.longitude,
            arrivee.latitude,
            arrivee.longitude,
          );
      final dureeMinutes = resultat?.dureeMinutes ??
          _dureeEstimeeMinutes(mode, distanceKm, parametres);

      if (resultat == null) {
        echecs++;
      }

      // Correction de la duree selon les vitesses moyennes de
      // l'utilisateur : les profils de routage supposent un terrain
      // plat et un rythme soutenu ; un randonneur en montagne ou un
      // cyclotouriste charge est plus lent.
      var dureeMinutesFinale = dureeMinutes;
      if (mode == ModeTransport.marche &&
          parametres.vitesseMarcheKmh > 0) {
        dureeMinutesFinale =
            (distanceKm / parametres.vitesseMarcheKmh * 60).round();
      } else if (mode == ModeTransport.velo &&
          parametres.vitesseVeloKmh > 0) {
        dureeMinutesFinale =
            (distanceKm / parametres.vitesseVeloKmh * 60).round();
      }

      // Denivele et profil d'altitude du trace (best effort : sans
      // reseau, le trajet reste exploitable, simplement sans profil).
      var denivelePositif = 0;
      var deniveleNegatif = 0;
      var profilJson = '[]';
      if (points.length > 2) {
        final profil = await _elevation.calculerProfil(points);
        if (profil != null) {
          denivelePositif = profil.denivelePositifM;
          deniveleNegatif = profil.deniveleNegatifM;
          profilJson = jsonEncode(profil.toList());
        }
      }

      await _db.upsertTrajet(Trajet(
        voyageId: voyageId,
        etapeDepartId: depart.id!,
        etapeArriveeId: arrivee.id!,
        mode: mode,
        distanceKm: distanceKm,
        dureeMinutes: dureeMinutesFinale,
        geometrieJson: Trajet.encodePoints(points),
        denivelePositifM: denivelePositif,
        deniveleNegatifM: deniveleNegatif,
        profilAltitudeJson: profilJson,
      ));
    }

    return echecs;
  }

  /// Distance a vol d'oiseau (formule de haversine) entre deux points.
  static double _distanceHaversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const rayonTerreKm = 6371.0;
    final dLat = _degEnRad(lat2 - lat1);
    final dLon = _degEnRad(lon2 - lon1);
    final a =
        (dLat / 2) * (dLat / 2) +
            _degEnRad(lat1) *
                _degEnRad(lat2) *
                (dLon / 2) *
                (dLon / 2);
    return 2 * rayonTerreKm * math.asin(math.sqrt(a));
  }

  static double _degEnRad(double deg) => deg * math.pi / 180.0;

  /// Duree d'un trajet de secours selon la vitesse moyenne du mode :
  /// parametres de l'utilisateur si disponibles, sinon vitesses
  /// classiques (voiture 80 km/h, velo 15 km/h, vtt 12 km/h, marche 4
  /// km/h).
  static int _dureeEstimeeMinutes(
    ModeTransport mode,
    double distanceKm,
    ParametresPlanification parametres,
  ) {
    double vitesse;
    switch (mode) {
      case ModeTransport.marche:
        vitesse = parametres.vitesseMarcheKmh > 0
            ? parametres.vitesseMarcheKmh
            : 4.0;
        break;
      case ModeTransport.velo:
        vitesse = parametres.vitesseVeloKmh > 0
            ? parametres.vitesseVeloKmh
            : 15.0;
        break;
      case ModeTransport.vtt:
        vitesse = 12.0;
        break;
      default:
        vitesse = 80.0;
        break;
    }
    return (distanceKm / vitesse * 60).round();
  }
}
