import '../db/trip_planner_database.dart';
import '../models/etape.dart';

/// Logique d'insertion "intelligente" d'une etape dans la timeline.
///
/// Lors de l'ajout d'une etape racine (pas de sous-etape), on determine
/// sa position dans la timeline :
///  1. par date d'arrivee : elle vient se placer entre les etapes dont
///     les dates l'encadrent (une etape ajoutee "au milieu" du voyage
///     se place donc au bon endroit, pas a la fin) ;
///  2. a date egale, avant l'etape suivante (ordre chronologique).
///
/// Les ordres persistes restent 0-based et consecutifs : on renumerate
/// toutes les etapes racines apres insertion.
class InsertionEtapeService {
  /// Calcule l'index d'insertion de [nouvelle] parmi [existantes]
  /// (racines uniquement), par date d'arrivee croissante.
  ///
  /// En cas d'egalite de date, l'etape est inseree apres les etapes de
  /// meme date (elle "arrive" apres celles deja planifiees ce jour-la).
  static int calculerIndexInsertion(
      List<Etape> existantes, Etape nouvelle) {
    if (nouvelle.parentId != null) {
      // Sous-etape : apres la derniere sous-etape du meme parent,
      // gere par l'appelant.
      return existantes.length;
    }
    var index = 0;
    for (final e in existantes) {
      if (e.parentId != null) continue; // sous-etapes exclues du tri racine
      if (_dateArrivee(e).isBefore(_dateArrivee(nouvelle)) ||
          _dateArrivee(e).isAtSameMomentAs(_dateArrivee(nouvelle))) {
        index++;
      } else {
        break;
      }
    }
    return index;
  }

  static DateTime _dateArrivee(Etape e) =>
      DateTime.tryParse(e.date) ?? DateTime(2999);

  /// Insere [nouvelle] au bon endroit dans la liste des etapes racines,
  /// renumerote tout et persiste. Renvoie la liste complete a jour.
  ///
  /// Les sous-etapes ne sont pas renumerotees : leur ordre est relatif
  /// a leur parent et gere par l'UI.
  static Future<List<Etape>> insererIntelligent(Etape nouvelle) async {
    final db = TripPlannerDatabase.instance;
    final existantes =
        await db.getEtapesForVoyage(nouvelle.voyageId);

    final racines =
        existantes.where((e) => e.parentId == null).toList();
    final sousEtapes = existantes.where((e) => e.parentId != null).toList();

    // Si l'etape existe deja (edition), on la remplace a sa place.
    racines.removeWhere((e) => e.id == nouvelle.id);

    if (nouvelle.parentId == null) {
      final index = calculerIndexInsertion(racines, nouvelle);
      racines.insert(index, nouvelle);
    } else {
      racines.add(nouvelle);
    }

    // Renumerotation des racines et persistance.
    for (var i = 0; i < racines.length; i++) {
      final maj = racines[i].ordre == i
          ? racines[i]
          : await _majOrdre(db, racines[i], i);
      racines[i] = maj;
    }

    return [...racines, ...sousEtapes]..sort((a, b) {
        if (a.parentId == null && b.parentId == null) {
          return a.ordre.compareTo(b.ordre);
        }
        return 0;
      });
  }

  static Future<Etape> _majOrdre(
      TripPlannerDatabase db, Etape e, int nouvelOrdre) async {
    final maj = e.copyWith(ordre: nouvelOrdre);
    await db.updateEtape(maj);
    return maj;
  }
}
