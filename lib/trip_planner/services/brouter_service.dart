import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trajet.dart';
import 'osrm_service.dart';

/// Client pour l'API BRouter (https://brouter.de/brouter), moteur de
/// routage OpenStreetMap specialise velo, avec des profils
/// configurables. Le profil public "mtb" (VTT) favorise les chemins et
/// singletracks, la ou les profils velo classiques preferent les
/// routes et pistes cyclables : c'est ce qui distingue le mode
/// [ModeTransport.vtt] du mode [ModeTransport.velo] dans l'application.
///
/// Si BRouter est indisponible (pas de reseau, service en panne), le
/// calcul retombe sur le profil velo d'OSRM FOSSGIS :
/// itineraire routier classique, moins adapte au VTT mais toujours
/// exploitable.
class BrouterService {
  static const String baseUrl = 'https://brouter.de/brouter';

  /// Profil VTT : favorise les chemins (pistes forestieres,
  /// singletracks) par rapport aux routes.
  static const String _profilVtt = 'mtb';

  static const Map<String, String> _headers = {
    'User-Agent': 'BaroudeurStudio-TripPlanner/1.0 (usage personnel)',
  };

  final OsrmService _osrm;

  BrouterService({OsrmService? osrmService})
      : _osrm = osrmService ?? OsrmService();

  /// Calcule l'itineraire VTT entre deux points. Tente d'abord BRouter
  /// (profil mtb) ; en cas d'echec, retombe sur le profil velo de
  /// OSRM pour ne jamais laisser un trajet VTT sans trace.
  Future<ResultatItineraire?> calculerItineraireVtt({
    required double latDepart,
    required double lonDepart,
    required double latArrivee,
    required double lonArrivee,
  }) async {
    final resultatBrouter = await _calculerViaBrouter(
      latDepart: latDepart,
      lonDepart: lonDepart,
      latArrivee: latArrivee,
      lonArrivee: lonArrivee,
    );
    if (resultatBrouter != null) return resultatBrouter;

    return _osrm.calculerItineraire(
      mode: ModeTransport.velo,
      latDepart: latDepart,
      lonDepart: lonDepart,
      latArrivee: latArrivee,
      lonArrivee: lonArrivee,
    );
  }

  Future<ResultatItineraire?> _calculerViaBrouter({
    required double latDepart,
    required double lonDepart,
    required double latArrivee,
    required double lonArrivee,
  }) async {
    final lonlats = '$lonDepart,$latDepart|$lonArrivee,$latArrivee';
    final uri = Uri.parse(
      '$baseUrl?lonlats=$lonlats'
      '&profile=$_profilVtt&alternativeidx=0&format=geojson',
    );
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;
      final feature = features.first as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>?;
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? const [];
      if (coordinates.isEmpty || properties == null) return null;

      final distanceMetres = (properties['track-length'] as num?)?.toDouble();
      final tempsSecondes = (properties['total-time'] as num?)?.toDouble();
      if (distanceMetres == null || tempsSecondes == null) return null;

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
        dureeMinutes: (tempsSecondes / 60.0).round(),
        points: points,
      );
    } catch (_) {
      return null;
    }
  }
}
