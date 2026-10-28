// Tests de l'estimation des liaisons entre une visite et ses
// sous-etapes (distance a vol d'oiseau corrigee, mode et duree).

import 'package:flutter_test/flutter_test.dart';
import 'package:les_baroudeurs/trip_planner/services/liaison_sous_etape_service.dart';

String _duree(int minutes) => '${minutes}min';

void main() {
  test('meme lieu : distance nulle, duree nulle', () {
    final l = LiaisonSousEtape.estimer(
      latDepart: 45.0,
      lonDepart: 6.0,
      latArrivee: 45.0,
      lonArrivee: 6.0,
    );
    expect(l.memeLieu, isTrue);
    expect(l.dureeMinutes, 0);
    expect(l.libelle(_duree), 'Meme lieu');
  });

  test('courte liaison estimee a pied avec la vitesse de marche', () {
    // ~1,11 km a vol d'oiseau vers le nord -> ~1,45 km estimes.
    final l = LiaisonSousEtape.estimer(
      latDepart: 45.00,
      lonDepart: 6.0,
      latArrivee: 45.01,
      lonArrivee: 6.0,
      vitesseMarcheKmh: 4.5,
    );
    expect(l.aPied, isTrue);
    expect(l.distanceKm, closeTo(1.445, 0.01));
    expect(l.dureeMinutes, 19);
    expect(l.libelle(_duree), '≈ 1,4 km · 19min a pied');
  });

  test('liaison longue estimee en voiture', () {
    // ~5,56 km a vol d'oiseau -> ~7,2 km estimes, a 30 km/h.
    final l = LiaisonSousEtape.estimer(
      latDepart: 45.00,
      lonDepart: 6.0,
      latArrivee: 45.05,
      lonArrivee: 6.0,
    );
    expect(l.aPied, isFalse);
    expect(l.distanceKm, closeTo(7.23, 0.05));
    expect(l.dureeMinutes, 14);
    expect(l.libelle(_duree), endsWith('en voiture'));
  });

  test('distance en metres sous 1 km, duree minimale d\'une minute', () {
    final l = LiaisonSousEtape.estimer(
      latDepart: 45.0,
      lonDepart: 6.0,
      latArrivee: 45.0005,
      lonArrivee: 6.0,
    );
    expect(l.memeLieu, isFalse);
    expect(l.dureeMinutes, greaterThanOrEqualTo(1));
    expect(l.libelle(_duree), startsWith('≈ 70 m'));
  });

  test('vitesse de marche invalide : repli sur 4,5 km/h', () {
    final l = LiaisonSousEtape.estimer(
      latDepart: 45.00,
      lonDepart: 6.0,
      latArrivee: 45.01,
      lonArrivee: 6.0,
      vitesseMarcheKmh: 0,
    );
    expect(l.dureeMinutes, 19);
  });
}
