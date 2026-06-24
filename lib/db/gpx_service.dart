import 'dart:io';
import 'dart:math';
import 'package:gpx/gpx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Résultat du calcul d'une trace GPX : distance totale et dénivelés.
class GpxStats {
  final double distanceKm;
  final int denivelePositifM;
  final int deniveleNegatifM;
  final int nombrePoints;

  GpxStats({
    required this.distanceKm,
    required this.denivelePositifM,
    required this.deniveleNegatifM,
    required this.nombrePoints,
  });
}

/// Service de lecture de fichiers GPX et de calcul de statistiques
/// (distance, dénivelé positif/négatif) à partir des points de la trace.
class GpxService {
  static const _uuid = Uuid();

  // Seuil de lissage : les variations d'altitude point à point en dessous
  // de ce seuil sont ignorées dans le calcul du dénivelé. Le bruit GPS sur
  // l'altitude (souvent +/- 5-10m) gonflerait artificiellement le
  // dénivelé total sans ce filtrage.
  static const double _seuilLissageM = 3.0;

  /// Parse un fichier GPX et calcule ses statistiques (distance, dénivelé).
  Future<GpxStats> calculerStats(String gpxFilePath) async {
    final file = File(gpxFilePath);
    final content = await file.readAsString();
    final gpxData = GpxReader().fromString(content);

    // Récupère tous les points de toutes les tracks/segments, dans l'ordre.
    final points = <Wpt>[];
    for (final track in gpxData.trks) {
      for (final segment in track.trksegs) {
        points.addAll(segment.trkpts);
      }
    }

    // Si aucune track, on retombe sur les routes (rtes) s'il y en a.
    if (points.isEmpty) {
      for (final route in gpxData.rtes) {
        points.addAll(route.rtepts);
      }
    }

    if (points.length < 2) {
      return GpxStats(
        distanceKm: 0,
        denivelePositifM: 0,
        deniveleNegatifM: 0,
        nombrePoints: points.length,
      );
    }

    double distanceTotaleM = 0;
    double denivelePositif = 0;
    double deniveleNegatif = 0;

    double? altitudeLissee;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      if (a.lat != null && a.lon != null && b.lat != null && b.lon != null) {
        distanceTotaleM += _distanceHaversine(a.lat!, a.lon!, b.lat!, b.lon!);
      }

      // Calcul du dénivelé avec lissage simple pour réduire le bruit GPS.
      if (b.ele != null) {
        altitudeLissee ??= a.ele;
        if (altitudeLissee != null) {
          final delta = b.ele! - altitudeLissee;
          if (delta.abs() >= _seuilLissageM) {
            if (delta > 0) {
              denivelePositif += delta;
            } else {
              deniveleNegatif += delta.abs();
            }
            altitudeLissee = b.ele;
          }
        }
      }
    }

    return GpxStats(
      distanceKm: distanceTotaleM / 1000,
      denivelePositifM: denivelePositif.round(),
      deniveleNegatifM: deniveleNegatif.round(),
      nombrePoints: points.length,
    );
  }

  /// Distance en mètres entre deux points GPS, formule de Haversine
  /// (approximation suffisante pour des distances de randonnée, ne tient
  /// pas compte du relief — la distance "à vol d'oiseau" segment par
  /// segment, sommée sur tous les segments, donne une bonne approximation
  /// de la distance parcourue au sol pour une trace suffisamment dense).
  double _distanceHaversine(double lat1, double lon1, double lat2, double lon2) {
    const rayonTerreM = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return rayonTerreM * c;
  }

  double _degToRad(double deg) => deg * (pi / 180);

  /// Copie un fichier GPX importé vers le dossier géré par l'app, pour un
  /// jour donné. Suit la même convention que MediaStorageService.
  Future<String> copierGpxPourJour({
    required int jourId,
    required String sourcePath,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final jourDir = Directory(p.join(docsDir.path, 'media', 'jour_$jourId'));
    if (!await jourDir.exists()) {
      await jourDir.create(recursive: true);
    }

    final destPath = p.join(jourDir.path, '${_uuid.v4()}.gpx');
    await File(sourcePath).copy(destPath);
    return destPath;
  }
}
