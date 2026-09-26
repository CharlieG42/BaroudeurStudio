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
/// Utilise par defaut le serveur de demonstration public
/// (router.project-osrm.org), mis a disposition gracieusement par le
/// projet OSRM/FOSSGIS pour un usage raisonnable et non commercial
/// (voir https://github.com/Project-OSRM/osrm-backend/wiki/Api-usage-policy).
/// Ce serveur expose trois profils : voiture, velo et marche. Pour un
/// usage intensif ou une distribution large de l'application, il est
/// recommande d'heberger sa propre instance OSRM et de changer
/// [baseUrl] ci-dessous.
class OsrmService {
  static const String baseUrl = 'https://router.project-osrm.org';

  /// User-Agent obligatoire pour respecter la politique d'usage du
  /// serveur de demonstration OSRM.
  static const Map<String, String> _headers = {
    'User-Agent': 'BaroudeurStudio-TripPlanner/1.0 (usage personnel)',
  };

  /// Nom du profil OSRM correspondant au mode de transport. Ne
  /// s'applique qu'aux modes auto-calcules (voir [ModeTransportInfo]).
  String _profil(ModeTransport mode) {
    switch (mode) {
      case ModeTransport.voiture:
        return 'driving';
      case ModeTransport.velo:
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
  }) async {
    final coords = '$lonDepart,$latDepart;$lonArrivee,$latArrivee';
    final uri = Uri.parse(
      '$baseUrl/route/v1/${_profil(mode)}/$coords'
      '?overview=full&geometries=geojson&alternatives=false&steps=false',
    );

    try {
      final response = await http
          .get(uri, headers: _headers)
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
