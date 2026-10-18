// Tests des totaux automatiques d'un trek (somme des jours) et de la
// lecture des traces GPX (points, statistiques, profil d'altitude).

import 'package:flutter_test/flutter_test.dart';
import 'package:les_baroudeurs/db/gpx_service.dart';
import 'package:les_baroudeurs/models/jour_trek.dart';
import 'package:les_baroudeurs/models/totaux_trek.dart';

JourTrek _jour(
  int numero, {
  double? distance,
  int? positif,
  int? negatif,
  String? gpx,
}) =>
    JourTrek(
      trekId: 1,
      numeroJour: numero,
      date: '2026-07-0$numero',
      distanceKm: distance,
      denivelePositifM: positif,
      deniveleNegatifM: negatif,
      cheminGpx: gpx,
    );

String _gpx(List<String> points) => '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
${points.join('\n')}
  </trkseg></trk>
</gpx>''';

void main() {
  group('TotauxTrek', () {
    test('somme les jours renseignés et ignore les valeurs absentes', () {
      final totaux = TotauxTrek.depuisJours([
        _jour(1, distance: 12.3, positif: 800, negatif: 300, gpx: '/a.gpx'),
        _jour(2, distance: 8.45, positif: 450),
        _jour(3),
      ]);
      expect(totaux.distanceKm, closeTo(20.75, 0.001));
      expect(totaux.denivelePositifM, 1250);
      expect(totaux.deniveleNegatifM, 300);
      expect(totaux.nombreJours, 3);
      expect(totaux.nombreJoursAvecGpx, 1);
      expect(totaux.estRenseigne, isTrue);
    });

    test('valeurs nulles quand aucun jour n\'est renseigné', () {
      final totaux = TotauxTrek.depuisJours([_jour(1), _jour(2)]);
      expect(totaux.distanceKm, isNull);
      expect(totaux.denivelePositifM, isNull);
      expect(totaux.deniveleNegatifM, isNull);
      expect(totaux.estRenseigne, isFalse);
    });

    test('arrondit la distance pour éviter les erreurs flottantes', () {
      final totaux = TotauxTrek.depuisJours([
        _jour(1, distance: 0.1),
        _jour(2, distance: 0.2),
      ]);
      expect(totaux.distanceKm, 0.3);
    });

    test('formaterDistanceKm', () {
      expect(formaterDistanceKm(12.34), '12,3 km');
      expect(formaterDistanceKm(8.0), '8 km');
      expect(formaterDistanceKm(7.96), '8 km');
    });
  });

  group('Trace GPX', () {
    test('lit les points et calcule distance et dénivelés', () {
      // Trois points espacés d'environ 1,11 km vers le nord.
      final points = GpxService.parserPoints(_gpx([
        '<trkpt lat="45.00" lon="6.0"><ele>1000</ele></trkpt>',
        '<trkpt lat="45.01" lon="6.0"><ele>1100</ele></trkpt>',
        '<trkpt lat="45.02" lon="6.0"><ele>1050</ele></trkpt>',
      ]));
      expect(points, hasLength(3));
      final stats = GpxService.statsDepuisPoints(points);
      expect(stats.distanceKm, closeTo(2.224, 0.01));
      expect(stats.denivelePositifM, 100);
      expect(stats.deniveleNegatifM, 50);
      expect(stats.nombrePoints, 3);
    });

    test('ignore le bruit d\'altitude sous le seuil de lissage', () {
      final points = GpxService.parserPoints(_gpx([
        '<trkpt lat="45.000" lon="6.0"><ele>1000</ele></trkpt>',
        '<trkpt lat="45.001" lon="6.0"><ele>1002</ele></trkpt>',
        '<trkpt lat="45.002" lon="6.0"><ele>1000</ele></trkpt>',
      ]));
      final stats = GpxService.statsDepuisPoints(points);
      expect(stats.denivelePositifM, 0);
      expect(stats.deniveleNegatifM, 0);
    });

    test('retombe sur les routes quand il n\'y a pas de track', () {
      const contenu = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <rte>
    <rtept lat="45.0" lon="6.0"/>
    <rtept lat="45.1" lon="6.1"/>
  </rte>
</gpx>''';
      final trace = TraceGpx(GpxService.parserPoints(contenu));
      expect(trace.points, hasLength(2));
      expect(trace.estVide, isFalse);
      expect(trace.aDesAltitudes, isFalse);
      expect(trace.profilAltitude(), isEmpty);
    });

    test('profil d\'altitude : distance cumulée croissante', () {
      final trace = TraceGpx(GpxService.parserPoints(_gpx([
        '<trkpt lat="45.00" lon="6.0"><ele>1000</ele></trkpt>',
        '<trkpt lat="45.01" lon="6.0"></trkpt>',
        '<trkpt lat="45.02" lon="6.0"><ele>1200</ele></trkpt>',
      ])));
      final profil = trace.profilAltitude();
      // Le point sans altitude compte pour la distance mais n'est pas tracé.
      expect(profil, hasLength(2));
      expect(profil.first, [0.0, 1000.0]);
      expect(profil.last[0], closeTo(2.224, 0.01));
      expect(profil.last[1], 1200);
    });

    test('profil d\'altitude échantillonné sur les traces denses', () {
      final points = [
        for (var i = 0; i < 1000; i++)
          PointGpx(
            latitude: 45 + i * 0.0001,
            longitude: 6,
            altitudeM: 1000.0 + i,
          ),
      ];
      final profil = TraceGpx(points).profilAltitude(maxPoints: 100);
      expect(profil, hasLength(100));
      expect(profil.first[1], 1000);
      expect(profil.last[1], 1999);
      for (var i = 1; i < profil.length; i++) {
        expect(profil[i][0], greaterThanOrEqualTo(profil[i - 1][0]));
      }
    });
  });
}
