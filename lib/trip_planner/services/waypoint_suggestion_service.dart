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
/// Strategie de requete : le trace est echantillonne en ~50 centres
/// espaces regulierement (par distance, pas par index), puis une
/// seule requete Overpass utilise le filtre `around` avec tous ces
/// centres. On obtient ainsi un corridor continu autour de
/// l'itineraire, sans etre limite aux POI d'une enorme bbox englobante
/// (qui, pour un grand voyage, renvoie des POI partout sauf pres de
/// la route). Les ways/relations sont incluses (nwr) : beaucoup de
/// chateaux, cascades ou attractions sont traces comme des polygones
/// dans OSM ; "out center" fournit alors leur centre.
///
/// Les requetes sont limitees volontairement : elles ne sont lancees
/// que sur action explicite de l'utilisateur (jamais en continu), et
/// les resultats sont mis en cache en base (table waypoints) pour ne
/// pas re-interroger l'API a chaque ouverture de la carte.
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

  /// Nombre de centres vises pour le filtre `around` autour du trace.
  static const int _cibleCentres = 50;

  /// Categories OSM interessees, regroupees par cle : la cle et la
  /// valeur sont envoyees a Overpass sous forme de regex (une seule
  /// clause), et servent aussi a retrouver la categorie d'un POI
  /// retourne pour l'affichage.
  static const Map<String, String> _categoriesParCle = {
    'tourism': 'attraction|viewpoint|artwork',
    'natural': 'peak|waterfall|beach',
    'historic': 'monument|castle|ruins',
  };

  /// Retourne les POI dignes d'interet situes a moins de [rayonMetres]
  /// du trace passe en argument (liste de points [lat, lon], ordre du
  /// parcours). Le trace est echantillonne en centres espaces par
  /// distance, envoyes a Overpass dans une seule requete `around` ;
  /// les POI retournes sont re-filtres localement (filet de securite).
  Future<List<PoiSuggere>> suggererWaypoints({
    required List<List<double>> trace,
    required int rayonMetres,
  }) async {
    final centres = _echantillonnerTrace(trace, rayonMetres);
    if (centres.isEmpty) {
      throw SuggestionWaypointException(
        'Aucun trace disponible : calcule les trajets avant de demander '
        'des suggestions.',
      );
    }

    // Clause unique : la cle (tourism|natural|historic) et la valeur
    // (attraction|viewpoint|...) sont filtrees par regex, et le filtre
    // "around" cible chaque centre du trace. On ne garde que les POI
    // nommes : un POI sans nom n'est pas exploitable comme
    // suggestion affichable.
    final valeurs = _categoriesParCle.values.join('|');
    final centresListe = centres
        .map((p) => '${p[0].toStringAsFixed(5)},${p[1].toStringAsFixed(5)}')
        .join(',');
    final requete = '[out:json][timeout:60];'
        'nwr["name"]'
        '[~"^(tourism|natural|historic)\$"~"^($valeurs)\$"]'
        '(around:$rayonMetres,$centresListe);'
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
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw SuggestionWaypointException(
        'Impossible de contacter le service de suggestions '
        '(verifie ta connexion).',
      );
    }
    if (response.statusCode == 429) {
      throw SuggestionWaypointException(
        'Service de suggestions momentanement sature (limite d\'usage). '
        'Reessaie dans une minute.',
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
    // Overpass peut repondre 200 avec une erreur dans "remark" (ex:
    // timeout du serveur) : on la remonte plutot que de croire a une
    // absence de resultats.
    if (data['elements'] == null && data['remark'] != null) {
      throw SuggestionWaypointException(
        'Service de suggestions : ${data['remark']}',
      );
    }
    final elements = (data['elements'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final resultats = <PoiSuggere>[];
    final osmIdsDejaVus = <String>{};
    for (final element in elements) {
      final type = element['type'] as String? ?? 'node';
      final id = element['id']?.toString();
      if (id == null) continue;
      final osmId = '$type/$id';
      if (osmIdsDejaVus.contains(osmId)) continue;

      // Noeuds : lat/lon directs ; ways/relations : centre fourni par
      // "out center".
      final latDirect = element['lat'] as num?;
      final lonDirect = element['lon'] as num?;
      final centre = element['center'] as Map<String, dynamic>?;
      final lat = latDirect?.toDouble() ?? (centre?['lat'] as num?)?.toDouble();
      final lon = lonDirect?.toDouble() ?? (centre?['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      if (!_estProcheDuTrace(lat, lon, centres, rayonMetres)) continue;

      final tags =
          (element['tags'] as Map<String, dynamic>? ?? <String, dynamic>{});
      final nom = _nomAffichable(tags, osmId);
      final categorie = _categoriePrincipale(tags);

      osmIdsDejaVus.add(osmId);
      resultats.add(PoiSuggere(
        nom: nom,
        latitude: lat,
        longitude: lon,
        categorie: categorie,
        osmId: osmId,
      ));
    }
    return resultats;
  }

  /// Reduit le trace a un nombre borne de centres espaces par
  /// DISTANCE (et non par index) : on vise ~[_cibleCentres] centres,
  /// espaces d'au moins 2 km et d'au plus 15 km, de sorte que les
  /// rayons "around" couvrent un corridor continu autour du trace.
  /// Un trace court se contente de ses extremites.
  List<List<double>> _echantillonnerTrace(
    List<List<double>> trace,
    int rayonMetres,
  ) {
    final points =
        trace.where((p) => p.length >= 2).map((p) => [p[0], p[1]]).toList();
    if (points.isEmpty) return [];
    if (points.length == 1) return [points.first];

    var longueurMetres = 0.0;
    for (var i = 1; i < points.length; i++) {
      longueurMetres += _distanceApprocheeMetres(
        points[i - 1][0],
        points[i - 1][1],
        points[i][0],
        points[i][1],
      );
    }
    if (longueurMetres < rayonMetres * 2) {
      // Trace court : depart et arrivee suffisent a couvrir le corridor.
      return [points.first, points.last];
    }

    final espacement =
        (longueurMetres / _cibleCentres).clamp(2000.0, 15000.0).toDouble();
    final centres = <List<double>>[points.first];
    var distanceDepuisCentre = 0.0;
    for (var i = 1; i < points.length; i++) {
      distanceDepuisCentre += _distanceApprocheeMetres(
        points[i - 1][0],
        points[i - 1][1],
        points[i][0],
        points[i][1],
      );
      if (distanceDepuisCentre >= espacement) {
        centres.add(points[i]);
        distanceDepuisCentre = 0.0;
      }
    }
    if (centres.last != points.last) {
      centres.add(points.last);
    }
    return centres;
  }

  /// Vrai si le point est a moins de [rayonMetres] d'au moins un
  /// centre du trace. Overpass a deja filtre par "around" : ce filtre
  /// local est un simple filet de securite (avec une marge de 50% pour
  /// ne pas ecarter un POI legitime situe entre deux centres).
  bool _estProcheDuTrace(
    double lat,
    double lon,
    List<List<double>> centres,
    int rayonMetres,
  ) {
    final rayon = rayonMetres * 1.5;
    for (final p in centres) {
      if (_distanceApprocheeMetres(lat, lon, p[0], p[1]) <= rayon) {
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
  String _nomAffichable(Map<String, dynamic> tags, String osmId) {
    for (final cle in ['name:fr', 'name', 'ref']) {
      final valeur = tags[cle];
      if (valeur is String && valeur.isNotEmpty) return valeur;
    }
    final categorie = _categoriePrincipale(tags);
    if (categorie.isNotEmpty) return _libelleCategorie(categorie);
    return 'POI $osmId';
  }

  /// Premiere categorie OSM du POI qui correspond a une categorie
  /// connue, sous la forme 'cle=valeur' (ex: 'natural=waterfall').
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
