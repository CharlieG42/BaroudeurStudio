import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Un point d'altitude du profil d'un itineraire : distance cumulee
/// depuis le depart (km) et altitude (metres).
class PointAltitude {
  final double distanceKm;
  final double altitudeM;

  PointAltitude({required this.distanceKm, required this.altitudeM});
}

/// Resultat du calcul d'elevation pour un trace complet.
class ProfilAltitude {
  final List<PointAltitude> points;
  final int denivelePositifM;
  final int deniveleNegatifM;

  ProfilAltitude({
    required this.points,
    required this.denivelePositifM,
    required this.deniveleNegatifM,
  });

  /// Representation JSON compacte pour stockage en base :
  /// liste de couples [distance_km, altitude_m].
  List<List<double>> toList() =>
      points.map((p) => [p.distanceKm, p.altitudeM]).toList();
}

/// Service d'elevation : interroge l'API publique Open-Meteo
/// (https://api.open-meteo.com/v1/elevation), fondee sur le modele
/// numerique Copernicus DEM GLO-90 (resolution 90 m, couverture
/// mondiale). Gratuite sans cle d'API pour un usage non commercial,
/// elle accepte des lots d'au plus 100 coordonnees par requete : le
/// trace est donc echantillonne avant l'appel, puis decoupe en lots.
class ElevationService {
  static const String baseUrl = 'https://api.open-meteo.com/v1/elevation';

  /// Nombre maximal de coordonnees par requete Open-Meteo.
  static const int _maxPointsParRequete = 100;

  /// Nombre de points vises pour un trace, tous lots confondus :
  /// au-dela, le trace est echantillonne. Suffisant pour un graphique
  /// lisible tout en restant leger.
  static const int _ciblePointsProfil = 100;

  Future<ProfilAltitude?> calculerProfil(
    List<List<double>> trace,
  ) async {
    final points = _echantillonner(trace);
    if (points.isEmpty) return null;

    final altitudes = <double>[];
    for (var i = 0; i < points.length; i += _maxPointsParRequete) {
      final lot = points.skip(i).take(_maxPointsParRequete).toList();
      final resultats = await _altitudesPourLot(lot);
      if (resultats == null) {
        return null;
      }
      altitudes.addAll(resultats);
    }

    var distanceCumulee = 0.0;
    final profil = <PointAltitude>[];
    for (var i = 0; i < points.length; i++) {
      if (i > 0) {
        distanceCumulee += _distanceMetres(
          points[i - 1][0],
          points[i - 1][1],
          points[i][0],
          points[i][1],
        ) / 1000.0;
      }
      profil.add(PointAltitude(
        distanceKm: distanceCumulee,
        altitudeM: altitudes[i],
      ));
    }

    var positif = 0.0;
    var negatif = 0.0;
    for (var i = 1; i < altitudes.length; i++) {
      final delta = altitudes[i] - altitudes[i - 1];
      if (delta > 0) {
        positif += delta;
      } else {
        negatif -= delta;
      }
    }

    return ProfilAltitude(
      points: profil,
      denivelePositifM: positif.round(),
      deniveleNegatifM: negatif.round(),
    );
  }

  /// Retourne les altitudes des points donnes ([lat, lon]), ou null si
  /// l'API echoue.
  Future<List<double>?> _altitudesPourLot(
    List<List<double>> points,
  ) async {
    final lats = points.map((p) => p[0].toString()).join(',');
    final lons = points.map((p) => p[1].toString()).join(',');
    try {
      final response = await http
          .get(Uri.parse('$baseUrl?latitude=$lats&longitude=$lons'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elevations = data['elevation'] as List<dynamic>?;
      if (elevations == null || elevations.length != points.length) {
        return null;
      }
      return elevations
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Reduit le trace a un nombre borne de points equidistants (par
  /// distance cumulee), pour limiter le volume envoye a l'API et
  /// obtenir un graphique lisse.
  List<List<double>> _echantillonner(List<List<double>> trace) {
    final points = trace
        .where((p) => p.length >= 2)
        .map((p) => [p[0], p[1]])
        .toList();
    if (points.length <= _ciblePointsProfil) return points;

    var longueurTotale = 0.0;
    for (var i = 1; i < points.length; i++) {
      longueurTotale += _distanceMetres(
        points[i - 1][0],
        points[i - 1][1],
        points[i][0],
        points[i][1],
      );
    }
    final pas = longueurTotale / (_ciblePointsProfil - 1);
    final echantillons = <List<double>>[points.first];
    var distanceDepuis = 0.0;
    for (var i = 1; i < points.length; i++) {
      distanceDepuis += _distanceMetres(
        points[i - 1][0],
        points[i - 1][1],
        points[i][0],
        points[i][1],
      );
      if (distanceDepuis >= pas) {
        echantillons.add(points[i]);
        distanceDepuis = 0.0;
      }
    }
    if (echantillons.last != points.last) {
      echantillons.add(points.last);
    }
    return echantillons;
  }

  /// Distance en metres entre deux points lat/lon (haversine).
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
}
