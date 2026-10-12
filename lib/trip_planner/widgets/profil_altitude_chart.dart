import 'package:flutter/material.dart';

/// Graphique altitude en fonction de la distance cumulee du trace
/// d'un trajet. Dessine la courbe d'altitude avec un degrade discret,
/// les reperes min/max d'altitude et les bornes de distance. Simple
/// CustomPainter : pas de dependance de graphiques externe.
class ProfilAltitudeChart extends StatelessWidget {
  /// Couples [distance_km, altitude_m] dans l'ordre du parcours.
  final List<List<double>> profil;

  const ProfilAltitudeChart({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    if (profil.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('Profil d\'altitude indisponible pour ce trajet.'),
        ),
      );
    }
    final altitudes = profil.map((p) => p[1]).toList();
    var altitudeMin = altitudes.reduce((a, b) => a < b ? a : b);
    var altitudeMax = altitudes.reduce((a, b) => a > b ? a : b);
    // Marge verticale de 10% minimum pour eviter une courbe plate
    // collee aux bords quand le terrain est presque uniforme.
    final marge = (altitudeMax - altitudeMin).abs();
    if (marge < 20) {
      altitudeMin -= 10;
      altitudeMax += 10;
    } else {
      altitudeMin -= marge * 0.1;
      altitudeMax += marge * 0.1;
    }
    final distanceMax = profil.last[0];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _ProfilPainter(
              profil: profil,
              altitudeMin: altitudeMin,
              altitudeMax: altitudeMax,
              distanceMax: distanceMax,
              couleur: Theme.of(context).colorScheme.primary,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${altitudeMax.round()} m',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              'altitude min ${altitudeMin.round()} m',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0 km',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              '${distanceMax.toStringAsFixed(1)} km',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfilPainter extends CustomPainter {
  final List<List<double>> profil;
  final double altitudeMin;
  final double altitudeMax;
  final double distanceMax;
  final Color couleur;

  _ProfilPainter({
    required this.profil,
    required this.altitudeMin,
    required this.altitudeMax,
    required this.distanceMax,
    required this.couleur,
  });

  double _x(double distance, double largeur) =>
      distanceMax <= 0 ? 0 : distance / distanceMax * largeur;

  double _y(double altitude, double hauteur) =>
      altitudeMax == altitudeMin
          ? hauteur / 2
          : hauteur -
              (altitude - altitudeMin) / (altitudeMax - altitudeMin) * hauteur;

  @override
  void paint(Canvas canvas, Size size) {
    if (profil.length < 2 || distanceMax <= 0) return;

    final chemin = Path()..moveTo(_x(profil.first[0], size.width), _y(profil.first[1], size.height));
    for (final point in profil.skip(1)) {
      chemin.lineTo(
        _x(point[0], size.width),
        _y(point[1], size.height),
      );
    }

    // Aire sous la courbe, degrade du fond vers la couleur du theme.
    final aire = Path.from(chemin)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final degrade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          couleur.withValues(alpha: 0.35),
          couleur.withValues(alpha: 0.05),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(aire, degrade);

    // Trait de la courbe.
    canvas.drawPath(
      chemin,
      Paint()
        ..color = couleur
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ProfilPainter old) =>
      old.profil != profil ||
      old.altitudeMin != altitudeMin ||
      old.altitudeMax != altitudeMax ||
      old.couleur != couleur;
}
