import 'dart:math' as math;

/// Estimation hors ligne du deplacement entre deux points proches
/// d'une meme visite (etape parente -> sous-etape, ou sous-etape ->
/// sous-etape suivante).
///
/// Les sous-etapes ne participent pas au calcul d'itineraire (seules
/// les etapes principales sont routees) : on estime donc la distance a
/// vol d'oiseau, corrigee d'un facteur de detour, et la duree selon un
/// mode deduit de la distance (a pied pour les courtes liaisons, en
/// voiture au-dela).
class LiaisonSousEtape {
  /// Distance estimee en km (vol d'oiseau x facteur de detour).
  final double distanceKm;

  /// Duree estimee en minutes.
  final int dureeMinutes;

  /// Vrai si la liaison est estimee a pied, faux si en voiture.
  final bool aPied;

  const LiaisonSousEtape({
    required this.distanceKm,
    required this.dureeMinutes,
    required this.aPied,
  });

  /// Distance en dessous de laquelle deux points sont consideres comme
  /// le meme lieu (sous-etape creee a la position de la visite).
  static const double seuilMemeLieuKm = 0.05;

  /// Vrai si les deux points sont au meme endroit.
  bool get memeLieu => distanceKm < seuilMemeLieuKm;

  /// Rapport moyen entre distance reelle et vol d'oiseau en ville.
  static const double facteurDetour = 1.3;

  /// Au-dela de cette distance estimee, la liaison est supposee en
  /// voiture.
  static const double seuilMarcheKm = 2.0;

  /// Vitesse moyenne en voiture pour des trajets locaux (ville,
  /// routes secondaires, stationnement compris).
  static const double vitesseVoitureLocaleKmh = 30.0;

  /// Estime la liaison entre deux points. [vitesseMarcheKmh] vient des
  /// parametres de planification (4,5 km/h par defaut).
  factory LiaisonSousEtape.estimer({
    required double latDepart,
    required double lonDepart,
    required double latArrivee,
    required double lonArrivee,
    double vitesseMarcheKmh = 4.5,
  }) {
    final volOiseauKm =
        distanceHaversineKm(latDepart, lonDepart, latArrivee, lonArrivee);
    final distanceKm = volOiseauKm * facteurDetour;
    final aPied = distanceKm <= seuilMarcheKm;
    final vitesse = aPied
        ? (vitesseMarcheKmh > 0 ? vitesseMarcheKmh : 4.5)
        : vitesseVoitureLocaleKmh;
    final duree = distanceKm < seuilMemeLieuKm
        ? 0
        : math.max(1, (distanceKm / vitesse * 60).round());
    return LiaisonSousEtape(
      distanceKm: distanceKm,
      dureeMinutes: duree,
      aPied: aPied,
    );
  }

  /// Distance a vol d'oiseau entre deux points, en km.
  static double distanceHaversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const rayonTerreKm = 6371.0;
    double rad(double deg) => deg * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return rayonTerreKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Libelle court : "≈ 1,2 km · 16min a pied", ou "Meme lieu".
  String libelle(String Function(int minutes) formatDuree) {
    if (memeLieu) return 'Meme lieu';
    final distance = distanceKm < 1
        ? '${(distanceKm * 1000 / 10).round() * 10} m'
        : '${distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '≈ $distance · ${formatDuree(dureeMinutes)} '
        '${aPied ? 'a pied' : 'en voiture'}';
  }
}
