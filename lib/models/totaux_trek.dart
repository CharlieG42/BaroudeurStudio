import 'jour_trek.dart';

/// Totaux d'un trek calcules a partir de ses jours (somme des
/// distances et denivelés saisis ou importes depuis un GPX).
///
/// Les valeurs saisies a la main dans la fiche du trek restent
/// prioritaires a l'affichage : ces totaux servent de valeur par
/// defaut quand elles sont vides, et de source au bouton
/// "Calculer depuis les jours" du formulaire du trek.
class TotauxTrek {
  /// Somme des distances des jours renseignes, ou null si aucun jour
  /// n'a de distance.
  final double? distanceKm;

  /// Somme des denivelés positifs, ou null si aucun jour n'en a.
  final int? denivelePositifM;

  /// Somme des denivelés negatifs, ou null si aucun jour n'en a.
  final int? deniveleNegatifM;

  /// Nombre de jours du trek.
  final int nombreJours;

  /// Nombre de jours ayant une trace GPX.
  final int nombreJoursAvecGpx;

  const TotauxTrek({
    this.distanceKm,
    this.denivelePositifM,
    this.deniveleNegatifM,
    this.nombreJours = 0,
    this.nombreJoursAvecGpx = 0,
  });

  factory TotauxTrek.depuisJours(List<JourTrek> jours) {
    double? distance;
    int? positif;
    int? negatif;
    var avecGpx = 0;
    for (final jour in jours) {
      if (jour.distanceKm != null) {
        distance = (distance ?? 0) + jour.distanceKm!;
      }
      if (jour.denivelePositifM != null) {
        positif = (positif ?? 0) + jour.denivelePositifM!;
      }
      if (jour.deniveleNegatifM != null) {
        negatif = (negatif ?? 0) + jour.deniveleNegatifM!;
      }
      if (jour.cheminGpx != null && jour.cheminGpx!.isNotEmpty) {
        avecGpx++;
      }
    }
    return TotauxTrek(
      // Arrondi a 10 m pres pour eviter les 12.300000000000001 km.
      distanceKm: distance == null ? null : (distance * 100).round() / 100,
      denivelePositifM: positif,
      deniveleNegatifM: negatif,
      nombreJours: jours.length,
      nombreJoursAvecGpx: avecGpx,
    );
  }

  /// Vrai si au moins une valeur a pu etre calculee.
  bool get estRenseigne =>
      distanceKm != null || denivelePositifM != null || deniveleNegatifM != null;
}

/// Formate une distance en km pour l'affichage ("12,4 km", "8 km").
String formaterDistanceKm(double km) {
  final arrondi = (km * 10).round() / 10;
  final texte = arrondi == arrondi.roundToDouble()
      ? arrondi.toStringAsFixed(0)
      : arrondi.toStringAsFixed(1);
  return '${texte.replaceAll('.', ',')} km';
}
