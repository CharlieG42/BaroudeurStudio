import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/waypoint.dart';

/// Un POI retourne par Overpass avant persistance en base.
class PoiSuggere {
  final String nom;
  final double latitude;
  final double longitude;
  final String categorie; // ex: 'tourism=viewpoint'
  final String osmId;

  PoiSuggere({
    required this.nom,
    required this.latitude,
    required this.longitude,
    required this.categorie,
    required this.osmId,
  });

  Waypoint toWaypoint(int voyageId) {
    return Waypoint(
      voyageId: voyageId,
      nom: nom,
      latitude: latitude,
      longitude: longitude,
      source: SourceWaypoint.recommande,
      categorie: categorie,
      osmId: osmId,
    );
  }
}

/// Exception levee lorsque la requete Overpass echoue (reseau,
/// timeout, erreur serveur...), a distinguer d'une recherche qui
/// aboutit simplement a aucun resultat.
class SuggestionWaypointException implements Exception {
  final String message;
  SuggestionWaypointException(this.message);
  @override
  String toString() => message;
}

/// Client pour l'API Overpass (donnees OpenStreetMap), qui permet de
/// trouver les points d'interet situes a proximite du trace d'un
/// voyage : points de vue, cascades, sommets, monuments, attractions...
///
/// Les requetes sont limitees volontairement : elles ne sont lancees
/// que sur action explicite de l'utilisateur (jamais en continu), le
/// trace est echantillonne avant interrogation et les resultats sont
/// mis en cache en base (table waypoints) pour ne pas re-interroger
/// l'API a chaque ouverture de la carte.
///
/// Politique d'usage de overpass-api.de : usage raisonnable, pas
/// d'usage intensif automatise. Pour un usage intensif, heberger sa
/// propre instance Overpass et changer [baseUrl].
class WaypointSuggestionService {
  static const String baseUrl = 'https://overpass-api.de/api/interpreter';

  static const Map<String, String> _headers = {
    'User-Agent': 'BaroudeurStudio-TripPlanner/1.0 (usage personnel)',
  };

  /// Nombre maximal de POI retournes par la requete Overpass, pour
  /// borner le temps de reponse et le volume de donnees.
  static const int maxSuggestions = 60;

  /// Regroupement des categories OSM interessees par cle OSM : chaque
  /// entree devient une clause regex (union des valeurs) dans la
  /// requete Overpass.
  static const Map<String, String> _categoriesParCle = {
    'tourism': 'attraction|viewpoint|artwork',
    'natural': 'peak|waterfall|beach',
    'historic': 'monument|castle|ruins',
  };

  /// Retourne les POI dignes d'interet situes a moins de [rayonMetres]
  /// du trace passe en argument (liste de points [lat, lon], ordre du
  /// parcours). Le trace est echantillonne puis envoye a Overpass
  /// dans une seule requete englobante ; les POI retournes sont
  /// ensuite filtres localement sur leur distance reelle au trace.
  Future<List<PoiSuggere>> suggererWaypoints({
    required List<List<double>> trace,
    required int rayonMetres,
  }) async {
    final echantillons = _echantillonnerTrace(trace);
    if (echantillons.isEmpty) {
      throw SuggestionWaypointException(
        'Aucun trace disponible : calcule les trajets avant de demander '
        'des suggestions.',
      );
    }

    final bounds = _boundsTrace(echantillons);
    final bbox =
        '(${bounds.sud},${bounds.ouest},${bounds.nord},${bounds.est})';
    // Union des clauses par cle OSM (le ";" entre clauses = OU en
    // Overpass QL). On ne garde que les POI nommes : un POI sans nom
    // n'est pas exploitable comme suggestion affichable.
    final clauses = _categoriesParCle.entries
        .map((e) =>
            'node["name"]["${e.key}"~"^(${e.value})$"]$bbox;')
        .join('');
    final requete = '[out:json][timeout:25];'
        '($clauses);'
        'out center $maxSuggestions;';

    final uri = Uri.parse(baseUrl);

    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              ..._headers,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': requete},
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw SuggestionWaypointException(
        'Impossible de contacter le service de suggestions '
        '(verifie ta connexion).',
      );
    }
    if (response.statusCode != 200) {
      throw SuggestionWaypointException(
        'Service de suggestions indisponible (code '
        '${response.statusCode}). Reessaie plus tard.',
      );
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw SuggestionWaypointException(
        'Reponse du service de suggestions illisible.',
      );
    }
    final elements = (data['elements'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final resultats = <PoiSuggere>[];
    final osmIdsDejaVus = <String>{};
    for (final element in elements) {
      final id = element['id']?.toString();
      if (id == null || osmIdsDejaVus.contains(id)) continue;
      final lat = (element['lat'] as num?)?.toDouble();
      final lon = (element['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      if (!_estProcheDuTrace(lat, lon, echantillons, rayonMetres)) continue;

      final tags =
          (element['tags'] as Map<String, dynamic>? ?? <String, dynamic>{});
      final nom = _nomAffichable(tags, id);
      final categorie = _categoriePrincipale(tags);

      osmIdsDejaVus.add(id);
      resultats.add(PoiSuggere(
        nom: nom,
        latitude: lat,
        longitude: lon,
        categorie: categorie,
        osmId: id,
      ));
    }
    return resultats;
  }

  /// Reduit le trace a un nombre borne de points representatifs,
  /// preserves dans l'ordre du parcours. Pour un trace court, tous
  /// les points sont conserves ; sinon on garde un point tous les
  /// ~[pasApproximatif] points.
  List<List<double>> _echantillonnerTrace(List<List<double>> trace) {
    final points =
        trace.where((p) => p.length >= 2).map((p) => [p[0], p[1]]).toList();
    if (points.isEmpty) return [];
    const cible = 150;
    if (points.length <= cible) return points;
    final pas = (points.length / cible).ceil();
    final echantillons = <List<double>>[
      points.first,
    ];
    for (var i = pas; i < points.length; i += pas) {
      echantillons.add(points[i]);
    }
    if (echantillons.last != points.last) {
      echantillons.add(points.last);
    }
    return echantillons;
  }

  _Bounds _boundsTrace(List<List<double>> points) {
    var nord = -90.0;
    var sud = 90.0;
    var est = -180.0;
    var ouest = 180.0;
    for (final p in points) {
      if (p[0] > nord) nord = p[0];
      if (p[0] < sud) sud = p[0];
      if (p[1] > est) est = p[1];
      if (p[1] < ouest) ouest = p[1];
    }
    // Marge d'un demi-degre (~55 km) autour du trace, pour couvrir les
    // POI situes un peu au large de la route sans interroger une zone
    // disproportionnee.
    const marge = 0.5;
    return _Bounds(
      nord: math.min(90, nord + marge),
      sud: math.max(-90, sud - marge),
      est: math.min(180, est + marge),
      ouest: math.max(-180, ouest - marge),
    );
  }

  /// Vrai si le point est a moins de [rayonMetres] d'au moins un point
  /// du trace echantillonne (distance approchee, suffisante ici car
  /// la requete Overpass a deja borne la zone).
  bool _estProcheDuTrace(
    double lat,
    double lon,
    List<List<double>> echantillons,
    int rayonMetres,
  ) {
    for (final p in echantillons) {
      if (_distanceApprocheeMetres(lat, lon, p[0], p[1]) <= rayonMetres) {
        return true;
      }
    }
    return false;
  }

  /// Distance en metres entre deux points lat/lon (formule de la
  /// haversine, suffisante pour un filtre de proximite).
  double _distanceApprocheeMetres(
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

  /// Nom lisible d'un POI a partir de ses tags OSM, avec repli sur
  /// la categorie ou l'identifiant si le POI n'a pas de nom.
  String _nomAffichable(Map<String, dynamic> tags, String id) {
    for (final cle in ['name:fr', 'name', 'ref']) {
      final valeur = tags[cle];
      if (valeur is String && valeur.isNotEmpty) return valeur;
    }
    final categorie = _categoriePrincipale(tags);
    if (categorie.isNotEmpty) return _libelleCategorie(categorie);
    return 'POI $id';
  }

  /// Premiere categorie OSM du POI qui correspond a un filtre connu,
  /// sous la forme 'cle=valeur' (ex: 'natural=waterfall').
  String _categoriePrincipale(Map<String, dynamic> tags) {
    for (final entree in _categoriesParCle.entries) {
      final valeurs = entree.value.split('|');
      for (final valeur in valeurs) {
        if (tags[entree.key] == valeur) return '${entree.key}=$valeur';
      }
    }
    return '';
  }

  String _libelleCategorie(String categorie) {
    switch (categorie) {
      case 'tourism=attraction':
        return 'Attraction';
      case 'tourism=viewpoint':
        return 'Point de vue';
      case 'tourism=artwork':
        return 'Oeuvre d\'art';
      case 'natural=peak':
        return 'Sommet';
      case 'natural=waterfall':
        return 'Cascade';
      case 'natural=beach':
        return 'Plage';
      case 'historic=monument':
        return 'Monument';
      case 'historic=castle':
        return 'Chateau';
      case 'historic=ruins':
        return 'Ruines';
      default:
        return 'Point d\'interet';
    }
  }
}

class _Bounds {
  final double nord;
  final double sud;
  final double est;
  final double ouest;
  _Bounds({
    required this.nord,
    required this.sud,
    required this.est,
    required this.ouest,
  });
}
