import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trajet.dart';

/// Resultat d'un calcul d'itineraire : distance, duree estimee et
/// trace geographique (liste de points lat/lon dans l'ordre du parcours).
class ResultatItineraire {
  final double distanceKm;
  final int dureeMinutes;
  final List<List<double>> points; // [ [lat, lon], ... ]

  ResultatItineraire({
    required this.distanceKm,
    required this.dureeMinutes,
    required this.points,
  });
}

/// Client pour l'API de routage OSRM (Open Source Routing Machine).
///
/// Utilise le serveur public de la FOSSGIS (routing.openstreetmap.de),
/// qui met a disposition trois instances avec de vrais profils :
/// voiture (routed-car), velo (routed-bike) et marche (routed-foot).
///
/// Attention : l'ancien serveur de demonstration router.project-osrm.org
/// ne servait en realite que le profil voiture ; les prefixes /bike et
/// /foot de l'URL etaient ignores et renvoyaient exactement la meme
/// route et la meme duree que la voiture (probleme connu du serveur de
/// demo). C'est pourquoi ce service interroge desormais la FOSSGIS :
/// chaque mode a son propre graphe de routage (la marche emprunte les
/// chemins et sentiers, le velo les pistes cyclables).
///
/// Pour un usage intensif ou une distribution large de l'application,
/// il est recommande d'heberger sa propre instance OSRM et de changer
/// les constantes ci-dessous.
class OsrmService {
  /// Squelette d'URL par profil de routage (le {profil} et les
  /// coordonnees sont inseres au moment de la requete).
  static const String baseUrlPattern =
      'https://routing.openstreetmap.de/routed-{profil}/route/v1/driving';

  /// Instance FOSSGIS correspondant au mode de transport. Ne
  /// s'applique qu'aux modes auto-calcules (voir [ModeTransportInfo]).
  String _instance(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return 'car';
      case ModeTransport.velo:
      case ModeTransport.vtt:
        return 'bike';
      case ModeTransport.marche:
        return 'foot';
      case ModeTransport.avion:
      case ModeTransport.train:
      case ModeTransport.bus:
      case ModeTransport.autre:
        throw ArgumentError(
          'Mode $mode non routable via OSRM (transfert manuel attendu).',
        );
    }
  }

  /// Calcule l'itineraire entre deux points pour le profil correspondant
  /// au [mode] donne (voiture, velo ou marche). Retourne null en cas
  /// d'echec (pas de reseau, aucune route trouvee...).
  Future<ResultatItineraire?> calculerItineraire({
    required ModeTransport mode,
    required double latDepart,
    required double lonDepart,
    required double latArrivee,
    required double lonArrivee,
    bool eviterAutoroutes = false,
    bool eviterPeages = false,
  }) async {
    final coords = '$lonDepart,$latDepart;$lonArrivee,$latArrivee';
    final url = baseUrlPattern.replaceFirst('{profil}', _instance(mode));
    // Options d'exclusion supportees par le profil voiture FOSSGIS :
    // motorway (autoroutes) et toll (peage). Sans effet reel sur les
    // profils bike/foot (pas d'autoroutes dans leur graphe), on ne
    // les envoie que pour la voiture pour garder des URLs simples.
    final excludes = <String>[
      if (mode == ModeTransport.voiture && eviterAutoroutes) 'motorway',
      if (mode == ModeTransport.voiture && eviterPeages) 'toll',
    ];
    final parametresUrl = [
      'overview=full',
      'geometries=geojson',
      'alternatives=false',
      'steps=false',
      if (excludes.isNotEmpty) 'exclude=${excludes.join(',')}',
    ].join('&');
    final uri = Uri.parse('$url/$coords?$parametresUrl');
    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final distanceMetres = (route['distance'] as num).toDouble();
      final dureeSecondes = (route['duration'] as num).toDouble();
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;

      // GeoJSON fournit les coordonnees en [lon, lat] : on les remet
      // dans l'ordre [lat, lon] utilise partout ailleurs dans le module.
      final points = coordinates
          .map((c) => [
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ])
          .toList();

      return ResultatItineraire(
        distanceKm: distanceMetres / 1000.0,
        dureeMinutes: (dureeSecondes / 60.0).round(),
        points: points,
      );
    } catch (_) {
      return null;
    }
  }
}
