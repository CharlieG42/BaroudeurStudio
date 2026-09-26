import '../db/trip_planner_database.dart';
import '../models/etape.dart';
import '../models/trajet.dart';
import 'osrm_service.dart';

/// Orchestre le recalcul des trajets entre etapes consecutives d'un
/// voyage. A appeler apres tout ajout, suppression ou reordonnancement
/// d'etape.
///
/// Pour chaque paire d'etapes consecutives, le mode de transport deja
/// choisi est respecte : voiture/velo/marche sont recalcules via OSRM
/// (avec le profil correspondant), tandis qu'avion/train/bus/autre,
/// saisis manuellement par l'utilisateur (voir [ModeTransportInfo]),
/// ne sont jamais recalcules ni ecrases. Une paire sans trajet existant
/// est calculee par defaut en voiture.
class TripCalculationService {
  final OsrmService _osrm;
  final TripPlannerDatabase _db;

  TripCalculationService({
    OsrmService? osrmService,
    TripPlannerDatabase? database,
  })  : _osrm = osrmService ?? OsrmService(),
        _db = database ?? TripPlannerDatabase.instance;

  /// Recalcule les trajets auto-calcules (voiture/velo/marche) du
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

      final resultat = await _osrm.calculerItineraire(
        mode: mode,
        latDepart: depart.latitude,
        lonDepart: depart.longitude,
        latArrivee: arrivee.latitude,
        lonArrivee: arrivee.longitude,
      );

      if (resultat == null) {
        echecs++;
        continue;
      }

      await _db.upsertTrajet(Trajet(
        voyageId: voyageId,
        etapeDepartId: depart.id!,
        etapeArriveeId: arrivee.id!,
        mode: mode,
        distanceKm: resultat.distanceKm,
        dureeMinutes: resultat.dureeMinutes,
        geometrieJson: Trajet.encodePoints(resultat.points),
      ));
    }

    return echecs;
  }
}
