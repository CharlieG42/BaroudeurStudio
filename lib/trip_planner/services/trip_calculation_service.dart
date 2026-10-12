import 'dart:convert';

import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
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
    final etapes = await _db.getEtapesForVoyage(voyageId);
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
    for (var i = 0; i < etapes.length - 1; i++) {
      final Etape depart = etapes[i];
      final Etape arrivee = etapes[i + 1];
      if (depart.id == null || arrivee.id == null) continue;

      final cle = '${depart.id}-${arrivee.id}';
      final mode = modeParPaire[cle] ?? ModeTransport.voiture;

      if (!mode.estAutoCalcule) {
        continue; // transfert manuel : on ne touche pas.
      }

      final resultat = mode == ModeTransport.vtt
          ? await _brouter.calculerItineraireVtt(
              latDepart: depart.latitude,
              lonDepart: depart.longitude,
              latArrivee: arrivee.latitude,
              lonArrivee: arrivee.longitude,
            )
          : await _osrm.calculerItineraire(
              mode: mode,
              latDepart: depart.latitude,
              lonDepart: depart.longitude,
              latArrivee: arrivee.latitude,
              lonArrivee: arrivee.longitude,
              eviterAutoroutes: parametres.eviterAutoroutes,
              eviterPeages: parametres.eviterPeages,
            );

      if (resultat == null) {
        echecs++;
        continue;
      }

      // Correction de la duree selon les vitesses moyennes de
      // l'utilisateur : les profils de routage supposent un terrain
      // plat et un rythme soutenu ; un randonneur en montagne ou un
      // cyclotouriste charge est plus lent.
      var dureeMinutes = resultat.dureeMinutes;
      if (mode == ModeTransport.marche &&
          parametres.vitesseMarcheKmh > 0) {
        dureeMinutes =
            (resultat.distanceKm / parametres.vitesseMarcheKmh * 60)
                .round();
      } else if (mode == ModeTransport.velo &&
          parametres.vitesseVeloKmh > 0) {
        dureeMinutes =
            (resultat.distanceKm / parametres.vitesseVeloKmh * 60).round();
      }

      // Denivele et profil d'altitude du trace (best effort : sans
      // reseau, le trajet reste exploitable, simplement sans profil).
      var denivelePositif = 0;
      var deniveleNegatif = 0;
      var profilJson = '[]';
      if (resultat.points.isNotEmpty) {
        final profil = await _elevation.calculerProfil(resultat.points);
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
        distanceKm: resultat.distanceKm,
        dureeMinutes: dureeMinutes,
        geometrieJson: Trajet.encodePoints(resultat.points),
        denivelePositifM: denivelePositif,
        deniveleNegatifM: deniveleNegatif,
        profilAltitudeJson: profilJson,
      ));
    }

    return echecs;
  }
}
