// Verification de la formule de haversine utilisee pour les distances
// a vol d'oiseau (trajets de secours du trip planner, transferts
// manuels entre etapes).
//
// Reference : une precedente version oubliait les fonctions sin/cos
// dans le terme de longitude (produit de latitudes en radians a la
// place), ce qui sous-estimait fortement les distances est-ouest aux
// latitudes moyennes/hautes (ex : ~3340 "km" affiches pour New York ->
// Los Angeles, reels ~3974 km, soit a peu pres la valeur en miles).

import 'package:flutter_test/flutter_test.dart';
import 'package:les_baroudeurs/trip_planner/services/trip_calculation_service.dart';

void main() {
  group('distanceHaversineKm', () {
    test('New York (JFK) -> Los Angeles (LAX) ~ 3974 km', () {
      final km = TripCalculationService.distanceHaversineKm(
        40.6413, -73.7781,
        33.9416, -118.4085,
      );
      expect(km, closeTo(3974, 30));
    });

    test('Paris -> Marseille ~ 660 km', () {
      final km = TripCalculationService.distanceHaversineKm(
        48.8566, 2.3522,
        43.2965, 5.3698,
      );
      expect(km, closeTo(660, 15));
    });

    test('distance nulle entre deux points identiques', () {
      expect(
        TripCalculationService.distanceHaversineKm(45.0, 5.0, 45.0, 5.0),
        0,
      );
    });

    test('un degre de latitude vaut ~111 km quelle que soit la longitude', () {
      // Le terme de latitude ne depend pas de la longitude : verifie
      // que la composante nord-sud n'est pas faussee.
      final km = TripCalculationService.distanceHaversineKm(
        10.0, -120.0,
        11.0, -120.0,
      );
      expect(km, closeTo(111.2, 1.0));
    });
  });
}
